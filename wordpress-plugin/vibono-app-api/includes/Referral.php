<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Kundenwerbung ("Freunde werben") im zentralen Punktesystem. Ersetzt WPGens Refer-a-friend.
 *
 * Ablauf
 * 1. Jede*r Nutzer*in hat einen festen Code (z. B. ANNA7K). Link: https://www.vibono.de/?vref=ANNA7K
 *    Alte Refer-a-friend-Links (?raf=…) funktionieren weiter, alte Codes werden übernommen.
 * 2. Der Link setzt ein Cookie (30 Tage). Registriert sich die Person (Website oder App mit Code),
 *    wird die werbende Person am neuen Konto gespeichert.
 * 3. Bezahlt die geworbene Person ihre erste Bestellung (Mindestwert), bekommt die werbende Person
 *    Punkte, die geworbene einen Willkommensbonus. Beide zunächst "pending" bis zum Ende der
 *    Widerrufsfrist; bei Storno/Erstattung verfallen sie.
 * 4. Schutz: keine Selbstwerbung (gleiches Konto, gleiche E-Mail, gleiche Lieferadresse),
 *    nur eine Belohnung je geworbener Person.
 */
class Referral {

	const CODE_META     = '_vibono_ref_code';
	const BY_META       = '_vibono_referred_by';
	const COOKIE        = 'vibono_ref';
	const ORDER_META    = '_vibono_referrer';

	public static function init(): void {
		Plugin::hook( 'init', array( self::class, 'capture_param' ), 5 );
		Plugin::hook( 'user_register', array( self::class, 'on_register' ), 20 );
	}

	// -------------------------------------------------------------- Codes

	public static function code_for( int $user_id ): string {
		$code = (string) get_user_meta( $user_id, self::CODE_META, true );
		if ( $code ) {
			return $code;
		}
		$user = get_userdata( $user_id );
		$base = $user ? strtoupper( preg_replace( '/[^A-Za-z]/', '', remove_accents( $user->first_name ?: $user->display_name ) ) ) : '';
		$base = substr( $base ?: 'VIBONO', 0, 4 );
		$abc  = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
		do {
			$suffix = '';
			for ( $i = 0; $i < 2; $i++ ) {
				$suffix .= $abc[ random_int( 0, strlen( $abc ) - 1 ) ];
			}
			$code = $base . $suffix;
		} while ( self::user_by_code( $code ) );
		update_user_meta( $user_id, self::CODE_META, $code );
		return $code;
	}

	/** Findet den Nutzer zu einem Code (neue Codes und übernommene Refer-a-friend-Codes). */
	public static function user_by_code( string $code ): int {
		$code = trim( $code );
		if ( '' === $code || strlen( $code ) > 64 ) {
			return 0;
		}
		foreach ( array( self::CODE_META, (string) Settings::get( 'referral_legacy_meta_key' ) ) as $key ) {
			if ( ! $key ) {
				continue;
			}
			$users = get_users(
				array(
					'meta_key'   => $key, // phpcs:ignore
					'meta_value' => self::CODE_META === $key ? strtoupper( $code ) : $code, // phpcs:ignore
					'number'     => 1,
					'fields'     => 'ID',
				)
			);
			if ( $users ) {
				return (int) $users[0];
			}
		}
		return 0;
	}

	public static function link_for( int $user_id ): string {
		return add_query_arg( Settings::get( 'referral_param' ), self::code_for( $user_id ), home_url( '/' ) );
	}

	// --------------------------------------------------- Link und Cookie

	/**
	 * Läuft WPGens Refer a Friend noch? Für die Warnung in der Systemprüfung: Ist "Freunde werben" an,
	 * übernimmt das Punktesystem auch alte ?raf-Links. Refer a Friend darf dann keine Belohnungen mehr
	 * vergeben, sonst gäbe es doppelte Prämien. ANNAHME: Plugin-Ordner enthält "gens-raf" oder "refer-a-friend".
	 */
	public static function legacy_plugin_active(): bool {
		$active = (array) get_option( 'active_plugins', array() );
		if ( is_multisite() ) {
			$active = array_merge( $active, array_keys( (array) get_site_option( 'active_sitewide_plugins', array() ) ) );
		}
		foreach ( $active as $plugin ) {
			if ( preg_match( '/gens-raf|refer-a-friend|wpgens/i', (string) $plugin ) ) {
				return true;
			}
		}
		return false;
	}

