<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\RewardRules;

defined( 'ABSPATH' ) || exit;

/**
 * Prämien: Punkte einlösen gegen
 *  - exklusive Inhalte (Rezepte, Tipps, …): ein Beitrag wird für die Person dauerhaft freigeschaltet,
 *  - exklusive eBooks/PDFs: Datei aus der Mediathek, Download über kurzlebige signierte Links,
 *  - Rabatt auf Verlängerungen: persönlicher Einmal-Gutschein für den Shop auf vibono.de.
 *
 * Katalog in Tabelle vibono_rewards (Backend: Vibono-Punkte → Prämien), Einlösungen in
 * vibono_reward_unlocks, Abbuchung als Buchung "reward" im Punkte-Hauptbuch.
 * Eingelöst wird in der App (GET/POST /rewards, je Plattform einstellbar) oder auf vibono.de unter
 * Mein Konto → Vibono-Punkte. Es gibt keine Käufe: Punkte lassen sich nicht mit Geld kaufen.
 */
class Rewards {

	const NONCE = 'vibono_reward';

	private static $cache    = null;
	private static $by_post  = null;

	public static function module_on(): bool {
		return Settings::on( 'module_rewards' ) && (bool) Settings::get( 'points_enabled' );
	}

	public static function init(): void {
		if ( ! self::module_on() ) {
			return;
		}
		// Exklusive Beiträge auf der Website sperren, bis sie freigeschaltet sind.
		Plugin::hook( 'the_content', array( self::class, 'filter_content' ), 99 );
		Plugin::hook( 'get_the_excerpt', array( self::class, 'filter_excerpt' ), 99, 2 );
		Plugin::hook( 'template_redirect', array( self::class, 'handle_content_form' ) );
	}

	// ------------------------------------------------------------ Katalog

	public static function all(): array {
		if ( null === self::$cache ) {
			global $wpdb;
			$t           = Install::table( 'rewards' );
			$rows        = (array) $wpdb->get_results( "SELECT * FROM $t ORDER BY sort_order ASC, id ASC", ARRAY_A ); // phpcs:ignore
			self::$cache = array_map( array( self::class, 'from_row' ), $rows );
		}
		return self::$cache;
	}

	public static function flush(): void {
		self::$cache   = null;
		self::$by_post = null;
	}

	private static function from_row( array $r ): array {
		return array(
			'id'              => (int) $r['id'],
			'kind'            => $r['kind'],
			'title'           => $r['title'],
			'description'     => (string) $r['description'],
			'cost_points'     => (int) $r['cost_points'],
			'post_id'         => (int) $r['post_id'],
			'attachment_id'   => (int) $r['attachment_id'],
			'discount_type'   => $r['discount_type'] ?: 'fixed',
			'discount_amount' => (float) $r['discount_amount'],
			'product_ids'     => RewardRules::id_list( (string) $r['product_ids'] ),
			'valid_days'      => (int) $r['valid_days'],
			'per_user_limit'  => (int) $r['per_user_limit'],
			'enabled'         => (bool) $r['enabled'],
			'sort_order'      => (int) $r['sort_order'],
		);
	}

	public static function get( int $id ): ?array {
		foreach ( self::all() as $r ) {
			if ( $r['id'] === $id ) {
				return $r;
			}
		}
		return null;
	}

	/** Aktive Inhalts-Prämie für einen Beitrag (macht ihn exklusiv). */
	public static function for_post( int $post_id ): ?array {
		if ( null === self::$by_post ) {
			self::$by_post = array();
			foreach ( self::all() as $r ) {
				if ( 'content' === $r['kind'] && $r['enabled'] && $r['post_id'] ) {
					self::$by_post[ $r['post_id'] ] = $r;
				}
			}
		}
		return self::$by_post[ $post_id ] ?? null;
	}

