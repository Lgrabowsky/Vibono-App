<?php
namespace Vibono\AppApi\Core;

/**
 * Rechenregeln des Punktesystems. Reine Logik, ohne WordPress testbar.
 *
 * Aktionen (Campaigns) sind Arrays mit:
 *   kind ('earn'|'redeem'), reasons (string[]; leer = alle), multiplier (float),
 *   starts_at, ends_at (Unix-Zeit), enabled (bool), id (int)
 */
class PointsMath {

	const EARN_REASONS = array( 'app_open', 'article_read', 'lesson_done', 'course_done', 'referral', 'referral_friend', 'purchase' );

	/** Aktionen, die zum Zeitpunkt $now aktiv sind. */
	public static function active( array $campaigns, int $now, string $kind, ?string $reason = null ): array {
		return array_values(
			array_filter(
				$campaigns,
				static function ( $c ) use ( $now, $kind, $reason ) {
					if ( empty( $c['enabled'] ) || $c['kind'] !== $kind ) {
						return false;
					}
					if ( $now < (int) $c['starts_at'] || $now >= (int) $c['ends_at'] ) {
						return false;
					}
					if ( null !== $reason && ! empty( $c['reasons'] ) && ! in_array( $reason, $c['reasons'], true ) ) {
						return false;
					}
					return true;
				}
			)
		);
	}

	/**
	 * Beste passende Aktion. Mehrere Aktionen werden nicht multipliziert, es gilt die mit dem
	 * höchsten Multiplikator (verhindert unbeabsichtigtes Stapeln, z. B. 2 × 3 = 6-fach).
	 *
	 * @return array{0: float, 1: ?array} [Multiplikator, Aktion]
	 */
	public static function best_multiplier( array $campaigns, int $now, string $kind, ?string $reason = null ): array {
		$best = null;
		foreach ( self::active( $campaigns, $now, $kind, $reason ) as $c ) {
			if ( null === $best || (float) $c['multiplier'] > (float) $best['multiplier'] ) {
				$best = $c;
			}
		}
		return array( $best ? max( 0.0, (float) $best['multiplier'] ) : 1.0, $best );
	}

	/** Punkte für eine Aktion inkl. Aktion. Rundung kaufmännisch. */
	public static function earn( int $base, array $campaigns, int $now, string $reason ): array {
		list( $mult, $campaign ) = self::best_multiplier( $campaigns, $now, 'earn', $reason );
		return array(
			'points'     => (int) round( $base * $mult ),
			'base'       => $base,
			'multiplier' => $mult,
			'campaign'   => $campaign,
		);
	}

	/** Aktueller Wert eines Punktes in Cent inkl. Einlöse-Aktion. */
	public static function effective_cents_per_point( float $cents_per_point, array $campaigns, int $now ): float {
		list( $mult ) = self::best_multiplier( $campaigns, $now, 'redeem' );
		return $cents_per_point * $mult;
	}

	/** Punkte für einen Einkauf: Warenwert (ohne Versand, nach Rabatten/Punkten) in Cent. */
	public static function purchase_points( int $net_goods_cents, float $points_per_euro ): int {
		if ( $net_goods_cents <= 0 ) {
			return 0;
		}
		return (int) floor( $net_goods_cents / 100 * $points_per_euro );
	}

	/**
	 * Wie viele Punkte dürfen in diesem Warenkorb eingelöst werden und was sind sie wert?
	 *
	 * @param int   $requested       Gewünschte Punkte.
	 * @param int   $balance         Verfügbare Punkte.
	 * @param int   $cart_cents      Warenwert brutto ohne Versand, nach anderen Rabatten.
	 * @param float $eff_cpp         Effektiver Cent-Wert je Punkt.
	 * @param int   $max_percent     Max. Anteil des Warenwerts.
	 * @param int   $min_points      Mindesteinlösung.
	 * @return array{points:int, cents:int, error:?string}
	 */
	public static function redeemable( int $requested, int $balance, int $cart_cents, float $eff_cpp, int $max_percent, int $min_points ): array {
		if ( $eff_cpp <= 0 || $cart_cents <= 0 ) {
			return array( 'points' => 0, 'cents' => 0, 'error' => 'nothing_to_redeem' );
		}
		$requested = max( 0, min( $requested, $balance ) );
		if ( $requested < $min_points ) {
			return array( 'points' => 0, 'cents' => 0, 'error' => 'below_minimum' );
		}
		$max_cents  = (int) floor( $cart_cents * max( 0, min( 100, $max_percent ) ) / 100 );
		$max_points = (int) floor( $max_cents / $eff_cpp );
		$points     = min( $requested, $max_points );
		if ( $points < $min_points ) {
			return array( 'points' => 0, 'cents' => 0, 'error' => 'cart_too_small' );
		}
		return array( 'points' => $points, 'cents' => (int) floor( $points * $eff_cpp ), 'error' => null );
	}
}
