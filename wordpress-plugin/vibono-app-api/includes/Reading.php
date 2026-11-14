<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\ReadingRules;

defined( 'ABSPATH' ) || exit;

/**
 * Lese-Nachweis für Punkte "Artikel gelesen" (App und Website).
 *
 * Die App bzw. das Web-Skript startet eine Lese-Session, meldet alle ~10 s einen Heartbeat
 * (nur, wenn der Artikel sichtbar ist) und schließt sie ab. Der Server erkennt Aktivzeit nur an,
 * soweit tatsächlich Zeit vergangen ist, und prüft Scrolltiefe und optional eine Quizfrage.
 */
class Reading {

	const QUIZ_META = '_vibono_quiz';

	/** Immer aktiv: Aufräumen per Cron; Quiz-Box im Editor nur, wenn Lesepunkte irgendwo vergeben werden. */
	public static function init(): void {
		Plugin::hook( 'vibono_points_daily', array( self::class, 'cleanup' ) );
		$used = Settings::get( 'points_enabled' ) && 'off' !== Settings::get( 'reading_quiz_mode' )
			&& ( Settings::on( 'module_api' ) || Settings::on( 'module_web_reading' ) );
		if ( $used && is_admin() ) {
			Plugin::hook( 'add_meta_boxes', array( self::class, 'meta_box' ) );
			Plugin::hook( 'save_post', array( self::class, 'save_quiz' ), 10, 2 );
		}
	}

	/** Modul "Lese-Nachweis auf der Website": Skript auf belohnten Beitragsseiten für eingeloggte Nutzer*innen. */
	public static function init_web(): void {
		Plugin::hook( 'wp_enqueue_scripts', array( self::class, 'enqueue_web' ) );
	}

	public static function eligible( int $post_id ): bool {
		$post = get_post( $post_id );
		return $post && 'publish' === $post->post_status && in_array( $post->post_type, (array) Settings::get( 'reading_eligible_types' ), true );
	}

	public static function reward_key( int $user_id, int $post_id ): string {
		return 'article_read:' . $user_id . ':' . $post_id;
	}

	public static function points_for( int $user_id, int $post_id ): int {
		if ( ! self::eligible( $post_id ) || Points::has_key( self::reward_key( $user_id, $post_id ) ) ) {
			return 0;
		}
		return Core\PointsMath::earn( (int) Settings::get( 'earn_article_read' ), Campaigns::all_for_math(), time(), 'article_read' )['points'];
	}

	public static function word_count( int $post_id ): int {
		$cached = get_post_meta( $post_id, '_vibono_word_count', true );
		$mod    = get_post_modified_time( 'U', true, $post_id );
		if ( is_array( $cached ) && (int) $cached['mod'] === (int) $mod ) {
			return (int) $cached['words'];
		}
		$words = ReadingRules::word_count( (string) get_post_field( 'post_content', $post_id ) );
		update_post_meta( $post_id, '_vibono_word_count', array( 'mod' => $mod, 'words' => $words ) );
		return $words;
	}

	public static function quiz( int $post_id ): ?array {
		if ( 'off' === Settings::get( 'reading_quiz_mode' ) ) {
			return null;
		}
		$q = get_post_meta( $post_id, self::QUIZ_META, true );
		if ( ! is_array( $q ) || empty( $q['question'] ) || count( (array) ( $q['answers'] ?? array() ) ) < 2 ) {
			return null;
		}
		return $q;
	}

	/** @return array|\WP_Error */
	public static function start( int $user_id, int $post_id, string $channel ) {
		global $wpdb;
		if ( ! self::eligible( $post_id ) || ! Membership::can_view( $user_id, $post_id ) ) {
			return Plugin::error( 'vibono_not_rewardable', 'Für diesen Beitrag gibt es keine Lesepunkte.', 404 );
		}
		if ( Points::has_key( self::reward_key( $user_id, $post_id ) ) ) {
			return Plugin::error( 'vibono_already_rewarded', 'Für diesen Artikel hast du schon Punkte bekommen.', 409 );
		}
		if ( 'required' === Settings::get( 'reading_quiz_mode' ) && ! self::quiz( $post_id ) ) {
			return Plugin::error( 'vibono_not_rewardable', 'Für diesen Beitrag gibt es keine Lesepunkte.', 404 );
		}
		$words = self::word_count( $post_id );
		$min   = ReadingRules::min_active_seconds(
			$words,
			(int) Settings::get( 'reading_wpm' ),
			(float) Settings::get( 'reading_min_factor' ),
			(int) Settings::get( 'reading_min_seconds' ),
			(int) Settings::get( 'reading_max_seconds' )
		);
		$id  = bin2hex( random_bytes( 16 ) );
		$now = time();
		$wpdb->insert(
			Install::table( 'reading' ),
			array(
				'id'                 => $id,
				'user_id'            => $user_id,
				'post_id'            => $post_id,
				'word_count'         => $words,
				'min_active_seconds' => $min,
				'started_at'         => $now,
				'last_beat_at'       => $now,
				'channel'            => 'web' === $channel ? 'web' : 'app',
			)
		);
		$quiz = self::quiz( $post_id );
		return array(
			'session_id'                 => $id,
			'post_id'                    => $post_id,
			'word_count'                 => $words,
			'min_active_seconds'         => $min,
			'min_scroll_depth'           => (float) Settings::get( 'reading_min_scroll' ),
			'heartbeat_interval_seconds' => (int) Settings::get( 'reading_heartbeat_seconds' ),
			'points'                     => self::points_for( $user_id, $post_id ),
			'quiz'                       => $quiz ? array( 'question' => $quiz['question'], 'answers' => array_values( $quiz['answers'] ) ) : null,
		);
	}

