<?php
namespace Vibono\AppApi\Core;

/**
 * Bringt Rezept-Zutaten aus unterschiedlichen Quellen (Textzeilen, Feldgruppen/ACF-Wiederholer,
 * WP Recipe Maker) in ein einheitliches Format für die Einkaufsliste der App:
 * {name: string, amount: float|null, unit: string|null, group: string|null}
 *
 * Reine Logik ohne WordPress, damit sie getestet werden kann.
 */
class Ingredients {

	/** Kanonische Einheit => Schreibweisen (klein, ohne Punkt). */
	const UNITS = array(
		'g'        => array( 'g', 'gr', 'gramm' ),
		'kg'       => array( 'kg', 'kilo', 'kilogramm' ),
		'ml'       => array( 'ml', 'milliliter' ),
		'l'        => array( 'l', 'liter', 'ltr' ),
		'el'       => array( 'el', 'esslöffel', 'eßlöffel', 'essl' ),
		'tl'       => array( 'tl', 'teelöffel', 'teel' ),
		'stück'    => array( 'stück', 'stueck', 'stk', 'st' ),
		'pck'      => array( 'pck', 'päckchen', 'packung', 'packungen', 'pkg', 'pk' ),
		'prise'    => array( 'prise', 'prisen' ),
		'msp'      => array( 'msp', 'messerspitze' ),
		'bund'     => array( 'bund' ),
		'dose'     => array( 'dose', 'dosen' ),
		'becher'   => array( 'becher' ),
		'glas'     => array( 'glas', 'gläser' ),
		'scheibe'  => array( 'scheibe', 'scheiben' ),
		'zehe'     => array( 'zehe', 'zehen' ),
		'tasse'    => array( 'tasse', 'tassen' ),
		'handvoll' => array( 'handvoll' ),
		'kopf'     => array( 'kopf', 'köpfe' ),
		'stange'   => array( 'stange', 'stangen' ),
		'zweig'    => array( 'zweig', 'zweige' ),
	);

	const FRACTIONS = array( '½' => 0.5, '¼' => 0.25, '¾' => 0.75, '⅓' => 0.333, '⅔' => 0.667 );

	/** Einheit vereinheitlichen. Bekannt: kanonische Form. Unbekannt: kleingeschrieben übernehmen (oder null). */
	public static function unit( $raw, bool $known_only = false ): ?string {
		$u = mb_strtolower( trim( (string) $raw, " \t\n\r\0\x0B." ) );
		if ( '' === $u ) {
			return null;
		}
		foreach ( self::UNITS as $canonical => $aliases ) {
			if ( in_array( $u, $aliases, true ) ) {
				return $canonical;
			}
		}
		return $known_only ? null : mb_substr( $u, 0, 20 );
	}

	/** Mengenangabe lesen: "200", "1,5", "1/2", "1 1/2", "½", "2-3" (Spanne: oberer Wert, für den Einkauf). */
	public static function amount( $raw ): ?float {
		if ( is_int( $raw ) || is_float( $raw ) ) {
			return $raw > 0 ? round( (float) $raw, 3 ) : null;
		}
		$s = trim( strtr( (string) $raw, array( ',' => '.' ) ) );
		if ( '' === $s ) {
			return null;
		}
		$parts = preg_split( '/\s*[-–]\s*/u', $s );
		$s     = end( $parts );
		$total = 0.0;
		foreach ( preg_split( '/\s+/u', $s ) as $tok ) {
			if ( isset( self::FRACTIONS[ $tok ] ) ) {
				$total += self::FRACTIONS[ $tok ];
			} elseif ( preg_match( '/^(\d+)\/(\d+)$/', $tok, $m ) && (int) $m[2] > 0 ) {
				$total += (int) $m[1] / (int) $m[2];
			} elseif ( preg_match( '/^(\d+(?:\.\d+)?)([½¼¾⅓⅔])?$/u', $tok, $m ) ) {
				$total += (float) $m[1] + ( isset( $m[2] ) ? self::FRACTIONS[ $m[2] ] : 0 );
			} else {
				return null;
			}
		}
		return $total > 0 ? round( $total, 3 ) : null;
	}

