<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * WP-CLI-Befehle.
 *
 *   wp vibono migrate-raf --dry-run
 *   wp vibono migrate-raf --coupon-meta=<meta_key>
 *   wp vibono confirm-pending
 *   wp vibono balance kundin@example.com
 *   wp vibono check
 *   wp vibono export-points > punkte.csv
 *   wp vibono restore-myvibono --dry-run
 *   wp vibono reconcile-orders --days=60
 */
class Cli {

	/**
	 * Übernimmt WPGens Refer-a-friend ins Vibono-Punktesystem.
	 *
	 * 1. Alte Empfehlungscodes werden zu den neuen Codes (Links bleiben gültig).
	 * 2. Optional: noch nicht eingelöste Refer-a-friend-Gutscheine (fester Betrag) werden in Punkte
	 *    umgewandelt und der Gutschein beendet. Dafür das Meta-Feld angeben, an dem Refer-a-friend
	 *    seine Gutscheine erkennt (vorher in der Datenbank prüfen!).
	 *
	 * ## OPTIONS
	 *
	 * [--dry-run]
	 * : Nur anzeigen, nichts ändern.
	 *
	 * [--meta-key=<key>]
	 * : Nutzer-Meta mit dem alten Code. Standard aus den Einstellungen (gens_referral_id).
	 *
	 * [--coupon-meta=<key>]
	 * : Meta-Feld, das Refer-a-friend-Gutscheine kennzeichnet. Ohne Angabe werden keine Gutscheine umgewandelt.
	 *
	 * @subcommand migrate-raf
	 */
	public function migrate_raf( $args, $assoc ): void {
		global $wpdb;
		$dry      = isset( $assoc['dry-run'] );
		$meta_key = $assoc['meta-key'] ?? (string) Settings::get( 'referral_legacy_meta_key' );
		$rows     = $wpdb->get_results( $wpdb->prepare( "SELECT user_id, meta_value FROM {$wpdb->usermeta} WHERE meta_key = %s AND meta_value <> ''", $meta_key ) );
		$codes    = 0;
		$skipped  = 0;
		foreach ( $rows as $r ) {
			$code = strtoupper( trim( (string) $r->meta_value ) );
			if ( get_user_meta( (int) $r->user_id, Referral::CODE_META, true ) ) {
				++$skipped;
				continue;
			}
			$owner = Referral::user_by_code( $code );
			if ( $owner && $owner !== (int) $r->user_id ) {
				\WP_CLI::warning( "Code $code doppelt (Nutzer {$r->user_id} und $owner), übersprungen." );
				++$skipped;
				continue;
			}
			if ( ! $dry ) {
				update_user_meta( (int) $r->user_id, Referral::CODE_META, $code );
			}
			++$codes;
		}
		\WP_CLI::log( sprintf( 'Empfehlungscodes: %d übernommen, %d übersprungen%s.', $codes, $skipped, $dry ? ' (Probelauf)' : '' ) );

		if ( empty( $assoc['coupon-meta'] ) ) {
			\WP_CLI::log( 'Gutscheine: nicht umgewandelt (--coupon-meta fehlt).' );
			return;
		}
		$cpp     = (float) Settings::get( 'cents_per_point' );
		$ids     = get_posts( array( 'post_type' => 'shop_coupon', 'post_status' => 'publish', 'posts_per_page' => -1, 'fields' => 'ids', 'meta_key' => sanitize_key( $assoc['coupon-meta'] ) ) ); // phpcs:ignore
		$done    = 0;
		$points  = 0;
		$ignored = 0;
		foreach ( $ids as $id ) {
			$c       = new \WC_Coupon( $id );
			$emails  = (array) $c->get_email_restrictions();
			$user    = $emails ? get_user_by( 'email', $emails[0] ) : null;
			$expired = $c->get_date_expires() && $c->get_date_expires()->getTimestamp() < time();
			$used    = $c->get_usage_limit() && $c->get_usage_count() >= $c->get_usage_limit();
			if ( ! $user || $expired || $used || 'fixed_cart' !== $c->get_discount_type() ) {
				++$ignored;
				continue;
			}
			$pts = (int) round( (float) $c->get_amount() * 100 / $cpp );
			\WP_CLI::log( sprintf( '%s: Gutschein %s (%s €) → %d Punkte', $user->user_email, $c->get_code(), $c->get_amount(), $pts ) );
			if ( ! $dry && ! Points::has_key( 'migration:coupon:' . $id ) ) {
				Points::book( $user->ID, $pts, 'migration', 'Umgewandelt aus Empfehlungs-Gutschein ' . $c->get_code(), array( 'ref_type' => 'coupon', 'ref_id' => $id, 'idempotency_key' => 'migration:coupon:' . $id ) );
				// Altes Ablaufdatum merken, damit die Umwandlung nachvollziehbar und umkehrbar bleibt.
				$c->update_meta_data( '_vibono_migrated', array( 'at' => gmdate( 'c' ), 'points' => $pts, 'old_expiry' => $c->get_date_expires() ? $c->get_date_expires()->getTimestamp() : null ) );
				$c->set_date_expires( time() - 60 );
				$c->save();
			}
			++$done;
			$points += $pts;
		}
		\WP_CLI::success( sprintf( 'Gutscheine: %d umgewandelt (%d Punkte), %d ignoriert (abgelaufen, verbraucht, Prozent-Gutschein oder ohne Konto)%s.', $done, $points, $ignored, $dry ? ' – Probelauf, nichts geändert' : '' ) );
	}