	public static function capture_param(): void {
		$params = array_merge( array( (string) Settings::get( 'referral_param' ) ), (array) Settings::get( 'referral_legacy_params' ) );
		foreach ( $params as $p ) {
			if ( empty( $_GET[ $p ] ) ) { // phpcs:ignore
				continue;
			}
			$code = sanitize_text_field( wp_unslash( $_GET[ $p ] ) ); // phpcs:ignore
			$uid  = self::user_by_code( $code );
			if ( $uid && $uid !== get_current_user_id() && ! headers_sent() ) {
				setcookie( self::COOKIE, (string) $uid, time() + DAY_IN_SECONDS * (int) Settings::get( 'referral_cookie_days' ), COOKIEPATH ?: '/', COOKIE_DOMAIN, is_ssl(), true );
				$_COOKIE[ self::COOKIE ] = (string) $uid;
			}
			return;
		}
	}

	private static function referrer_from_cookie(): int {
		return isset( $_COOKIE[ self::COOKIE ] ) ? absint( $_COOKIE[ self::COOKIE ] ) : 0;
	}

	/** Neues Konto: werbende Person aus Cookie übernehmen (Website). */
	public static function on_register( int $user_id ): void {
		$ref = self::referrer_from_cookie();
		if ( $ref ) {
			self::attach( $user_id, $ref );
		}
	}

	/** Werbende Person am Konto speichern (einmalig, keine Selbstwerbung). */
	public static function attach( int $user_id, int $referrer_id ): bool {
		if ( ! $referrer_id || $referrer_id === $user_id || get_user_meta( $user_id, self::BY_META, true ) || ! get_userdata( $referrer_id ) ) {
			return false;
		}
		update_user_meta( $user_id, self::BY_META, $referrer_id );
		update_user_meta( $user_id, '_vibono_referred_at', gmdate( 'c' ) );
		do_action( 'vibono_referral_attached', $user_id, $referrer_id );
		return true;
	}

	// ------------------------------------------------------ Bestellungen

	/**
	 * Werbende Person einer Bestellung bestimmen und an der Bestellung merken.
	 * Gilt nur für die erste Bestellung eines Kunden.
	 */
	public static function referrer_for_order( \WC_Order $order ): int {
		$stored = (int) $order->get_meta( self::ORDER_META );
		if ( $stored ) {
			return $stored;
		}
		$customer = (int) $order->get_customer_id();
		$ref      = $customer ? (int) get_user_meta( $customer, self::BY_META, true ) : 0;
		if ( ! $ref ) {
			$ref = self::referrer_from_cookie();
		}
		if ( ! $ref || $ref === $customer || self::is_self_referral( $order, $ref ) || self::is_existing_customer( $order ) ) {
			return 0;
		}
		$order->update_meta_data( self::ORDER_META, $ref );
		if ( $customer ) {
			self::attach( $customer, $ref );
		}
		return $ref;
	}

	/** Bestandskunden (frühere bezahlte Bestellung) zählen nicht als Neukunden. */
	private static function is_existing_customer( \WC_Order $order ): bool {
		$args = array(
			'status'  => array( 'wc-processing', 'wc-completed' ),
			'exclude' => array( $order->get_id() ),
			'limit'   => 1,
			'return'  => 'ids',
		);
		if ( $order->get_customer_id() ) {
			$args['customer_id'] = $order->get_customer_id();
		} else {
			$args['billing_email'] = $order->get_billing_email();
		}
		return (bool) wc_get_orders( $args );
	}

