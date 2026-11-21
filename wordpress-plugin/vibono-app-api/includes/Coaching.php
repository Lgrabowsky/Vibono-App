<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\CoachingPoints;

defined( 'ABSPATH' ) || exit;

/**
 * Punkte für den Coaching-Fortschritt.
 *
 * Grundlage sind die Häkchen "Lektion erledigt" (Sync-Sammlung lessons_done), egal ob sie in der App
 * oder auf vibono.de unter "Mein Coaching" gesetzt werden:
 *  - Lektion erledigt:   earn_lesson_done Punkte, einmal je Lektion, höchstens lesson_done_daily_cap pro Tag.
 *  - Kurs abgeschlossen: earn_course_done Punkte, sobald alle veröffentlichten Lektionen des Kurses erledigt sind.
 * Häkchen entfernen und wieder setzen bringt nichts (Idempotenz-Schlüssel je Lektion bzw. Kurs).
 * Was beim ersten Abgleich von der Website übernommen wird, ist Vergangenheit und bringt keine Punkte.
 */
class Coaching {

	/** Nutzer-Meta: Zeitpunkt, ab dem Website-Häkchen dieser Person Punkte bringen. */
	const BASELINE_META = '_vibono_coaching_baseline';

	public static function has_baseline( int $user_id ): bool {
		return (bool) get_user_meta( $user_id, self::BASELINE_META, true );
	}

	/** Nach dem ersten Abgleich mit der Website: ab jetzt zählen neue Website-Häkchen. */
	public static function mark_baseline( int $user_id ): void {
		if ( ! self::has_baseline( $user_id ) ) {
			update_user_meta( $user_id, self::BASELINE_META, time() );
		}
	}

	/**
	 * Wird von SyncStore::put aufgerufen, wenn ein Eintrag in lessons_done oder courses_done neu
	 * gesetzt wurde (vorher nicht vorhanden oder gelöscht). Fehler dürfen die Synchronisation nicht stören.
	 */
	public static function on_done( int $user_id, string $collection, string $key, string $source ): void {
		try {
			if ( ! Settings::get( 'points_enabled' ) || ! ctype_digit( $key ) ) {
				return;
			}
			if ( 'lessons_done' === $collection ) {
				self::lesson_done( $user_id, (int) $key, $source );
			} elseif ( 'courses_done' === $collection ) {
				self::maybe_course_done( $user_id, (int) $key, $source );
			}
		} catch ( \Throwable $e ) {
			Plugin::report( $e, 'Coaching-Punkte' );
		}
	}

	private static function is_lesson( int $post_id, int $user_id ): bool {
		$p = get_post( $post_id );
		return $p && 'publish' === $p->post_status && Content::post_type( 'lesson' ) === $p->post_type && Membership::can_view( $user_id, $post_id );
	}

	public static function lesson_done( int $user_id, int $post_id, string $source ): array {
		if ( ! self::is_lesson( $post_id, $user_id ) ) {
			return array( 'awarded_points' => 0, 'blocked' => 'not_a_lesson' );
		}
		$points = (int) Settings::get( 'earn_lesson_done' );
		$block  = CoachingPoints::lesson_block_reason(
			$source,
			self::has_baseline( $user_id ),
			Points::count_today( $user_id, 'lesson_done' ),
			(int) Settings::get( 'lesson_done_daily_cap' ),
			$points
		);
		$result = array( 'awarded_points' => 0, 'blocked' => $block );
		if ( null === $block ) {
			$r      = Points::earn(
				$user_id,
				'lesson_done',
				$points,
				array(
					'idempotency_key' => 'lesson_done:' . $user_id . ':' . $post_id,
					'label'           => 'Lektion erledigt: ' . html_entity_decode( wp_strip_all_tags( get_the_title( $post_id ) ), ENT_QUOTES, 'UTF-8' ),
					'ref_type'        => 'lesson',
					'ref_id'          => $post_id,
				)
			);
			$result = array( 'awarded_points' => $r['awarded_points'], 'blocked' => $r['already_awarded'] ? 'already_awarded' : null );
		}
		// Kursbonus auch dann prüfen, wenn die Lektion selbst wegen Tageslimit keine Punkte bringt.
		if ( 'history' !== $block ) {
			$tax   = Content::lesson_taxonomy();
			$terms = $tax ? get_the_terms( $post_id, $tax ) : false;
			if ( is_array( $terms ) ) {
				foreach ( $terms as $t ) {
					self::maybe_course_done( $user_id, (int) $t->term_id, $source );
				}
			}
		}
		return $result;
	}

	/** Kursbonus, wenn alle Lektionen des Kurses erledigt sind. */
	public static function maybe_course_done( int $user_id, int $term_id, string $source ): int {
		$points = (int) Settings::get( 'earn_course_done' );
		$tax    = Content::lesson_taxonomy();
		if ( $points <= 0 || ! $tax || ( 'web' === $source && ! self::has_baseline( $user_id ) ) ) {
			return 0;
		}
		$term = get_term( $term_id, $tax );
		if ( ! $term || is_wp_error( $term ) ) {
			return 0;
		}
		$ids = get_posts(
			array(
				'post_type'      => Content::post_type( 'lesson' ),
				'post_status'    => 'publish',
				'posts_per_page' => 500,
				'fields'         => 'ids',
				'tax_query'      => array( array( 'taxonomy' => $tax, 'terms' => $term_id ) ), // phpcs:ignore
			)
		);
		if ( ! CoachingPoints::course_complete( array_map( 'intval', $ids ), SyncStore::current_map( $user_id, 'lessons_done' ) ) ) {
			return 0;
		}
		$r = Points::earn(
			$user_id,
			'course_done',
			$points,
			array(
				'idempotency_key' => 'course_done:' . $user_id . ':' . $term_id,
				'label'           => 'Kurs abgeschlossen: ' . html_entity_decode( $term->name, ENT_QUOTES, 'UTF-8' ),
				'ref_type'        => 'course',
				'ref_id'          => $term_id,
			)
		);
		return (int) $r['awarded_points'];
	}
}
