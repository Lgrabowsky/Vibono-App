<?php
namespace Vibono\AppApi\Core;

/**
 * Serie (Streak) fürs tägliche Öffnen der App. Reine Logik, ohne WordPress testbar.
 *
 * Zustand einer Person (Nutzer-Meta):
 *   days        Tage in Folge (inkl. des letzten Öffnens)
 *   best        längste Serie
 *   last_date   letzter Tag mit Öffnen (Y-m-d, Website-Zeitzone)
 *   grace_month Monat (Y-m), auf den sich grace_used bezieht
 *   grace_used  in diesem Monat verbrauchte Schutztage
 *
 * Stufen: [['from_day' => 1, 'points' => 5], ['from_day' => 3, 'points' => 6], …]. Die Stufe mit dem
 * höchsten erreichten from_day bestimmt die Punkte des Tages. Stufe 1 (ab Tag 1) ist immer da.
 *
 * Verpasste Tage: Solange Schutztage im laufenden Monat übrig sind, überbrücken sie Lücken (die Serie
 * hält, verpasste Tage zählen aber nicht mit). Reicht das nicht, greift on_break:
 *   reset       Serie beginnt wieder bei Tag 1
 *   drop_level  Serie fällt auf den Anfang der vorherigen Stufe zurück (z. B. von Tag 20 auf Tag 7)
 */
class StreakMath {

	const MODES = array( 'reset', 'drop_level' );

	/** Stufen aus Grundwert (Tag 1) und weiteren Stufen bauen: sortiert, ohne Dubletten, ab Tag 2. */
	public static function levels( int $base, array $raw ): array {
		$by_day = array( 1 => max( 0, $base ) );
		foreach ( $raw as $l ) {
			$day    = (int) ( $l['from_day'] ?? $l['days'] ?? $l[0] ?? 0 );
			$points = (int) ( $l['points'] ?? $l[1] ?? 0 );
			if ( $day >= 2 && $day <= 3650 && $points >= 0 ) {
				$by_day[ $day ] = $points;
			}
		}
		ksort( $by_day );
		$out = array();
		foreach ( $by_day as $day => $points ) {
			$out[] = array( 'from_day' => $day, 'points' => $points );
		}
		return $out;
	}

	/** Index der Stufe für eine Serienlänge. */
	public static function stage_index( int $days, array $levels ): int {
		$idx = 0;
		foreach ( $levels as $i => $l ) {
			if ( $days >= $l['from_day'] ) {
				$idx = $i;
			}
		}
		return $idx;
	}

	/** Stufe, Punkte und nächste Stufe für eine Serienlänge. */
	public static function stage( int $days, array $levels ): array {
		$i    = self::stage_index( max( 1, $days ), $levels );
		$next = $levels[ $i + 1 ] ?? null;
		return array(
			'index'      => $i,
			'from_day'   => $levels[ $i ]['from_day'],
			'points'     => $levels[ $i ]['points'],
			'next_stage' => $next ? array(
				'from_day'  => $next['from_day'],
				'points'    => $next['points'],
				'days_left' => max( 0, $next['from_day'] - max( 1, $days ) ),
			) : null,
		);
	}

	/** Tage von $from bis $to (Y-m-d). Positiv, wenn $to später ist. */
	public static function days_between( string $from, string $to ): int {
		$a = \DateTimeImmutable::createFromFormat( '!Y-m-d', $from, new \DateTimeZone( 'UTC' ) );
		$b = \DateTimeImmutable::createFromFormat( '!Y-m-d', $to, new \DateTimeZone( 'UTC' ) );
		if ( ! $a || ! $b ) {
			return PHP_INT_MAX;
		}
		return (int) round( ( $b->getTimestamp() - $a->getTimestamp() ) / 86400 );
	}

	public static function empty_state(): array {
		return array( 'days' => 0, 'best' => 0, 'last_date' => null, 'grace_month' => null, 'grace_used' => 0 );
	}

	public static function normalize( $state ): array {
		$s = array_merge( self::empty_state(), is_array( $state ) ? $state : array() );
		return array(
			'days'        => max( 0, (int) $s['days'] ),
			'best'        => max( 0, (int) $s['best'], (int) $s['days'] ),
			'last_date'   => is_string( $s['last_date'] ) && '' !== $s['last_date'] ? $s['last_date'] : null,
			'grace_month' => is_string( $s['grace_month'] ) && '' !== $s['grace_month'] ? $s['grace_month'] : null,
			'grace_used'  => max( 0, (int) $s['grace_used'] ),
		);
	}

	/** Übrige Schutztage im Monat von $today. */
	public static function grace_left( array $state, string $today, int $per_month ): int {
		$used = ( $state['grace_month'] ?? null ) === substr( $today, 0, 7 ) ? (int) $state['grace_used'] : 0;
		return max( 0, $per_month - $used );
	}