	/** @return int|\WP_Error */
	public static function save( array $in, int $id = 0 ) {
		global $wpdb;
		list( $r, $err ) = RewardRules::normalize( $in );
		if ( $err ) {
			return new \WP_Error( 'invalid_reward', $err );
		}
		if ( 'content' === $r['kind'] && ! get_post( $r['post_id'] ) ) {
			return new \WP_Error( 'invalid_reward', 'Einen Beitrag mit dieser ID gibt es nicht.' );
		}
		if ( 'download' === $r['kind'] && ( 'attachment' !== get_post_type( $r['attachment_id'] ) || ! get_attached_file( $r['attachment_id'] ) ) ) {
			return new \WP_Error( 'invalid_reward', 'In der Mediathek gibt es keine Datei mit dieser ID.' );
		}
		if ( 'content' === $r['kind'] ) {
			$other = self::for_post( $r['post_id'] );
			if ( $other && $other['id'] !== $id ) {
				return new \WP_Error( 'invalid_reward', 'Für diesen Beitrag gibt es schon eine Prämie („' . $other['title'] . '“).' );
			}
		}
		$row = array(
			'kind'            => $r['kind'],
			'title'           => sanitize_text_field( $r['title'] ),
			'description'     => sanitize_textarea_field( $r['description'] ),
			'cost_points'     => $r['cost_points'],
			'post_id'         => $r['post_id'],
			'attachment_id'   => $r['attachment_id'],
			'discount_type'   => $r['discount_type'],
			'discount_amount' => $r['discount_amount'],
			'product_ids'     => implode( ',', $r['product_ids'] ),
			'valid_days'      => $r['valid_days'],
			'per_user_limit'  => $r['per_user_limit'],
			'enabled'         => $r['enabled'] ? 1 : 0,
			'sort_order'      => $r['sort_order'],
		);
		$t = Install::table( 'rewards' );
		if ( $id ) {
			$wpdb->update( $t, $row, array( 'id' => $id ) );
		} else {
			$row['created_at'] = gmdate( 'Y-m-d H:i:s' );
			$wpdb->insert( $t, $row );
			$id = (int) $wpdb->insert_id;
		}
		self::flush();
		return $id;
	}

	/** Prämie entfernen. Bereits eingelöste bleiben für die Personen erhalten (Abschalten statt Löschen empfohlen). */
	public static function delete( int $id ): void {
		global $wpdb;
		$wpdb->update( Install::table( 'rewards' ), array( 'enabled' => 0 ), array( 'id' => $id ) );
		$used = (int) $wpdb->get_var( $wpdb->prepare( 'SELECT COUNT(*) FROM ' . Install::table( 'reward_unlocks' ) . ' WHERE reward_id = %d', $id ) );
		if ( ! $used ) {
			$wpdb->delete( Install::table( 'rewards' ), array( 'id' => $id ) );
		}
		self::flush();
	}

	// ------------------------------------------------------------ Kanäle

	/** Darf diese Prämienart in diesem Kanal eingelöst werden? Website immer, App je Plattform. */
	public static function allowed_in( string $kind, string $channel ): bool {
		if ( 'web' === $channel ) {
			return true;
		}
		$pf = 'android' === $channel ? 'android' : 'ios';
		return ! empty( ( (array) Settings::get( 'rewards_app_' . $pf ) )[ $kind ] );
	}

	/** Prämienarten, die die App auf dieser Plattform anzeigt. */
	public static function app_kinds( string $platform ): array {
		return array_values( array_filter( RewardRules::KINDS, static fn( $k ) => self::allowed_in( $k, $platform ) ) );
	}

	// ------------------------------------------------------- Einlösungen

	public static function unlock_rows( int $user_id ): array {
		global $wpdb;
		$t = Install::table( 'reward_unlocks' );
		return (array) $wpdb->get_results( $wpdb->prepare( "SELECT * FROM $t WHERE user_id = %d ORDER BY id DESC", $user_id ), ARRAY_A );
	}

