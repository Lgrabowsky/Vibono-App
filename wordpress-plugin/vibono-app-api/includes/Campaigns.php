<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Aktionen mit Zeitraum und Multiplikator.
 *
 * kind = earn:   Punkte für die gewählten Aktionen werden multipliziert
 *                (z. B. "Doppelte Punkte fürs Werben, 2 Wochen": reasons = [referral], multiplier = 2).
 * kind = redeem: Punkte sind im Shop mehr wert
 *                (z. B. "Eine Woche doppelter Punktwert": multiplier = 2 → 1 Punkt = 2 Cent).
 * Überschneiden sich Aktionen, gilt die mit dem höchsten Multiplikator (kein Stapeln).
 */
class Campaigns {

	private static $cache = null;

	public static function all(): array {
		if ( null === self::$cache ) {
			global $wpdb;
			$t           = Install::table( 'campaigns' );
			self::$cache = (array) $wpdb->get_results( "SELECT * FROM $t ORDER BY starts_at DESC", ARRAY_A ); // phpcs:ignore
		}
		return self::$cache;
	}

	public static function flush(): void {
		self::$cache = null;
	}

	/** Aktionen im Format für Core\PointsMath (Unix-Zeiten, Gründe als Array). */
	public static function all_for_math(): array {
		return array_map(
			static function ( $c ) {
				return array(
					'id'          => (int) $c['id'],
					'name'        => $c['name'],
					'description' => (string) $c['description'],
					'kind'        => $c['kind'],
					'reasons'     => array_values( array_filter( explode( ',', (string) $c['reasons'] ) ) ),
					'multiplier'  => (float) $c['multiplier'],
					'starts_at'   => strtotime( $c['starts_at'] . ' UTC' ),
					'ends_at'     => strtotime( $c['ends_at'] . ' UTC' ),
					'enabled'     => (bool) $c['enabled'],
				);
			},
			self::all()
		);
	}

	/** Laufende und in den nächsten 14 Tagen startende Aktionen. */
	public static function visible(): array {
		$now = time();
		return array_values(
			array_filter(
				self::all_for_math(),
				static fn( $c ) => $c['enabled'] && $c['ends_at'] > $now && $c['starts_at'] < $now + 14 * DAY_IN_SECONDS
			)
		);
	}

	public static function format( array $c ): array {
		$now = time();
		return array(
			'id'          => (int) $c['id'],
			'name'        => $c['name'],
			'description' => $c['description'] ?? '',
			'kind'        => $c['kind'],
			'reasons'     => $c['reasons'],
			'multiplier'  => (float) $c['multiplier'],
			'starts_at'   => Plugin::iso( $c['starts_at'] ),
			'ends_at'     => Plugin::iso( $c['ends_at'] ),
			'active'      => $c['enabled'] && $now >= $c['starts_at'] && $now < $c['ends_at'],
		);
	}

	/** @return int|\WP_Error */
	public static function save( array $in, int $id = 0 ) {
		global $wpdb;
		$kind = in_array( $in['kind'] ?? '', array( 'earn', 'redeem' ), true ) ? $in['kind'] : null;
		$mult = (float) ( $in['multiplier'] ?? 0 );
		$from = strtotime( (string) ( $in['starts_at'] ?? '' ) );
		$to   = strtotime( (string) ( $in['ends_at'] ?? '' ) );
		if ( ! $kind || $mult <= 0 || $mult > 20 || ! $from || ! $to || $to <= $from || '' === trim( (string) ( $in['name'] ?? '' ) ) ) {
			return new \WP_Error( 'invalid_campaign', 'Bitte Name, Art, Multiplikator (0–20) und einen gültigen Zeitraum angeben.' );
		}
		$reasons = 'earn' === $kind ? array_intersect( (array) ( $in['reasons'] ?? array() ), Core\PointsMath::EARN_REASONS ) : array();
		$row     = array(
			'name'        => sanitize_text_field( $in['name'] ),
			'description' => sanitize_textarea_field( $in['description'] ?? '' ),
			'kind'        => $kind,
			'reasons'     => implode( ',', $reasons ),
			'multiplier'  => $mult,
			'starts_at'   => gmdate( 'Y-m-d H:i:s', $from ),
			'ends_at'     => gmdate( 'Y-m-d H:i:s', $to ),
			'enabled'     => empty( $in['enabled'] ) ? 0 : 1,
		);
		$t = Install::table( 'campaigns' );
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

	public static function delete( int $id ): void {
		global $wpdb;
		$wpdb->delete( Install::table( 'campaigns' ), array( 'id' => $id ) );
		self::flush();
	}
}