	private static function is_self_referral( \WC_Order $order, int $ref ): bool {
		$referrer = get_userdata( $ref );
		if ( ! $referrer ) {
			return true;
		}
		if ( strtolower( $referrer->user_email ) === strtolower( (string) $order->get_billing_email() ) ) {
			return true;
		}
		$addr = static fn( $a, $p ) => strtolower( preg_replace( '/\s+/', '', (string) $a ) ) . '|' . preg_replace( '/\s+/', '', (string) $p );
		$ref_addr = $addr( get_user_meta( $ref, 'shipping_address_1', true ) ?: get_user_meta( $ref, 'billing_address_1', true ), get_user_meta( $ref, 'shipping_postcode', true ) ?: get_user_meta( $ref, 'billing_postcode', true ) );
		$ord_addr = $addr( $order->get_shipping_address_1() ?: $order->get_billing_address_1(), $order->get_shipping_postcode() ?: $order->get_billing_postcode() );
		return '|' !== $ref_addr && $ref_addr === $ord_addr;
	}

	/** Schlüssel der geworbenen Person: Konto, sonst E-Mail (Gastbestellung). */
	private static function friend_key( \WC_Order $order ): string {
		return $order->get_customer_id() ? 'u' . $order->get_customer_id() : 'e' . md5( strtolower( (string) $order->get_billing_email() ) );
	}

	/** Bezahlte Bestellung: Empfehlungspunkte vormerken. */
	public static function on_order_paid( \WC_Order $order ): void {
		$ref = self::referrer_for_order( $order );
		if ( ! $ref ) {
			return;
		}
		$goods = (int) round( ( (float) $order->get_total() - (float) $order->get_shipping_total() - (float) $order->get_shipping_tax() ) * 100 );
		if ( $goods < (int) Settings::get( 'referral_min_order_cents' ) ) {
			return;
		}
		$friend = self::friend_key( $order );
		$days   = (int) Settings::get( 'pending_days' );
		$name   = trim( $order->get_billing_first_name() ) ?: 'Ein*e Freund*in';
		Points::earn(
			$ref,
			'referral',
			(int) Settings::get( 'earn_referral' ),
			array(
				'idempotency_key' => 'referral:' . $friend,
				'label'           => $name . ' hat über deine Empfehlung bestellt',
				'ref_type'        => 'order',
				'ref_id'          => $order->get_id(),
				'pending_days'    => $days,
			)
		);
		if ( $order->get_customer_id() ) {
			Points::earn(
				(int) $order->get_customer_id(),
				'referral_friend',
				(int) Settings::get( 'earn_referral_friend' ),
				array(
					'idempotency_key' => 'referral_friend:' . $friend,
					'label'           => 'Willkommensbonus für deine erste Bestellung',
					'ref_type'        => 'order',
					'ref_id'          => $order->get_id(),
					'pending_days'    => $days,
				)
			);
		}
		$order->save_meta_data();
	}

	// ------------------------------------------------------------ Zähler

	public static function stats( int $user_id ): array {
		global $wpdb;
		$t       = Install::table( 'points_ledger' );
		$invited = count(
			get_users(
				array(
					'meta_key'   => self::BY_META, // phpcs:ignore
					'meta_value' => $user_id, // phpcs:ignore
					'fields'     => 'ID',
				)
			)
		);
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT COUNT(*) AS n, COALESCE(SUM(points),0) AS p FROM $t WHERE user_id = %d AND reason = 'referral' AND status <> 'void'", $user_id ) );
		return array(
			'invited'       => $invited,
			'converted'     => (int) $row->n,
			'points_earned' => (int) $row->p,
		);
	}

	public static function info( int $user_id ): array {
		$summary = Points::summary( $user_id );
		$code    = self::code_for( $user_id );
		$link    = self::link_for( $user_id );
		return array_merge(
			array(
				'code'                 => $code,
				'link'                 => $link,
				'share_text'           => sprintf( 'Ich nehme mit Vibono ab, mit Genuss statt Verzicht. Mit meinem Link bekommst du %d Bonuspunkte für deine erste Bestellung: %s', $summary['earn_rules']['referral_friend'], $link ),
				'points_per_referral'  => $summary['earn_rules']['referral'],
				'friend_bonus_points'  => $summary['earn_rules']['referral_friend'],
			),
			self::stats( $user_id )
		);
	}
}