	/**
	 * Bestätigt fällige vorgemerkte Punkte sofort (läuft sonst stündlich per Cron).
	 *
	 * @subcommand confirm-pending
	 */
	public function confirm_pending(): void {
		\WP_CLI::success( Points::confirm_due() . ' Buchungen bestätigt.' );
	}

	/**
	 * Zeigt Kontostand und letzte Buchungen.
	 *
	 * <email>
	 * : E-Mail des Kontos.
	 */
	public function balance( $args ): void {
		$user = get_user_by( 'email', $args[0] );
		if ( ! $user ) {
			\WP_CLI::error( 'Konto nicht gefunden.' );
		}
		\WP_CLI::log( 'Kontostand: ' . Points::balance( $user->ID ) . ' · vorgemerkt: ' . Points::pending( $user->ID ) );
		\WP_CLI\Utils\format_items( 'table', Points::ledger( $user->ID, 1, 20 )['items'], array( 'created_at', 'reason', 'points', 'status', 'label' ) );
	}

	/**
	 * Prüft die Anbindung an vibono.de (Konstanten, Tabellen, Cron, WooCommerce, Module). Ändert nichts.
	 */
	public function check(): void {
		$items = array();
		foreach ( array( 'module_api', 'points_enabled', 'module_shop', 'module_referral', 'module_web_reading', 'myvibono_write', 'delete_data_on_uninstall' ) as $m ) {
			$items[] = array( 'status' => Settings::on( $m ) ? 'an' : 'aus', 'label' => 'Modul ' . $m, 'detail' => '' );
		}
		foreach ( Health::checks() as $c ) {
			$items[] = $c;
		}
		\WP_CLI\Utils\format_items( 'table', $items, array( 'status', 'label', 'detail' ) );
	}

	/**
	 * Gibt alle Punktestände als CSV aus (z. B. vor dem Löschen des Plugins).
	 *
	 * ## EXAMPLES
	 *
	 *     wp vibono export-points > punkte.csv
	 *
	 * @subcommand export-points
	 */
	public function export_points(): void {
		global $wpdb;
		$t    = Install::table( 'points_ledger' );
		$rows = $wpdb->get_results(
			"SELECT user_id,
				COALESCE(SUM(CASE WHEN status = 'confirmed' THEN points ELSE 0 END),0) AS balance,
				COALESCE(SUM(CASE WHEN status = 'pending' AND points > 0 THEN points ELSE 0 END),0) AS pending
			FROM $t GROUP BY user_id ORDER BY user_id" // phpcs:ignore
		);
		$cpp = (float) Settings::get( 'cents_per_point' );
		$out = fopen( 'php://stdout', 'w' );
		fputcsv( $out, array( 'user_id', 'email', 'name', 'punkte', 'vorgemerkt', 'wert_eur' ), ';' );
		foreach ( $rows as $r ) {
			$u = get_userdata( (int) $r->user_id );
			fputcsv( $out, array( (int) $r->user_id, $u ? $u->user_email : '', $u ? $u->display_name : '', (int) $r->balance, (int) $r->pending, number_format( (int) $r->balance * $cpp / 100, 2, ',', '' ) ), ';' );
		}
		fclose( $out );
	}

