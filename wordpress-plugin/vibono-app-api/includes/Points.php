<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\PointsMath;

defined( 'ABSPATH' ) || exit;

/**
 * Zentrales Punktesystem: ein Hauptbuch (Ledger) für App und Shop.
 *
 * Grundsätze
 * - Jede Buchung ist eine Zeile, nichts wird überschrieben. Kontostand = Summe bestätigter Zeilen.
 * - Idempotenz-Schlüssel verhindern Doppelbuchungen (z. B. "app_open:42:2026-11-14").
 * - Kauf- und Empfehlungspunkte sind zuerst "pending" und werden nach der Widerrufsfrist bestätigt
 *   (Cron), bei Storno/Erstattung "void".
 * - Aktionen (Campaigns) werden beim Verdienen bzw. Einlösen angewendet und an der Buchung vermerkt.
 */
class Points {

	public static function init(): void {
		Plugin::hook( 'vibono_points_daily', array( self::class, 'confirm_due' ) );
	}

	// ------------------------------------------------------------------ Lesen

	public static function balance( int $user_id ): int {
		global $wpdb;
		$t = Install::table( 'points_ledger' );
		return (int) $wpdb->get_var( $wpdb->prepare( "SELECT COALESCE(SUM(points),0) FROM $t WHERE user_id = %d AND status = 'confirmed'", $user_id ) );
	}

	public static function pending( int $user_id ): int {
		global $wpdb;
		$t = Install::table( 'points_ledger' );
		return (int) $wpdb->get_var( $wpdb->prepare( "SELECT COALESCE(SUM(points),0) FROM $t WHERE user_id = %d AND status = 'pending' AND points > 0", $user_id ) );
	}

	public static function ledger( int $user_id, int $page, int $per_page ): array {
		global $wpdb;
		$t     = Install::table( 'points_ledger' );
		$total = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM $t WHERE user_id = %d", $user_id ) );
		$rows  = $wpdb->get_results( $wpdb->prepare( "SELECT * FROM $t WHERE user_id = %d ORDER BY id DESC LIMIT %d OFFSET %d", $user_id, $per_page, ( $page - 1 ) * $per_page ), ARRAY_A );
		return array( 'items' => array_map( array( self::class, 'format_entry' ), $rows ), 'total' => $total );
	}

	public static function format_entry( array $r ): array {
		return array(
			'id'          => (int) $r['id'],
			'points'      => (int) $r['points'],
			'reason'      => $r['reason'],
			'status'      => $r['status'],
			'label'       => $r['label'],
			'multiplier'  => (float) $r['multiplier'],
			'campaign_id' => $r['campaign_id'] ? (int) $r['campaign_id'] : null,
			'created_at'  => Plugin::iso( $r['created_at'] ),
			'confirms_at' => $r['confirms_at'] ? Plugin::iso( $r['confirms_at'] ) : null,
		);
	}

	public static function has_key( string $idempotency_key ): bool {
		global $wpdb;
		$t = Install::table( 'points_ledger' );
		return (bool) $wpdb->get_var( $wpdb->prepare( "SELECT id FROM $t WHERE idempotency_key = %s", $idempotency_key ) );
	}

