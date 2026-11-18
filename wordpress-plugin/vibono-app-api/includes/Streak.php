<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\StreakMath;

defined( 'ABSPATH' ) || exit;

/**
 * Serie (Streak) fürs tägliche Öffnen der App: je mehr Tage in Folge, desto mehr Punkte pro Tag.
 * Regeln in Core\StreakMath, Einstellungen unter Vibono-Punkte → Kurs & Regeln.
 * Der Zustand liegt im Nutzer-Meta "_vibono_app_streak" (wird mit dem Konto gelöscht).
 */
class Streak {

	const META = '_vibono_app_streak';

	public static function enabled(): bool {
		return (bool) Settings::get( 'streak_enabled' );
	}

	public static function levels(): array {
		return StreakMath::levels( (int) Settings::get( 'earn_app_open' ), (array) Settings::get( 'streak_levels' ) );
	}

	public static function grace(): int {
		return max( 0, (int) Settings::get( 'streak_grace_per_month' ) );
	}

	public static function mode(): string {
		$m = (string) Settings::get( 'streak_on_break' );
		return in_array( $m, StreakMath::MODES, true ) ? $m : 'drop_level';
	}

	/** Zustand laden. Gibt es noch keinen, wird er einmalig aus den bisherigen Öffnen-Buchungen abgeleitet. */
	public static function state( int $user_id ): array {
		$s = get_user_meta( $user_id, self::META, true );
		if ( is_array( $s ) ) {
			return StreakMath::normalize( $s );
		}
		return StreakMath::from_dates( self::open_dates( $user_id ), Plugin::today() );
	}

	public static function save( int $user_id, array $state ): void {
		update_user_meta( $user_id, self::META, StreakMath::normalize( $state ) );
	}

	/** Tage (Website-Zeitzone) mit Öffnen-Buchung in den letzten 400 Tagen. */
	private static function open_dates( int $user_id ): array {
		global $wpdb;
		$t    = Install::table( 'points_ledger' );
		$rows = $wpdb->get_col( $wpdb->prepare( "SELECT created_at FROM $t WHERE user_id = %d AND reason = 'app_open' AND status <> 'void' AND created_at >= %s", $user_id, gmdate( 'Y-m-d H:i:s', time() - 400 * DAY_IN_SECONDS ) ) );
		$tz   = wp_timezone();
		return array_values(
			array_unique(
				array_map(
					static fn( $c ) => ( new \DateTimeImmutable( $c, new \DateTimeZone( 'UTC' ) ) )->setTimezone( $tz )->format( 'Y-m-d' ),
					(array) $rows
				)
			)
		);
	}

	/**
	 * Öffnen von heute verbuchen (idempotent: am selben Tag ändert sich nichts).
	 *
	 * @return array Ansicht wie view(), dazu event, bridged_days, previous_days.
	 */
	public static function register_open( int $user_id ): array {
		$today  = Plugin::today();
		$levels = self::levels();
		$r      = StreakMath::advance( self::state( $user_id ), $today, $levels, self::grace(), self::mode() );
		if ( 'same_day' !== $r['event'] || ! is_array( get_user_meta( $user_id, self::META, true ) ) ) {
			self::save( $user_id, $r['state'] );
		}
		if ( 'same_day' !== $r['event'] ) {
			do_action( 'vibono_streak_updated', $user_id, $r );
		}
		return array_merge(
			self::view( $user_id, $r['state'] ),
			array(
				'event'         => $r['event'],
				'bridged_days'  => $r['bridged_days'],
				'previous_days' => $r['previous_days'],
			)
		);
	}

	/** Ansicht für App und Testzentrale (ohne zu speichern). */
	public static function view( int $user_id, ?array $state = null ): array {
		if ( ! self::enabled() ) {
			return array( 'enabled' => false );
		}
		$v = StreakMath::view( $state ?? self::state( $user_id ), Plugin::today(), self::levels(), self::grace(), self::mode() );
		return array( 'enabled' => true ) + $v;
	}

	/** Kennzahlen fürs Backend: Personen mit laufender Serie, längste laufende Serie. */
	public static function stats(): array {
		global $wpdb;
		$rows   = $wpdb->get_col( $wpdb->prepare( "SELECT meta_value FROM {$wpdb->usermeta} WHERE meta_key = %s", self::META ) );
		$today  = Plugin::today();
		$levels = self::levels();
		$out    = array( 'active' => 0, 'longest' => 0, 'by_stage' => array_fill( 0, count( $levels ), 0 ) );
		foreach ( (array) $rows as $raw ) {
			$v = StreakMath::view( maybe_unserialize( $raw ), $today, $levels, self::grace(), self::mode() );
			if ( $v['days'] > 0 ) {
				++$out['active'];
				$out['longest'] = max( $out['longest'], $v['days'] );
				++$out['by_stage'][ StreakMath::stage_index( $v['days'], $levels ) ];
			}
		}
		return $out;
	}
}