	private static function session( int $user_id, string $id ): ?array {
		global $wpdb;
		$t = Install::table( 'reading' );
		$s = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $t WHERE id = %s AND user_id = %d", $id, $user_id ), ARRAY_A );
		return $s ?: null;
	}

	/** @return array|\WP_Error */
	public static function heartbeat( int $user_id, string $id, int $active_seconds, float $scroll ) {
		global $wpdb;
		$s = self::session( $user_id, $id );
		if ( ! $s || (int) $s['completed'] ) {
			return Plugin::error( 'vibono_reading_session_not_found', 'Lese-Session nicht gefunden.', 404 );
		}
		$new = ReadingRules::beat( $s, $active_seconds, $scroll, time(), (int) Settings::get( 'reading_heartbeat_seconds' ) );
		$wpdb->update( Install::table( 'reading' ), $new, array( 'id' => $id ) );
		$s = array_merge( $s, $new );
		return array(
			'accepted_active_seconds' => (int) $s['accepted_seconds'],
			'scroll_depth'            => (float) $s['scroll_depth'],
			'ready_to_complete'       => ! ReadingRules::missing( $s, (int) $s['min_active_seconds'], (float) Settings::get( 'reading_min_scroll' ) ),
		);
	}

	/** @return array|\WP_Error */
	public static function complete( int $user_id, string $id, ?int $quiz_answer ) {
		global $wpdb;
		$s = self::session( $user_id, $id );
		if ( ! $s || (int) $s['completed'] ) {
			return Plugin::error( 'vibono_reading_session_not_found', 'Lese-Session nicht gefunden.', 404 );
		}
		$min_scroll = (float) Settings::get( 'reading_min_scroll' );
		$missing    = ReadingRules::missing( $s, (int) $s['min_active_seconds'], $min_scroll );
		if ( $missing ) {
			return Plugin::error(
				'vibono_reading_incomplete',
				'Lies den Artikel bitte zu Ende, dann gibt es Punkte.',
				422,
				array(
					'progress' => array(
						'missing'                 => $missing,
						'accepted_active_seconds' => (int) $s['accepted_seconds'],
						'min_active_seconds'      => (int) $s['min_active_seconds'],
						'scroll_depth'            => (float) $s['scroll_depth'],
						'min_scroll_depth'        => $min_scroll,
					),
				)
			);
		}
		$quiz = self::quiz( (int) $s['post_id'] );
		if ( $quiz ) {
			if ( (int) $s['quiz_failed_at'] && time() - (int) $s['quiz_failed_at'] < 30 ) {
				return Plugin::error( 'vibono_quiz_wrong', 'Versuch es in ein paar Sekunden noch einmal.', 422 );
			}
			if ( null === $quiz_answer || (int) $quiz['correct'] !== $quiz_answer ) {
				$wpdb->update( Install::table( 'reading' ), array( 'quiz_failed_at' => time() ), array( 'id' => $id ) );
				return Plugin::error( 'vibono_quiz_wrong', 'Das stimmt leider nicht. Schau noch einmal in den Artikel.', 422 );
			}
		}
		if ( Points::count_today( $user_id, 'article_read' ) >= (int) Settings::get( 'article_read_daily_cap' ) ) {
			$wpdb->update( Install::table( 'reading' ), array( 'completed' => 1 ), array( 'id' => $id ) );
			return Plugin::error( 'vibono_daily_cap_reached', 'Für heute hast du alle Lesepunkte gesammelt. Morgen geht es weiter!', 422 );
		}
		$wpdb->update( Install::table( 'reading' ), array( 'completed' => 1 ), array( 'id' => $id ) );

		$post_id = (int) $s['post_id'];
		$r       = Points::earn(
			$user_id,
			'article_read',
			(int) Settings::get( 'earn_article_read' ),
			array(
				'idempotency_key' => self::reward_key( $user_id, $post_id ),
				'label'           => 'Gelesen: ' . wp_strip_all_tags( get_the_title( $post_id ) ),
				'ref_type'        => 'post',
				'ref_id'          => $post_id,
				'meta'            => array(
					'channel' => $s['channel'],
					'seconds' => (int) $s['accepted_seconds'],
					'scroll'  => (float) $s['scroll_depth'],
					'quiz'    => (bool) $quiz,
				),
			)
		);
		// Lektion gilt auch als erledigt (Häkchen in "Mein Coaching").
		if ( get_post_type( $post_id ) === Settings::get( 'lesson_post_type' ) ) {
			SyncStore::apply(
				$user_id,
				array(
					'collection' => 'lessons_done',
					'key'        => (string) $post_id,
					'op'         => 'upsert',
					'updated_at' => gmdate( 'c' ),
				),
				Plugin::now_ms()
			);
		}
		unset( $r['entry_id'] );
		$r['balance'] = Points::balance( $user_id );
		return $r;
	}