	public static function times_redeemed( int $user_id, int $reward_id ): int {
		global $wpdb;
		$t = Install::table( 'reward_unlocks' );
		return (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM $t WHERE user_id = %d AND reward_id = %d", $user_id, $reward_id ) );
	}

	/** Darf die Person einen exklusiven Beitrag sehen? (Ohne Prämie: ja.) */
	public static function can_view_post( int $user_id, int $post_id ): bool {
		$r = self::module_on() ? self::for_post( $post_id ) : null;
		if ( ! $r ) {
			return true;
		}
		if ( $user_id && ( user_can( $user_id, 'edit_post', $post_id ) || user_can( $user_id, 'manage_options' ) ) ) {
			return true;
		}
		return $user_id && self::times_redeemed( $user_id, $r['id'] ) > 0;
	}

	/** Kurzinfo für Inhalte (ContentSummary.reward). */
	public static function post_info( int $user_id, int $post_id ): ?array {
		$r = self::module_on() ? self::for_post( $post_id ) : null;
		if ( ! $r ) {
			return null;
		}
		return array(
			'id'          => $r['id'],
			'cost_points' => $r['cost_points'],
			'unlocked'    => self::can_view_post( $user_id, $post_id ),
		);
	}

	/**
	 * Prämie einlösen: prüfen, Punkte abbuchen, Prämie ausliefern. Schlägt das Ausliefern fehl
	 * (z. B. Gutschein), werden die Punkte sofort zurückgebucht.
	 *
	 * @param string $channel ios|android|web
	 * @return array|\WP_Error ['unlock' => RewardUnlock, 'balance' => int]
	 */
	public static function redeem( int $user_id, int $reward_id, string $channel ) {
		$reward = self::get( $reward_id );
		if ( ! $reward || ! $reward['enabled'] ) {
			return Plugin::error( 'vibono_reward_not_found', 'Diese Prämie gibt es nicht mehr.', 404 );
		}
		return Points::with_lock(
			$user_id,
			static function () use ( $user_id, $reward, $channel ) {
				$n   = self::times_redeemed( $user_id, $reward['id'] );
				$err = RewardRules::check( $reward, Points::balance( $user_id ), $n, self::allowed_in( $reward['kind'], $channel ) );
				if ( $err ) {
					return self::error( $err, $reward );
				}
				$entry = Points::book(
					$user_id,
					-$reward['cost_points'],
					'reward',
					'Prämie: ' . $reward['title'],
					array(
						'ref_type'        => 'reward',
						'ref_id'          => $reward['id'],
						'idempotency_key' => 'reward:' . $reward['id'] . ':' . $user_id . ':' . ( $n + 1 ),
						'meta'            => array( 'channel' => $channel ),
					)
				);
				if ( ! $entry ) {
					return Plugin::error( 'vibono_busy', 'Bitte einen Moment warten und noch einmal versuchen.', 429 );
				}
				$coupon = null;
				if ( 'renewal_discount' === $reward['kind'] ) {
					$coupon = WooCommerce::create_reward_coupon( $user_id, $reward );
					if ( is_wp_error( $coupon ) ) {
						Points::book(
							$user_id,
							$reward['cost_points'],
							'reward_refund',
							'Prämie zurückgebucht: ' . $reward['title'],
							array( 'ref_type' => 'reward', 'ref_id' => $reward['id'], 'idempotency_key' => 'reward_refund:' . $entry )
						);
						return $coupon;
					}
				}
				global $wpdb;
				$wpdb->insert(
					Install::table( 'reward_unlocks' ),
					array(
						'user_id'     => $user_id,
						'reward_id'   => $reward['id'],
						'kind'        => $reward['kind'],
						'points'      => $reward['cost_points'],
						'ledger_id'   => $entry,
						'coupon_code' => $coupon['code'] ?? '',
						'coupon_id'   => $coupon['coupon_id'] ?? 0,
						'channel'     => $channel,
						'created_at'  => gmdate( 'Y-m-d H:i:s' ),
						'expires_at'  => isset( $coupon['expires_at'] ) ? gmdate( 'Y-m-d H:i:s', $coupon['expires_at'] ) : null,
					)
				);
				$row = $wpdb->get_row( $wpdb->prepare( 'SELECT * FROM ' . Install::table( 'reward_unlocks' ) . ' WHERE id = %d', (int) $wpdb->insert_id ), ARRAY_A );
				do_action( 'vibono_reward_redeemed', $user_id, $reward, $row );
				return array(
					'unlock'  => self::format_unlock( $row, $channel ),
					'balance' => Points::balance( $user_id ),
				);
			}
		);
	}

	private static function error( string $code, array $reward ): \WP_Error {
		$map = array(
			'disabled'            => array( 404, 'Diese Prämie gibt es nicht mehr.' ),
			'not_available_here'  => array( 403, 'Diese Prämie kannst du auf vibono.de unter „Mein Konto → Vibono-Punkte“ einlösen.' ),
			'already_unlocked'    => array( 409, 'Du hast diese Prämie schon freigeschaltet.' ),
			'limit_reached'       => array( 409, 'Du hast diese Prämie schon so oft eingelöst, wie es geht.' ),
			'insufficient_points' => array( 409, sprintf( 'Dafür brauchst du %s Punkte.', number_format_i18n( $reward['cost_points'] ) ) ),
		);
		list( $status, $msg ) = $map[ $code ] ?? array( 400, 'Die Prämie konnte nicht eingelöst werden.' );
		return Plugin::error( 'vibono_' . $code, $msg, $status, array( 'reward_id' => $reward['id'] ) );
	}

	// ------------------------------------------------------------ Format

	/** Prämie im Format RewardItem (openapi.yaml). */
	public static function format( array $r, int $user_id, int $balance, string $channel ): array {
		$n    = $user_id ? self::times_redeemed( $user_id, $r['id'] ) : 0;
		$here = self::allowed_in( $r['kind'], $channel );
		$err  = RewardRules::check( $r, $balance, $n, $here );
		$out  = array(
			'id'               => $r['id'],
			'kind'             => $r['kind'],
			'title'            => $r['title'],
			'description'      => $r['description'],
			'cost_points'      => $r['cost_points'],
			'image_url'        => null,
			'redeemed_count'   => $n,
			'unlocked'         => in_array( $r['kind'], RewardRules::ONCE, true ) && $n > 0,
			'can_redeem'       => null === $err,
			'unavailable_reason' => $err,
			'content'          => null,
			'file'             => null,
			'discount'         => null,
		);
		if ( 'content' === $r['kind'] ) {
			$p = get_post( $r['post_id'] );
			if ( $p ) {
				$out['content']   = array(
					'post_id' => $p->ID,
					'type'    => Content::kind_of( $p ),
					'title'   => html_entity_decode( wp_strip_all_tags( get_the_title( $p ) ), ENT_QUOTES, 'UTF-8' ),
				);
				$out['image_url'] = get_the_post_thumbnail_url( $p, 'medium_large' ) ?: null;
			}
		} elseif ( 'download' === $r['kind'] ) {
			$path        = get_attached_file( $r['attachment_id'] );
			$out['file'] = array(
				'name'       => $path ? basename( $path ) : '',
				'size_bytes' => $path && is_readable( $path ) ? (int) filesize( $path ) : null,
				'mime'       => (string) get_post_mime_type( $r['attachment_id'] ),
			);
			$thumb       = wp_get_attachment_image_url( $r['attachment_id'], 'medium' );
			$out['image_url'] = $thumb ?: null;
		} else {
			$out['discount'] = array(
				'type'       => $r['discount_type'],
				'amount'     => $r['discount_amount'],
				'label'      => RewardRules::discount_label( $r['discount_type'], $r['discount_amount'] ),
				'valid_days' => $r['valid_days'],
			);
		}
		return $out;
	}

	/** Einlösung im Format RewardUnlock. */
	public static function format_unlock( array $row, string $channel ): array {
		$reward = self::get( (int) $row['reward_id'] ) ?? array( 'title' => '', 'post_id' => 0 );
		$out    = array(
			'id'          => (int) $row['id'],
			'reward_id'   => (int) $row['reward_id'],
			'kind'        => $row['kind'],
			'title'       => $reward['title'],
			'points'      => (int) $row['points'],
			'created_at'  => Plugin::iso( $row['created_at'] ),
			'post_id'     => 'content' === $row['kind'] ? (int) ( $reward['post_id'] ?? 0 ) : null,
			'coupon'      => null,
		);
		if ( 'renewal_discount' === $row['kind'] ) {
			$out['coupon'] = array(
				'code'       => strtoupper( (string) $row['coupon_code'] ), // WooCommerce speichert Codes klein, Eingabe ist egal.
				'expires_at' => $row['expires_at'] ? Plugin::iso( $row['expires_at'] ) : null,
				'used'       => WooCommerce::coupon_used( (int) $row['coupon_id'] ),
				'label'      => isset( $reward['discount_type'] ) ? RewardRules::discount_label( $reward['discount_type'], (float) $reward['discount_amount'] ) : '',
			);
		}
		return $out;
	}

	/** Katalog für App oder Website. */
	public static function catalog( int $user_id, string $channel ): array {
		$balance = Points::balance( $user_id );
		$items   = array();
		foreach ( self::all() as $r ) {
			if ( ! $r['enabled'] || ( 'web' !== $channel && ! self::allowed_in( $r['kind'], $channel ) ) ) {
				continue;
			}
			$items[] = self::format( $r, $user_id, $balance, $channel );
		}
		$unlocked = array();
		foreach ( self::unlock_rows( $user_id ) as $row ) {
			if ( 'web' === $channel || self::allowed_in( $row['kind'], $channel ) ) {
				$unlocked[] = self::format_unlock( $row, $channel );
			}
		}
		return array( 'balance' => $balance, 'items' => $items, 'unlocked' => $unlocked );
	}

	// ------------------------------------------------------------ Downloads

	/** Kurzlebiger Download-Link für eine freigeschaltete Datei. */
	public static function download_link( int $user_id, int $reward_id ) {
		$r = self::get( $reward_id );
		if ( ! $r || 'download' !== $r['kind'] ) {
			return Plugin::error( 'vibono_reward_not_found', 'Diese Datei gibt es nicht.', 404 );
		}
		if ( ! self::times_redeemed( $user_id, $reward_id ) ) {
			return Plugin::error( 'vibono_reward_locked', 'Bitte schalte die Datei zuerst mit deinen Punkten frei.', 403 );
		}
		$exp   = time() + 60 * max( 1, (int) Settings::get( 'reward_download_minutes' ) );
		$token = RewardRules::download_token( $user_id, $reward_id, $exp, Settings::jwt_secret() );
		return array(
			'url'        => add_query_arg( 't', rawurlencode( $token ), rest_url( VIBONO_API_NS . '/rewards/file' ) ),
			'expires_at' => Plugin::iso( $exp ),
		);
	}

	/** Datei ausliefern (öffentlicher Endpunkt, abgesichert über das signierte Token). */
	public static function serve_file( string $token ) {
		$t = RewardRules::verify_download_token( $token, Settings::jwt_secret(), time() );
		if ( ! $t ) {
			return Plugin::error( 'vibono_link_expired', 'Der Download-Link ist abgelaufen. Bitte öffne ihn noch einmal über deine Prämien.', 403 );
		}
		$r = self::get( $t['reward_id'] );
		if ( ! $r || 'download' !== $r['kind'] || ! self::times_redeemed( $t['user_id'], $t['reward_id'] ) ) {
			return Plugin::error( 'vibono_reward_locked', 'Diese Datei ist nicht freigeschaltet.', 403 );
		}
		$path = get_attached_file( $r['attachment_id'] );
		if ( ! $path || ! is_readable( $path ) ) {
			return Plugin::error( 'vibono_not_found', 'Die Datei wurde nicht gefunden.', 404 );
		}
		$mime = (string) get_post_mime_type( $r['attachment_id'] ) ?: 'application/octet-stream';
		nocache_headers();
		header( 'Content-Type: ' . $mime );
		header( 'Content-Length: ' . filesize( $path ) );
		header( 'Content-Disposition: attachment; filename="' . str_replace( '"', '', basename( $path ) ) . '"' );
		header( 'X-Content-Type-Options: nosniff' );
		readfile( $path ); // phpcs:ignore
		exit;
	}

	// ------------------------------------------------------------ Website

	/** Exklusiver Beitrag auf der Website: Anrisstext und Freischalt-Box statt Inhalt. */
	public static function filter_content( $content ) {
		$post = get_post();
		$rest = defined( 'REST_REQUEST' ) && REST_REQUEST; // z. B. /wp-json/wp/v2/posts liefert content.rendered.
		if ( ! $post || ! ( ( in_the_loop() && is_singular() ) || $rest || is_feed() ) ) {
			return $content;
		}
		$r = self::for_post( $post->ID );
		if ( ! $r || self::can_view_post( get_current_user_id(), $post->ID ) ) {
			return $content;
		}
		$teaser = wp_trim_words( wp_strip_all_tags( $post->post_excerpt ?: strip_shortcodes( $post->post_content ) ), 40 );
		return '<p>' . esc_html( $teaser ) . '</p>' . self::unlock_box( $r, $post->ID );
	}

	public static function filter_excerpt( $excerpt, $post = null ) {
		$post = get_post( $post );
		if ( $post && self::for_post( $post->ID ) && ! self::can_view_post( get_current_user_id(), $post->ID ) ) {
			return wp_trim_words( wp_strip_all_tags( $post->post_excerpt ?: strip_shortcodes( $post->post_content ) ), 40 );
		}
		return $excerpt;
	}

	private static function unlock_box( array $r, int $post_id ): string {
		$html = '<div class="vibono-exclusive" style="border:1px solid #c8e6c9;border-radius:12px;padding:16px;margin:16px 0;background:#f3faf3">';
		$html .= '<p><strong>Exklusiv für Vibono-Punkte</strong><br>' . esc_html( sprintf( 'Schalte diesen Beitrag mit %s Punkten dauerhaft frei.', number_format_i18n( $r['cost_points'] ) ) ) . '</p>';
		if ( ! is_user_logged_in() ) {
			$html .= '<p><a class="button" href="' . esc_url( wp_login_url( get_permalink( $post_id ) ) ) . '">Anmelden</a></p>';
			return $html . '</div>';
		}
		$balance = Points::balance( get_current_user_id() );
		if ( $balance < $r['cost_points'] ) {
			$html .= '<p>' . esc_html( sprintf( 'Du hast %s Punkte. Es fehlen noch %s.', number_format_i18n( $balance ), number_format_i18n( $r['cost_points'] - $balance ) ) ) . '</p>';
			return $html . '</div>';
		}
		$html .= '<form method="post">' . wp_nonce_field( self::NONCE, 'vibono_reward_nonce', true, false );
		$html .= '<input type="hidden" name="vibono_reward_id" value="' . (int) $r['id'] . '">';
		$html .= '<button type="submit" class="button">' . esc_html( sprintf( 'Für %s Punkte freischalten', number_format_i18n( $r['cost_points'] ) ) ) . '</button>';
		$html .= ' <small>' . esc_html( sprintf( 'Du hast %s Punkte.', number_format_i18n( $balance ) ) ) . '</small></form>';
		return $html . '</div>';
	}

	/** Freischalten direkt am exklusiven Beitrag. */
	public static function handle_content_form(): void {
		if ( empty( $_POST['vibono_reward_id'] ) || ! is_user_logged_in() || ! is_singular() ) {
			return;
		}
		if ( ! isset( $_POST['vibono_reward_nonce'] ) || ! wp_verify_nonce( sanitize_key( $_POST['vibono_reward_nonce'] ), self::NONCE ) ) {
			return;
		}
		$res = self::redeem( get_current_user_id(), absint( $_POST['vibono_reward_id'] ), 'web' );
		if ( is_wp_error( $res ) && function_exists( 'wc_add_notice' ) ) {
			wc_add_notice( $res->get_error_message(), 'error' );
		}
		wp_safe_redirect( get_permalink() );
		exit;
	}

	/** Einlösen unter Mein Konto → Vibono-Punkte. */
	public static function handle_account_form(): void {
		if ( empty( $_POST['vibono_account_reward_id'] ) || ! is_user_logged_in() ) {
			return;
		}
		if ( ! isset( $_POST['vibono_reward_nonce'] ) || ! wp_verify_nonce( sanitize_key( $_POST['vibono_reward_nonce'] ), self::NONCE ) ) {
			return;
		}
		$res = self::redeem( get_current_user_id(), absint( $_POST['vibono_account_reward_id'] ), 'web' );
		if ( function_exists( 'wc_add_notice' ) ) {
			if ( is_wp_error( $res ) ) {
				wc_add_notice( $res->get_error_message(), 'error' );
			} else {
				wc_add_notice( 'Prämie eingelöst: ' . $res['unlock']['title'], 'success' );
			}
		}
		if ( function_exists( 'wc_get_account_endpoint_url' ) ) {
			wp_safe_redirect( wc_get_account_endpoint_url( WooCommerce::ENDPOINT ) );
			exit;
		}
	}

	/** Abschnitt "Prämien" in Mein Konto → Vibono-Punkte. */
	public static function render_account_section( int $user_id ): void {
		$cat = self::catalog( $user_id, 'web' );
		echo '<h3>Meine Prämien</h3>';
		if ( ! $cat['unlocked'] ) {
			echo '<p>Du hast noch keine Prämie eingelöst.</p>';
		} else {
			echo '<ul class="vibono-unlocked">';
			foreach ( $cat['unlocked'] as $u ) {
				echo '<li>' . esc_html( $u['title'] );
				if ( 'content' === $u['kind'] && $u['post_id'] ) {
					printf( ' – <a href="%s">Lesen</a>', esc_url( get_permalink( $u['post_id'] ) ) );
				} elseif ( 'download' === $u['kind'] ) {
					$link = self::download_link( $user_id, $u['reward_id'] );
					if ( ! is_wp_error( $link ) ) {
						printf( ' – <a href="%s">Herunterladen</a>', esc_url( $link['url'] ) );
					}
				} elseif ( $u['coupon'] ) {
					printf(
						' – Gutschein <code>%s</code> (%s%s)',
						esc_html( $u['coupon']['code'] ),
						esc_html( $u['coupon']['label'] ),
						esc_html( $u['coupon']['used'] ? ', eingelöst' : ( $u['coupon']['expires_at'] ? ', gültig bis ' . wp_date( 'd.m.Y', strtotime( $u['coupon']['expires_at'] ) ) : '' ) )
					);
				}
				echo '</li>';
			}
			echo '</ul>';
		}
		if ( ! $cat['items'] ) {
			return;
		}
		echo '<h3>Punkte einlösen</h3><table class="shop_table"><tbody>';
		$kinds = array( 'content' => 'Exklusiver Inhalt', 'download' => 'eBook/PDF', 'renewal_discount' => 'Rabatt auf Verlängerung' );
		foreach ( $cat['items'] as $it ) {
			echo '<tr><td><strong>' . esc_html( $it['title'] ) . '</strong><br><small>' . esc_html( $kinds[ $it['kind'] ] . ( $it['discount'] ? ' · ' . $it['discount']['label'] : '' ) ) . '</small>';
			if ( $it['description'] ) {
				echo '<br>' . esc_html( $it['description'] );
			}
			echo '</td><td style="white-space:nowrap">' . esc_html( number_format_i18n( $it['cost_points'] ) ) . ' Punkte</td><td>';
			if ( $it['unlocked'] ) {
				echo 'freigeschaltet';
			} elseif ( $it['can_redeem'] ) {
				echo '<form method="post">';
				wp_nonce_field( self::NONCE, 'vibono_reward_nonce' );
				printf( '<input type="hidden" name="vibono_account_reward_id" value="%d"><button type="submit" class="button">Einlösen</button></form>', (int) $it['id'] );
			} elseif ( 'limit_reached' === $it['unavailable_reason'] ) {
				echo 'eingelöst';
			} elseif ( 'insufficient_points' === $it['unavailable_reason'] ) {
				echo esc_html( sprintf( 'noch %s Punkte', number_format_i18n( $it['cost_points'] - $cat['balance'] ) ) );
			}
			echo '</td></tr>';
		}
		echo '</tbody></table>';
	}
}