	/**
	 * Öffnen am Tag $today verbuchen.
	 *
	 * @return array{state: array, event: string, bridged_days: int, previous_days: int}
	 *   event: first (erste Serie), continued, bridged (Lücke mit Schutztagen überbrückt),
	 *          broken (Serie gerissen, on_break angewendet), same_day (heute schon gezählt)
	 */
	public static function advance( $state, string $today, array $levels, int $grace_per_month, string $mode ): array {
		$s    = self::normalize( $state );
		$prev = $s['days'];
		$out  = array( 'state' => $s, 'event' => 'same_day', 'bridged_days' => 0, 'previous_days' => $prev );

		if ( null === $s['last_date'] || $prev <= 0 ) {
			$s['days']  = 1;
			$out['event'] = 'first';
		} else {
			$gap = self::days_between( $s['last_date'], $today );
			if ( $gap <= 0 ) {
				return $out; // Heute schon gezählt (oder Uhr zurückgestellt): nichts ändern.
			}
			if ( 1 === $gap ) {
				++$s['days'];
				$out['event'] = 'continued';
			} else {
				$missed = $gap - 1;
				$left   = self::grace_left( $s, $today, $grace_per_month );
				if ( $missed <= $left ) {
					$month = substr( $today, 0, 7 );
					$s['grace_used']  = ( $s['grace_month'] === $month ? $s['grace_used'] : 0 ) + $missed;
					$s['grace_month'] = $month;
					++$s['days'];
					$out['event']        = 'bridged';
					$out['bridged_days'] = $missed;
				} else {
					$out['event'] = 'broken';
					if ( 'drop_level' === $mode ) {
						$i         = self::stage_index( $prev, $levels );
						$s['days'] = $i > 0 ? (int) $levels[ $i - 1 ]['from_day'] : 1;
					} else {
						$s['days'] = 1;
					}
				}
			}
		}
		$s['last_date'] = $today;
		$s['best']      = max( $s['best'], $s['days'] );
		$out['state']   = $s;
		return $out;
	}

	/**
	 * Ansicht für die App: Serie und Punkte, wie sie heute gelten (nach dem Öffnen bzw. falls heute
	 * geöffnet würde), ohne etwas zu speichern.
	 */
	public static function view( $state, string $today, array $levels, int $grace_per_month, string $mode ): array {
		$s       = self::normalize( $state );
		$opened  = null !== $s['last_date'] && self::days_between( $s['last_date'], $today ) <= 0;
		$preview = self::advance( $s, $today, $levels, $grace_per_month, $mode );
		$alive   = $opened || ( $s['days'] > 0 && in_array( $preview['event'], array( 'continued', 'bridged' ), true ) );
		$today_d = $preview['state']['days'];
		$stage   = self::stage( $today_d, $levels );
		return array(
			'days'            => $opened || $alive ? $s['days'] : 0,
			'best'            => $s['best'],
			'opened_today'    => $opened,
			'alive'           => $alive,
			'today'           => array(
				'day'    => $today_d,
				'points' => $stage['points'],
			),
			'stage'           => array( 'from_day' => $stage['from_day'], 'points' => $stage['points'] ),
			'next_stage'      => $stage['next_stage'],
			'levels'          => $levels,
			'grace_per_month' => $grace_per_month,
			'grace_left'      => self::grace_left( $opened ? $s : $preview['state'], $today, $grace_per_month ),
			'on_break'        => $mode,
		);
	}

	/**
	 * Serie aus bisherigen Öffnen-Tagen ableiten (Übernahme, wenn es noch keinen Zustand gibt).
	 * Zählt die lückenlose Folge, die heute oder gestern endet.
	 *
	 * @param string[] $dates Tage (Y-m-d) mit Öffnen.
	 */
	public static function from_dates( array $dates, string $today ): array {
		$set = array_flip( array_filter( array_map( 'strval', $dates ) ) );
		$s   = self::empty_state();
		if ( ! $set ) {
			return $s;
		}
		// Längste Serie überhaupt.
		$sorted = array_keys( $set );
		sort( $sorted );
		$best = 0;
		$run  = 0;
		$prev = null;
		foreach ( $sorted as $d ) {
			$run  = ( null !== $prev && 1 === self::days_between( $prev, $d ) ) ? $run + 1 : 1;
			$best = max( $best, $run );
			$prev = $d;
		}
		$s['best'] = $best;

		$cursor = new \DateTimeImmutable( $today, new \DateTimeZone( 'UTC' ) );
		if ( ! isset( $set[ $cursor->format( 'Y-m-d' ) ] ) ) {
			$cursor = $cursor->modify( '-1 day' );
			if ( ! isset( $set[ $cursor->format( 'Y-m-d' ) ] ) ) {
				return $s; // Keine laufende Serie.
			}
		}
		$s['last_date'] = $cursor->format( 'Y-m-d' );
		$days           = 0;
		while ( isset( $set[ $cursor->format( 'Y-m-d' ) ] ) ) {
			++$days;
			$cursor = $cursor->modify( '-1 day' );
		}
		$s['days'] = $days;
		return $s;
	}
}
