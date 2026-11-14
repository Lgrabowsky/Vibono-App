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
}