	/** Anzahl Buchungen eines Grundes seit Tagesbeginn (Website-Zeitzone). */
	public static function count_today( int $user_id, string $reason ): int {
		global $wpdb;
		$t     = Install::table( 'points_ledger' );
		$start = ( new \DateTimeImmutable( 'today', wp_timezone() ) )->setTimezone( new \DateTimeZone( 'UTC' ) )->format( 'Y-m-d H:i:s' );
		return (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM $t WHERE user_id = %d AND reason = %s AND created_at >= %s AND status <> 'void'", $user_id, $reason, $start ) );
	}

	// -------------------------------------------------------------- Buchen

	/**
	 * Punkte für eine Aktion gutschreiben (mit Aktions-Multiplikator).
	 *
	 * @param string $reason app_open|article_read|referral|referral_friend|purchase
	 * @param array  $args   idempotency_key, label, ref_type, ref_id, pending_days, meta
	 */
	public static function earn( int $user_id, string $reason, int $base, array $args = array() ): array {
		$none = array( 'awarded_points' => 0, 'already_awarded' => false, 'multiplier' => 1.0, 'campaign' => null, 'entry_id' => null );
		if ( ! Settings::get( 'points_enabled' ) || $base <= 0 ) {
			return $none;
		}
		$key = $args['idempotency_key'] ?? null;
		if ( $key && self::has_key( $key ) ) {
			return array_merge( $none, array( 'already_awarded' => true ) );
		}
		$calc    = PointsMath::earn( $base, Campaigns::all_for_math(), time(), $reason );
		$pending = (int) ( $args['pending_days'] ?? 0 );
		$id      = self::insert(
			array(
				'user_id'         => $user_id,
				'points'          => $calc['points'],
				'reason'          => $reason,
				'status'          => $pending > 0 ? 'pending' : 'confirmed',
				'ref_type'        => $args['ref_type'] ?? '',
				'ref_id'          => (int) ( $args['ref_id'] ?? 0 ),
				'idempotency_key' => $key,
				'base_points'     => $base,
				'multiplier'      => $calc['multiplier'],
				'campaign_id'     => $calc['campaign']['id'] ?? null,
				'label'           => $args['label'] ?? '',
				'meta'            => $args['meta'] ?? null,
				'confirms_at'     => $pending > 0 ? gmdate( 'Y-m-d H:i:s', time() + $pending * DAY_IN_SECONDS ) : null,
			)
		);
		if ( ! $id ) {
			// Unique-Konflikt durch parallele Anfrage.
			return array_merge( $none, array( 'already_awarded' => true ) );
		}
		do_action( 'vibono_points_earned', $user_id, $reason, $calc['points'], $id );
		return array(
			'awarded_points'  => $calc['points'],
			'already_awarded' => false,
			'multiplier'      => $calc['multiplier'],
			'campaign'        => $calc['campaign'] ? Campaigns::format( $calc['campaign'] ) : null,
			'entry_id'        => $id,
		);
	}

	/** Freie Buchung (Admin-Korrektur, Einlösung, Migration). */
	public static function book( int $user_id, int $points, string $reason, string $label, array $extra = array() ): ?int {
		return self::insert(
			array_merge(
				array(
					'user_id'     => $user_id,
					'points'      => $points,
					'reason'      => $reason,
					'status'      => 'confirmed',
					'label'       => $label,
					'base_points' => $points,
					'created_by'  => get_current_user_id(),
				),
				$extra
			)
		);
	}

	private static function insert( array $row ): ?int {
		global $wpdb;
		$row['created_at'] = gmdate( 'Y-m-d H:i:s' );
		if ( isset( $row['meta'] ) && is_array( $row['meta'] ) ) {
			$row['meta'] = wp_json_encode( $row['meta'] );
		}
		$row = array_filter( $row, static fn( $v ) => null !== $v );
		$ok  = $wpdb->insert( Install::table( 'points_ledger' ), $row );
		return $ok ? (int) $wpdb->insert_id : null;
	}

	/** Buchungen zu einer Referenz stornieren (z. B. Bestellung erstattet). */
	public static function void_ref( string $ref_type, int $ref_id, array $reasons ): int {
		global $wpdb;
		$t  = Install::table( 'points_ledger' );
		$in = implode( ',', array_fill( 0, count( $reasons ), '%s' ) );
		return (int) $wpdb->query( $wpdb->prepare( "UPDATE $t SET status = 'void' WHERE ref_type = %s AND ref_id = %d AND status IN ('pending','confirmed') AND reason IN ($in)", array_merge( array( $ref_type, $ref_id ), $reasons ) ) ); // phpcs:ignore
	}

	/** Bestätigt fällige Pending-Buchungen. Läuft stündlich per Cron. */
	public static function confirm_due(): int {
		global $wpdb;
		$t = Install::table( 'points_ledger' );
		return (int) $wpdb->query( $wpdb->prepare( "UPDATE $t SET status = 'confirmed' WHERE status = 'pending' AND confirms_at IS NOT NULL AND confirms_at <= %s", gmdate( 'Y-m-d H:i:s' ) ) );
	}

	/** Bestätigungszeitpunkt der Pending-Buchungen einer Referenz setzen. */
	public static function set_confirm_at( string $ref_type, int $ref_id, int $timestamp ): void {
		global $wpdb;
		$t = Install::table( 'points_ledger' );
		$wpdb->query( $wpdb->prepare( "UPDATE $t SET confirms_at = %s WHERE ref_type = %s AND ref_id = %d AND status = 'pending'", gmdate( 'Y-m-d H:i:s', $timestamp ), $ref_type, $ref_id ) );
	}

	// -------------------------------------------------------- Zusammenfassung

	public static function summary( int $user_id ): array {
		$cpp       = (float) Settings::get( 'cents_per_point' );
		$campaigns = Campaigns::all_for_math();
		$eff       = PointsMath::effective_cents_per_point( $cpp, $campaigns, time() );
		$balance   = self::balance( $user_id );
		$rules     = array();
		foreach ( array(
			'app_open'        => 'earn_app_open',
			'article_read'    => 'earn_article_read',
			'referral'        => 'earn_referral',
			'referral_friend' => 'earn_referral_friend',
			'purchase'        => 'earn_purchase_per_euro',
		) as $reason => $setting ) {
			$rules[ $reason ] = PointsMath::earn( (int) Settings::get( $setting ), $campaigns, time(), $reason )['points'];
		}
		return array(
			'balance'                   => $balance,
			'pending'                   => self::pending( $user_id ),
			'cents_per_point'           => $cpp,
			'effective_cents_per_point' => $eff,
			'value_cents'               => (int) floor( $balance * $eff ),
			'earn_rules'                => $rules,
			'campaigns'                 => array_map( array( Campaigns::class, 'format' ), Campaigns::visible() ),
		);
	}

	/** Tägliche App-Öffnung. */
	public static function app_open( int $user_id ): array {
		$r = self::earn(
			$user_id,
			'app_open',
			(int) Settings::get( 'earn_app_open' ),
			array(
				'idempotency_key' => 'app_open:' . $user_id . ':' . Plugin::today(),
				'label'           => 'App heute geöffnet',
			)
		);
		$r['balance'] = self::balance( $user_id );
		unset( $r['entry_id'] );
		return $r;
	}

	public static function app_open_awarded_today( int $user_id ): bool {
		return self::has_key( 'app_open:' . $user_id . ':' . Plugin::today() );
	}
}
