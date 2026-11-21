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
	 * @param string $reason app_open|article_read|lesson_done|course_done|referral|referral_friend|purchase
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
		foreach ( self::earn_settings() as $reason => $setting ) {
			$base = (int) Settings::get( $setting );
			if ( $base > 0 ) {
				$rules[ $reason ] = PointsMath::earn( $base, $campaigns, time(), $reason )['points'];
			}
		}
		return array(
			'balance'                   => $balance,
			'pending'                   => self::pending( $user_id ),
			'cents_per_point'           => $cpp,
			'effective_cents_per_point' => $eff,
			'value_cents'               => (int) floor( $balance * $eff ),
			'earn_rules'                => $rules,
			'campaigns'                 => array_map( array( Campaigns::class, 'format' ), Campaigns::visible() ),
			'streak'                    => Streak::view( $user_id ),
		);
	}

	/**
	 * Aktuelle Anlässe für Punkte (Grund => Einstellung mit dem Grundwert). Ausgeschaltete Anlässe fehlen,
	 * damit App und Website sie nicht anzeigen.
	 */
	public static function earn_settings(): array {
		$out = array(
			'app_open'     => 'earn_app_open',
			'article_read' => 'earn_article_read',
			'lesson_done'  => 'earn_lesson_done',
			'course_done'  => 'earn_course_done',
		);
		if ( Settings::on( 'module_referral' ) ) {
			$out['referral']        = 'earn_referral';
			$out['referral_friend'] = 'earn_referral_friend';
		}
		if ( WooCommerce::purchase_points_on() ) {
			$out['purchase'] = 'earn_purchase_per_euro';
		}
		return $out;
	}

	/**
	 * Führt $fn exklusiv für ein Punktekonto aus (verhindert, dass zwei gleichzeitige Einlösungen
	 * denselben Kontostand ausgeben). Sperre über einen eindeutigen Options-Eintrag, funktioniert mit
	 * MySQL und SQLite. Hängt eine Sperre länger als 30 Sekunden, gilt sie als verwaist.
	 *
	 * @return mixed Rückgabe von $fn oder WP_Error, wenn das Konto gerade gesperrt ist.
	 */
	public static function with_lock( int $user_id, callable $fn ) {
		$name = 'vibono_points_lock_' . $user_id;
		if ( ! add_option( $name, time(), '', false ) ) {
			$since = (int) get_option( $name );
			if ( $since && $since > time() - 30 ) {
				return Plugin::error( 'vibono_busy', 'Bitte einen Moment warten und noch einmal versuchen.', 429 );
			}
			update_option( $name, time(), false );
		}
		try {
			return $fn();
		} finally {
			delete_option( $name );
		}
	}

	/**
	 * Tägliche App-Öffnung. Mit eingeschalteter Serie (Streak) richten sich die Punkte nach der
	 * Stufe der Serie; eine laufende Aktion für "App geöffnet" multipliziert sie wie gewohnt.
	 */
	public static function app_open( int $user_id ): array {
		$streak = Streak::enabled() ? Streak::register_open( $user_id ) : null;
		$base   = $streak ? (int) $streak['today']['points'] : (int) Settings::get( 'earn_app_open' );
		$label  = $streak && $streak['today']['day'] > 1
			? sprintf( 'App heute geöffnet · %d Tage in Folge', $streak['today']['day'] )
			: 'App heute geöffnet';
		$r = self::earn(
			$user_id,
			'app_open',
			$base,
			array(
				'idempotency_key' => 'app_open:' . $user_id . ':' . Plugin::today(),
				'label'           => $label,
				'meta'            => $streak ? array( 'streak_day' => $streak['today']['day'], 'streak_event' => $streak['event'] ) : null,
			)
		);
		$r['balance'] = self::balance( $user_id );
		$r['streak']  = $streak ?? array( 'enabled' => false );
		unset( $r['entry_id'] );
		return $r;
	}

	public static function app_open_awarded_today( int $user_id ): bool {
		return self::has_key( 'app_open:' . $user_id . ':' . Plugin::today() );
	}
}
