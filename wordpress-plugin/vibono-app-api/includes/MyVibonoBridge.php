<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Brücke zwischen der Sync-Tabelle und den Speicherorten, die das Theme "vibono" für
 * MyVibono nutzt (Lieblingsrezepte, Mein Gewicht, Mein Sport, Mein Wochenplan, Coaching-Häkchen).
 *
 * ANNAHME: Der Theme-Code liegt noch nicht vor. Deshalb ist die Brücke über Adapter austauschbar:
 *  - Standard: Nutzer-Meta mit konfigurierbarem Schlüssel (Einstellungen → "MyVibono-Speicherorte").
 *    Erwartetes Format je Sammlung siehe self::to_theme() / self::from_theme().
 *  - Eigener Adapter: Filter "vibono_api_myvibono_adapter" liefert ein Objekt mit
 *    read(int $user_id, string $collection): ?array (Schlüssel => Daten) und
 *    write(int $user_id, string $collection, array $items): void.
 *
 * Ablauf:
 *  - Vor jedem Abruf (GET /sync, GET /me/{collection}) wird reconcile() aufgerufen: Was sich im Theme
 *    geändert hat (Website-Nutzung), wird als Änderung mit Quelle "web" in die Sync-Tabelle übernommen.
 *  - Nach jeder App-Änderung schreibt write_through() den kompletten Stand der Sammlung ins Theme,
 *    aber nur, wenn "myvibono_write" eingeschaltet ist. Standard ist nur lesen, damit ein falsch
 *    angenommenes Format die Website-Daten nicht verändern kann.
 *  - Vor dem ersten Schreiben wird der ursprüngliche Wert je Nutzer*in in "_vibono_bak_<meta>" gesichert
 *    (Rückbau: wp vibono restore-myvibono). Das Speicherformat (Array, JSON-Text, Komma-Liste) bleibt erhalten.
 */
class MyVibonoBridge {

	/** Präfix der einmaligen Sicherung eines Theme-Felds vor dem ersten Schreiben. */
	const BACKUP_PREFIX = '_vibono_bak_';

	/** @return object|null */
	private static function adapter( string $collection ) {
		$custom = apply_filters( 'vibono_api_myvibono_adapter', null, $collection );
		if ( $custom ) {
			return $custom;
		}
		$meta = (string) Settings::get( 'store_' . $collection . '_meta' );
		return $meta ? new MetaAdapter( $meta ) : null;
	}

	public static function reconcile( int $user_id, array $collections ): void {
		foreach ( $collections as $collection ) {
			$adapter = self::adapter( $collection );
			if ( ! $adapter ) {
				continue;
			}
			$raw = $adapter->read( $user_id, $collection );
			if ( null === $raw ) {
				continue;
			}
			$theme = self::from_theme( $collection, $raw );
			$ours  = SyncStore::current_map( $user_id, $collection );
			$now   = Plugin::now_ms();

			// Neu oder geändert auf der Website.
			foreach ( $theme as $key => $data ) {
				if ( ! array_key_exists( $key, $ours ) || $ours[ $key ] != $data ) { // phpcs:ignore -- lockerer Vergleich gewollt (Zahlen als String).
					SyncStore::put( $user_id, $collection, (string) $key, $data, false, $now, 'web' );
				}
			}
			// Auf der Website entfernt.
			foreach ( array_diff_key( $ours, $theme ) as $key => $unused ) {
				SyncStore::put( $user_id, $collection, (string) $key, null, true, $now, 'web' );
			}
		}
	}

	public static function write_through( int $user_id, string $collection ): void {
		if ( ! Settings::on( 'myvibono_write' ) ) {
			return;
		}
		$adapter = self::adapter( $collection );
		if ( ! $adapter ) {
			return;
		}
		$adapter->write( $user_id, $collection, self::to_theme( $collection, SyncStore::current_map( $user_id, $collection ) ) );
	}