	/**
	 * Stellt die MyVibono-Felder des Themes auf den Stand vor dem ersten Schreiben des Plugins zurück.
	 *
	 * Achtung: Änderungen, die Nutzer*innen seitdem auf der Website oder in der App gemacht haben,
	 * gehen in diesen Feldern verloren. Nur für den Notfall (z. B. falsch angenommenes Format).
	 * Schaltet vorher "MyVibono-Daten auf die Website schreiben" aus.
	 *
	 * ## OPTIONS
	 *
	 * [--dry-run]
	 * : Nur anzeigen, nichts ändern.
	 *
	 * [--yes]
	 * : Ohne Rückfrage ausführen.
	 *
	 * @subcommand restore-myvibono
	 */
	public function restore_myvibono( $args, $assoc ): void {
		global $wpdb;
		$dry  = isset( $assoc['dry-run'] );
		$rows = $wpdb->get_results( $wpdb->prepare( "SELECT user_id, meta_key, meta_value FROM {$wpdb->usermeta} WHERE meta_key LIKE %s", $wpdb->esc_like( MyVibonoBridge::BACKUP_PREFIX ) . '%' ) );
		if ( ! $rows ) {
			\WP_CLI::success( 'Keine Sicherungen vorhanden: Das Plugin hat nie in MyVibono-Felder geschrieben.' );
			return;
		}
		if ( ! $dry ) {
			\WP_CLI::confirm( sprintf( '%d Felder zurücksetzen? Spätere Änderungen in diesen Feldern gehen verloren.', count( $rows ) ), $assoc );
			Settings::update( array( 'myvibono_write' => false ) );
		}
		foreach ( $rows as $r ) {
			$key = substr( $r->meta_key, strlen( MyVibonoBridge::BACKUP_PREFIX ) );
			$bak = maybe_unserialize( $r->meta_value );
			\WP_CLI::log( sprintf( 'Nutzer %d: %s (gesichert %s)%s', $r->user_id, $key, $bak['at'] ?? '?', empty( $bak['existed'] ) ? ' → wird entfernt' : '' ) );
			if ( $dry ) {
				continue;
			}
			if ( empty( $bak['existed'] ) ) {
				delete_user_meta( (int) $r->user_id, $key );
			} else {
				update_user_meta( (int) $r->user_id, $key, $bak['value'] );
			}
			delete_user_meta( (int) $r->user_id, $r->meta_key );
		}
		\WP_CLI::success( $dry ? 'Probelauf, nichts geändert.' : 'Zurückgesetzt. "MyVibono-Daten auf die Website schreiben" ist jetzt aus.' );
	}

	/**
	 * Holt Punkte-Buchungen für Bestellungen nach, deren Status sich geändert hat, während das Plugin
	 * deaktiviert war (Storno: Punkte zurück; abgeschlossen: Widerrufsfrist starten). Mehrfach ausführbar.
	 *
	 * ## OPTIONS
	 *
	 * [--days=<n>]
	 * : Bestellungen, die in den letzten n Tagen geändert wurden. Standard: 60.
	 *
	 * [--dry-run]
	 * : Nur anzeigen, nichts ändern.
	 *
	 * @subcommand reconcile-orders
	 */
	public function reconcile_orders( $args, $assoc ): void {
		if ( ! function_exists( 'wc_get_orders' ) ) {
			\WP_CLI::error( 'WooCommerce ist nicht aktiv.' );
		}
		$dry  = isset( $assoc['dry-run'] );
		$days = max( 1, (int) ( $assoc['days'] ?? 60 ) );
		$ids  = wc_get_orders(
			array(
				'limit'         => -1,
				'return'        => 'ids',
				'status'        => array( 'wc-completed', 'wc-cancelled', 'wc-refunded', 'wc-failed' ),
				'date_modified' => '>' . ( time() - $days * DAY_IN_SECONDS ),
			)
		);
		$n = 0;
		foreach ( $ids as $id ) {
			$order = wc_get_order( $id );
			$did   = $order ? WooCommerce::reconcile_order( $order, $dry ) : '';
			if ( $did ) {
				\WP_CLI::log( 'Bestellung ' . $order->get_order_number() . ' – ' . $did );
				++$n;
			}
		}
		\WP_CLI::success( sprintf( '%d von %d Bestellungen nachgebucht%s.', $n, count( $ids ), $dry ? ' (Probelauf, nichts geändert)' : '' ) );
	}
}