	public static function cleanup(): void {
		global $wpdb;
		$t = Install::table( 'reading' );
		$wpdb->query( $wpdb->prepare( "DELETE FROM $t WHERE started_at < %d", time() - 2 * DAY_IN_SECONDS ) );
	}

	// ------------------------------------------------------------- Website

	public static function enqueue_web(): void {
		if ( ! is_user_logged_in() || ! is_singular() || ! Settings::get( 'points_enabled' ) ) {
			return;
		}
		$post_id = get_queried_object_id();
		if ( ! self::eligible( $post_id ) || ! self::points_for( get_current_user_id(), $post_id ) ) {
			return;
		}
		wp_enqueue_script( 'vibono-reading', VIBONO_API_URL . 'assets/reading-tracker.js', array(), VIBONO_API_VERSION, true );
		wp_localize_script(
			'vibono-reading',
			'vibonoReading',
			array(
				'root'    => esc_url_raw( rest_url( VIBONO_API_NS . '/' ) ),
				'nonce'   => wp_create_nonce( 'wp_rest' ),
				'postId'  => $post_id,
				'content' => apply_filters( 'vibono_reading_content_selector', '.entry-content, article, main' ),
			)
		);
	}

	// ----------------------------------------------- Quizfrage im Editor

	public static function meta_box(): void {
		foreach ( (array) Settings::get( 'reading_eligible_types' ) as $type ) {
			add_meta_box( 'vibono_quiz', 'Vibono-Punkte: Quizfrage', array( self::class, 'render_meta_box' ), $type, 'side' );
		}
	}

	public static function render_meta_box( \WP_Post $post ): void {
		$q = get_post_meta( $post->ID, self::QUIZ_META, true );
		$q = is_array( $q ) ? $q : array( 'question' => '', 'answers' => array( '', '', '' ), 'correct' => 0 );
		wp_nonce_field( 'vibono_quiz', 'vibono_quiz_nonce' );
		echo '<p><label>Frage<br><input type="text" class="widefat" name="vibono_quiz[question]" value="' . esc_attr( $q['question'] ) . '"></label></p>';
		for ( $i = 0; $i < 3; $i++ ) {
			$a = $q['answers'][ $i ] ?? '';
			echo '<p><label><input type="radio" name="vibono_quiz[correct]" value="' . (int) $i . '" ' . checked( (int) $q['correct'], $i, false ) . '> Antwort ' . ( $i + 1 ) . '</label>';
			echo '<input type="text" class="widefat" name="vibono_quiz[answers][]" value="' . esc_attr( $a ) . '"></p>';
		}
		echo '<p class="description">Optional. Wenn gesetzt, gibt es Lesepunkte erst nach richtiger Antwort. Radio = richtige Antwort.</p>';
	}

	public static function save_quiz( int $post_id, \WP_Post $post ): void {
		if ( ! isset( $_POST['vibono_quiz_nonce'] ) || ! wp_verify_nonce( sanitize_key( $_POST['vibono_quiz_nonce'] ), 'vibono_quiz' ) || ! current_user_can( 'edit_post', $post_id ) ) {
			return;
		}
		$in      = (array) wp_unslash( $_POST['vibono_quiz'] ?? array() ); // phpcs:ignore
		$raw     = array_map( 'sanitize_text_field', (array) ( $in['answers'] ?? array() ) );
		$correct = $raw[ (int) ( $in['correct'] ?? 0 ) ] ?? '';
		$answers = array_values( array_filter( $raw, 'strlen' ) );
		$q       = sanitize_text_field( $in['question'] ?? '' );
		if ( '' === $q || count( $answers ) < 2 || '' === $correct ) {
			delete_post_meta( $post_id, self::QUIZ_META );
			return;
		}
		update_post_meta(
			$post_id,
			self::QUIZ_META,
			array(
				'question' => $q,
				'answers'  => $answers,
				'correct'  => (int) array_search( $correct, $answers, true ),
			)
		);
	}
}