	/** Eine Textzeile wie "200 g Magerquark", "1 Prise Salz", "2 große Zwiebeln" oder "Salz und Pfeffer". */
	public static function parse_line( string $line, ?string $group = null ): ?array {
		$line = trim( preg_replace( '/\s+/u', ' ', html_entity_decode( strip_tags( $line ), ENT_QUOTES, 'UTF-8' ) ) );
		$line = trim( $line, " -•*\t" );
		if ( '' === $line ) {
			return null;
		}
		$amount = null;
		$unit   = null;
		$rest   = $line;
		if ( preg_match( '/^((?:\d+\s+)?\d+(?:[.,]\d+)?(?:\s*\/\s*\d+)?(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?[½¼¾⅓⅔]?|[½¼¾⅓⅔])\s*(.*)$/u', $line, $m ) ) {
			$amount = self::amount( preg_replace( '/\s*\/\s*/', '/', $m[1] ) );
			$rest   = $m[2];
		}
		// Einheit nur übernehmen, wenn sie bekannt ist ("2 große Zwiebeln" hat keine Einheit).
		if ( preg_match( '/^([^\s\d]+)\s+(.+)$/u', $rest, $m ) && null !== self::unit( $m[1], true ) ) {
			$unit = self::unit( $m[1], true );
			$rest = $m[2];
		}
		$name = trim( $rest, " ,;" );
		if ( '' === $name ) {
			return null;
		}
		return array( 'name' => $name, 'amount' => $amount, 'unit' => $unit, 'group' => $group );
	}

	/** Freitext (Zeilen, <br>, <li>). Zeilen mit Doppelpunkt am Ende sind Zwischenüberschriften ("Für das Dressing:"). */
	public static function from_text( string $text ): array {
		$text  = preg_replace( '/<\s*(br|\/li|\/p|\/h\d)\s*\/?>/i', "\n", $text );
		$out   = array();
		$group = null;
		foreach ( preg_split( '/\r\n|\r|\n/', (string) $text ) as $line ) {
			$clean = trim( html_entity_decode( strip_tags( $line ), ENT_QUOTES, 'UTF-8' ) );
			if ( '' === $clean ) {
				continue;
			}
			if ( preg_match( '/^(.{1,60}):$/u', $clean, $m ) ) {
				$group = trim( $m[1] );
				continue;
			}
			$item = self::parse_line( $clean, $group );
			if ( $item ) {
				$out[] = $item;
			}
		}
		return $out;
	}

	/**
	 * Zeilen aus Feldgruppen (z. B. ACF-Wiederholer). Erkennt deutsche und englische Feldnamen;
	 * eine Zeile ohne eigene Menge wird als Text gelesen.
	 */
	public static function from_rows( array $rows ): array {
		$out = array();
		foreach ( $rows as $row ) {
			if ( is_string( $row ) ) {
				$item = self::parse_line( $row );
			} elseif ( is_array( $row ) ) {
				$pick  = static function ( array $keys ) use ( $row ) {
					foreach ( $keys as $k ) {
						if ( isset( $row[ $k ] ) && '' !== $row[ $k ] && ! is_array( $row[ $k ] ) ) {
							return (string) $row[ $k ];
						}
					}
					return '';
				};
				$name   = $pick( array( 'name', 'zutat', 'ingredient', 'bezeichnung', 'title', 'text', 'line' ) );
				$amount = $pick( array( 'amount', 'menge', 'quantity', 'anzahl' ) );
				$unit   = $pick( array( 'unit', 'einheit' ) );
				$group  = $pick( array( 'group', 'gruppe', 'kategorie', 'abschnitt' ) );
				if ( '' === $amount && '' === $unit ) {
					$item = self::parse_line( $name, '' !== $group ? $group : null );
				} else {
					$item = '' === trim( $name ) ? null : array(
						'name'   => trim( strip_tags( $name ) ),
						'amount' => self::amount( $amount ),
						'unit'   => self::unit( $unit ),
						'group'  => '' !== $group ? $group : null,
					);
				}
			} else {
				$item = null;
			}
			if ( $item ) {
				$out[] = $item;
			}
		}
		return $out;
	}

	/** Format von WP Recipe Maker: Gruppen mit "name" und "ingredients" ({amount, unit, name, notes}). */
	public static function from_wprm( array $groups ): array {
		$out = array();
		foreach ( $groups as $g ) {
			$group = isset( $g['name'] ) && '' !== trim( (string) $g['name'] ) ? trim( strip_tags( (string) $g['name'] ) ) : null;
			foreach ( (array) ( $g['ingredients'] ?? array() ) as $i ) {
				$name = trim( strip_tags( (string) ( $i['name'] ?? '' ) ) );
				if ( '' === $name ) {
					continue;
				}
				$notes = trim( strip_tags( (string) ( $i['notes'] ?? '' ) ) );
				$out[] = array(
					'name'   => $notes ? $name . ' (' . $notes . ')' : $name,
					'amount' => self::amount( $i['amount'] ?? '' ),
					'unit'   => self::unit( $i['unit'] ?? '' ),
					'group'  => $group,
				);
			}
		}
		return $out;
	}

	/** Portionen aus "4", "4 Portionen", "für 2 Personen". */
	public static function servings( $raw ): ?int {
		if ( is_int( $raw ) ) {
			$n = $raw;
		} elseif ( preg_match( '/(\d+)/', (string) $raw, $m ) ) {
			$n = (int) $m[1];
		} else {
			return null;
		}
		return $n >= 1 && $n <= 100 ? $n : null;
	}
}
