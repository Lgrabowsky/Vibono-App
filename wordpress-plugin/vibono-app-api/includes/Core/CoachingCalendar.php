<?php
namespace Vibono\AppApi\Core;

/**
 * Bestimmt Phase und Tag im Vibono-Konzept. Reine Logik, ohne WordPress testbar.
 *
 * Coaching-Tag 1 = Startdatum = 1. Umstellungstag.
 *  - Vorbereitung: vor dem Startdatum (oder ohne Startdatum)
 *  - Phase 1 "Umstellungstage": Tag 1..p1 (Standard 2)
 *  - Phase 2 "Gewohnheiten ändern": die nächsten p2 Tage (Standard 10)
 *  - Phase 3 "Satt essen & genießen": danach dauerhaft; Etappenziele nach 3, 6, 12 Monaten.
 * Tage haben keine Uhrzeiten.
 */
class CoachingCalendar {

	public static function day( ?string $start_date, string $date, int $p1 = 2, int $p2 = 10 ): array {
		$coaching_day = 0;
		if ( $start_date && SyncRules::is_date( $start_date ) ) {
			$diff         = ( new \DateTimeImmutable( $start_date ) )->diff( new \DateTimeImmutable( $date ) );
			$coaching_day = $diff->invert ? 0 : $diff->days + 1;
		}

		if ( $coaching_day <= 0 ) {
			return array(
				'key'          => 'vorbereitung',
				'label'        => 'Vorbereitung',
				'day_in_phase' => 1,
				'day_label'    => $start_date ? 'Vorbereitung auf den Start' : 'Startdatum festlegen',
				'coaching_day' => 0,
				'phase_progress' => 0.0,
			);
		}
		if ( $coaching_day <= $p1 ) {
			return array(
				'key'            => 'phase1',
				'label'          => 'Phase 1: Umstellungstage',
				'day_in_phase'   => $coaching_day,
				'day_label'      => $coaching_day . '. Umstellungstag',
				'coaching_day'   => $coaching_day,
				'phase_progress' => $coaching_day / max( 1, $p1 ),
			);
		}
		if ( $coaching_day <= $p1 + $p2 ) {
			$d = $coaching_day - $p1;
			return array(
				'key'            => 'phase2',
				'label'          => 'Phase 2: Gewohnheiten ändern',
				'day_in_phase'   => $d,
				'day_label'      => 'Tag ' . $d . ' von ' . $p2,
				'coaching_day'   => $coaching_day,
				'phase_progress' => $d / max( 1, $p2 ),
			);
		}
		$d = $coaching_day - $p1 - $p2;
		return array(
			'key'            => 'phase3',
			'label'          => 'Phase 3: Satt essen & genießen',
			'day_in_phase'   => $d,
			'day_label'      => 'Tag ' . $d,
			'coaching_day'   => $coaching_day,
			'phase_progress' => min( 1.0, $coaching_day / 365 ),
		);
	}

	/** Etappenziele (3, 6, 12 Monate nach Start). */
	public static function milestones( ?string $start_date, array $goals, ?float $current_kg, string $today ): array {
		if ( ! $start_date || ! SyncRules::is_date( $start_date ) ) {
			return array();
		}
		$start = new \DateTimeImmutable( $start_date );
		$out   = array();
		foreach ( array( 'm3' => 3, 'm6' => 6, 'm12' => 12 ) as $key => $months ) {
			$target = $goals[ 'target_weight_' . $months . 'm_kg' ] ?? null;
			$date   = $start->modify( '+' . $months . ' months' )->format( 'Y-m-d' );
			$out[]  = array(
				'key'              => $key,
				'date'             => $date,
				'target_weight_kg' => null === $target ? null : (float) $target,
				'reached'          => null !== $target && null !== $current_kg && $current_kg <= (float) $target,
			);
		}
		return $out;
	}

	/** Fortschritt Richtung 12-Monats-Ziel nach Gewicht, sonst nach Zeit. */
	public static function overall_progress( ?string $start_date, array $goals, ?float $current_kg, string $today ): float {
		$start_kg  = isset( $goals['start_weight_kg'] ) ? (float) $goals['start_weight_kg'] : null;
		$target_kg = isset( $goals['target_weight_12m_kg'] ) ? (float) $goals['target_weight_12m_kg'] : null;
		if ( $start_kg && $target_kg && null !== $current_kg && $start_kg > $target_kg ) {
			return max( 0.0, min( 1.0, ( $start_kg - $current_kg ) / ( $start_kg - $target_kg ) ) );
		}
		if ( $start_date && SyncRules::is_date( $start_date ) ) {
			$diff = ( new \DateTimeImmutable( $start_date ) )->diff( new \DateTimeImmutable( $today ) );
			return $diff->invert ? 0.0 : min( 1.0, $diff->days / 365 );
		}
		return 0.0;
	}
}
