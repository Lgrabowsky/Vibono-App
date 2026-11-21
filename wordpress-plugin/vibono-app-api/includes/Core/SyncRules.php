<?php
namespace Vibono\AppApi\Core;

/**
 * Regeln der Zwei-Wege-Synchronisation. Reine Logik, ohne WordPress testbar.
 *
 * Jede Sammlung ist eine Menge von Einträgen mit Schlüssel. Konflikte werden je Eintrag
 * per Last-Write-Wins über updated_at (Millisekunden) entschieden. Bei Gleichstand gewinnt
 * der Server, damit alle Geräte denselben Stand erreichen.
 */
class SyncRules {

	const COLLECTIONS = array( 'favorites', 'lessons_done', 'courses_done', 'weight', 'sport', 'weekplan', 'challenges' );

	const WEEKPLAN_SLOTS = array( 'fruehstueck', 'mittag', 'abend', 'snack' );

	/** Pfadname (/me/lessons-done) zu Sammlungsname (lessons_done). */
	public static function collection_from_path( string $path ): ?string {
		$c = str_replace( '-', '_', $path );
		return in_array( $c, self::COLLECTIONS, true ) ? $c : null;
	}

	/**
	 * Entscheidet, ob eine eingehende Änderung den Serverstand ersetzt.
	 *
	 * @param int|null $server_updated_ms null = Eintrag existiert auf dem Server noch nicht.
	 */
	public static function incoming_wins( int $incoming_ms, ?int $server_updated_ms ): bool {
		return null === $server_updated_ms || $incoming_ms > $server_updated_ms;
	}

	/**
	 * Prüft und normalisiert Schlüssel und Daten einer Änderung.
	 *
	 * @return array{0: ?array, 1: ?string} [normalisierte Daten, Fehlercode]
	 */
	public static function validate( string $collection, string $key, string $op, $data ): array {
		if ( ! in_array( $collection, self::COLLECTIONS, true ) ) {
			return array( null, 'unknown_collection' );
		}
		if ( ! in_array( $op, array( 'upsert', 'delete' ), true ) ) {
			return array( null, 'invalid_op' );
		}
		if ( '' === $key || strlen( $key ) > 100 ) {
			return array( null, 'invalid_key' );
		}
		$data = is_array( $data ) ? $data : array();

		switch ( $collection ) {
			case 'favorites':
				if ( ! preg_match( '/^(recipe|tip|lesson):(\d+)$/', $key, $m ) ) {
					return array( null, 'invalid_key' );
				}
				return array( array( 'post_id' => (int) $m[2], 'kind' => $m[1] ), null );

			case 'lessons_done':
			case 'courses_done':
				if ( ! ctype_digit( $key ) ) {
					return array( null, 'invalid_key' );
				}
				$field = 'lessons_done' === $collection ? 'post_id' : 'term_id';
				return array( array( $field => (int) $key ), null );

			case 'weight':
				if ( ! self::is_date( $key ) ) {
					return array( null, 'invalid_key' );
				}
				if ( 'delete' === $op ) {
					return array( array( 'date' => $key ), null );
				}
				$kg = isset( $data['kg'] ) ? (float) $data['kg'] : 0.0;
				if ( $kg < 30 || $kg > 400 ) {
					return array( null, 'invalid_weight' );
				}
				return array( array( 'date' => $key, 'kg' => round( $kg, 1 ) ), null );

			case 'sport':
				if ( ! preg_match( '/^[A-Za-z0-9-]{8,64}$/', $key ) ) {
					return array( null, 'invalid_key' );
				}
				if ( 'delete' === $op ) {
					return array( array(), null );
				}
				$date = (string) ( $data['date'] ?? '' );
				$min  = (int) ( $data['minutes'] ?? 0 );
				if ( ! self::is_date( $date ) || $min < 1 || $min > 1440 ) {
					return array( null, 'invalid_sport' );
				}
				return array(
					array(
						'date'     => $date,
						'activity' => mb_substr( trim( (string) ( $data['activity'] ?? '' ) ), 0, 80 ),
						'minutes'  => $min,
						'note'     => mb_substr( trim( (string) ( $data['note'] ?? '' ) ), 0, 500 ),
					),
					null,
				);

			case 'weekplan':
				if ( ! preg_match( '/^(\d{4}-\d{2}-\d{2}):([a-z]+)$/', $key, $m ) || ! self::is_date( $m[1] ) || ! in_array( $m[2], self::WEEKPLAN_SLOTS, true ) ) {
					return array( null, 'invalid_key' );
				}
				if ( 'delete' === $op ) {
					return array( array( 'date' => $m[1], 'slot' => $m[2] ), null );
				}
				$data   = is_array( $data ) ? $data : array();
				$recipe = isset( $data['recipe_id'] ) ? (int) $data['recipe_id'] : null;
				$note   = mb_substr( trim( (string) ( $data['note'] ?? '' ) ), 0, 500 );
				// Portionen (1–12), für die eingekauft und gekocht wird. Fehlt der Wert, gilt die Rezeptangabe.
				$portions = null;
				if ( isset( $data['portions'] ) ) {
					if ( ! is_numeric( $data['portions'] ) || (int) $data['portions'] != $data['portions'] || $data['portions'] < 1 || $data['portions'] > 12 ) { // phpcs:ignore
						return array( null, 'invalid_weekplan' );
					}
					$portions = (int) $data['portions'];
				}
				// Ohne Rezept und ohne Notiz: Platz bewusst frei (die App schlägt dort nichts vor).
				return array(
					array(
						'date'      => $m[1],
						'slot'      => $m[2],
						'recipe_id' => $recipe ?: null,
						'note'      => $note,
						'portions'  => $portions,
					),
					null,
				);

			case 'challenges':
				// Teilnahme an einer Challenge der Startseite, Schlüssel = ID der Challenge.
				return HomeRules::validate_participation( $key, $op, $data );
		}
		return array( null, 'unknown_collection' );
	}

	public static function is_date( string $d ): bool {
		if ( ! preg_match( '/^(\d{4})-(\d{2})-(\d{2})$/', $d, $m ) ) {
			return false;
		}
		return checkdate( (int) $m[2], (int) $m[3], (int) $m[1] );
	}

	/** ISO-8601 zu Millisekunden; null bei ungültigem Wert. Zeiten weit in der Zukunft werden auf "jetzt" gekappt. */
	public static function parse_time_ms( string $iso, int $now_ms ): ?int {
		$ts = strtotime( $iso );
		if ( false === $ts ) {
			return null;
		}
		$ms = $ts * 1000;
		if ( preg_match( '/\.(\d{1,3})/', $iso, $m ) ) {
			$ms += (int) str_pad( $m[1], 3, '0' );
		}
		// Schutz gegen falsch gestellte Geräteuhren: max. 5 Minuten in der Zukunft.
		return min( $ms, $now_ms + 300000 );
	}
}