	/**
	 * Theme-Format → Sync-Einträge (Schlüssel => Daten).
	 * ANNAHMEN zum Theme-Format:
	 *  favorites:    Liste von Post-IDs (Rezepte) oder ["recipe" => [..], "tip" => [..]]
	 *  lessons_done: [post_id => 1] wie die Checkboxen done[post_id] auf "Mein Coaching"
	 *  courses_done: Liste von Term-IDs
	 *  weight:       ["YYYY-MM-DD" => kg]
	 *  sport:        Liste von {id, date, activity, minutes, note}
	 *  weekplan:     ["YYYY-MM-DD" => ["mittag" => recipe_id|{recipe_id, note}, ...]]
	 */
	public static function from_theme( string $collection, $raw ): array {
		$raw = is_array( $raw ) ? $raw : array();
		$out = array();
		switch ( $collection ) {
			case 'favorites':
				$groups = isset( $raw['recipe'] ) || isset( $raw['tip'] ) ? $raw : array( 'recipe' => $raw );
				foreach ( $groups as $kind => $ids ) {
					foreach ( (array) $ids as $id ) {
						$out[ $kind . ':' . (int) $id ] = array( 'post_id' => (int) $id, 'kind' => $kind );
					}
				}
				break;
			case 'lessons_done':
				foreach ( $raw as $k => $v ) {
					$id = is_int( $k ) && 1 == $v ? $k : (int) $v; // phpcs:ignore
					if ( $id > 0 ) {
						$out[ (string) $id ] = array( 'post_id' => $id );
					}
				}
				break;
			case 'courses_done':
				foreach ( $raw as $id ) {
					$out[ (string) (int) $id ] = array( 'term_id' => (int) $id );
				}
				break;
			case 'weight':
				foreach ( $raw as $date => $kg ) {
					$out[ $date ] = array( 'date' => $date, 'kg' => round( (float) $kg, 1 ) );
				}
				break;
			case 'sport':
				foreach ( $raw as $entry ) {
					if ( ! empty( $entry['id'] ) ) {
						$out[ (string) $entry['id'] ] = array(
							'date'     => (string) ( $entry['date'] ?? '' ),
							'activity' => (string) ( $entry['activity'] ?? '' ),
							'minutes'  => (int) ( $entry['minutes'] ?? 0 ),
							'note'     => (string) ( $entry['note'] ?? '' ),
						);
					}
				}
				break;
			case 'weekplan':
				foreach ( $raw as $date => $slots ) {
					foreach ( (array) $slots as $slot => $val ) {
						$recipe = is_array( $val ) ? ( $val['recipe_id'] ?? null ) : $val;
						$note   = is_array( $val ) ? (string) ( $val['note'] ?? '' ) : '';
						$out[ $date . ':' . $slot ] = array(
							'date'      => $date,
							'slot'      => $slot,
							'recipe_id' => $recipe ? (int) $recipe : null,
							'note'      => $note,
						);
					}
				}
				break;
		}
		return $out;
	}

	public static function to_theme( string $collection, array $items ) {
		$out = array();
		switch ( $collection ) {
			case 'favorites':
				foreach ( $items as $d ) {
					$out[ $d['kind'] ][] = (int) $d['post_id'];
				}
				// Nur Rezepte → einfache Liste (vermutetes Theme-Format).
				if ( array_keys( $out ) === array( 'recipe' ) ) {
					$out = $out['recipe'];
				}
				break;
			case 'lessons_done':
				foreach ( $items as $d ) {
					$out[ (int) $d['post_id'] ] = 1;
				}
				break;
			case 'courses_done':
				foreach ( $items as $d ) {
					$out[] = (int) $d['term_id'];
				}
				break;
			case 'weight':
				foreach ( $items as $d ) {
					$out[ $d['date'] ] = $d['kg'];
				}
				ksort( $out );
				break;
			case 'sport':
				foreach ( $items as $key => $d ) {
					$out[] = array( 'id' => $key ) + $d;
				}
				break;
			case 'weekplan':
				foreach ( $items as $d ) {
					$out[ $d['date'] ][ $d['slot'] ] = $d['note'] ? array( 'recipe_id' => $d['recipe_id'], 'note' => $d['note'] ) : $d['recipe_id'];
				}
				ksort( $out );
				break;
		}
		return $out;
	}
}

/**
 * Standard-Adapter: ein Nutzer-Meta-Feld je Sammlung.
 */
class MetaAdapter {

	private $key;

	public function __construct( string $key ) {
		$this->key = $key;
	}

	public function read( int $user_id, string $collection ): ?array {
		$v = get_user_meta( $user_id, $this->key, true );
		if ( is_string( $v ) && '' !== $v ) {
			$decoded = json_decode( $v, true );
			$v       = is_array( $decoded ) ? $decoded : array_filter( array_map( 'intval', explode( ',', $v ) ) );
		}
		return is_array( $v ) ? $v : array();
	}

	public function write( int $user_id, string $collection, array $items ): void {
		$exists  = metadata_exists( 'user', $user_id, $this->key );
		$current = get_user_meta( $user_id, $this->key, true );
		// Einmalige Sicherung des Website-Stands vor dem ersten Schreiben des Plugins.
		add_user_meta(
			$user_id,
			MyVibonoBridge::BACKUP_PREFIX . $this->key,
			array(
				'at'      => gmdate( 'c' ),
				'existed' => $exists,
				'value'   => $current,
			),
			true
		);
		update_user_meta( $user_id, $this->key, self::in_format_of( $current, $items ) );
	}

	/** Neuen Stand im selben Format speichern wie bisher (JSON-Text, Komma-Liste oder Array). */
	private static function in_format_of( $current, array $items ) {
		if ( is_string( $current ) && '' !== $current ) {
			if ( is_array( json_decode( $current, true ) ) ) {
				return wp_json_encode( $items );
			}
			// Komma-Liste von IDs: Liste [12, 15] oder Häkchen-Form [12 => 1, 15 => 1].
			if ( array_is_list( $items ) && count( array_filter( $items, 'is_scalar' ) ) === count( $items ) ) {
				return implode( ',', $items );
			}
			if ( ! array_is_list( $items ) && count( array_filter( $items, static fn( $v ) => 1 == $v ) ) === count( $items ) ) { // phpcs:ignore
				return implode( ',', array_keys( $items ) );
			}
		}
		return $items;
	}
}
