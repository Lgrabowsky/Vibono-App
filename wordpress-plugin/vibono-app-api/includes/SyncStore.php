<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\SyncRules;

defined( 'ABSPATH' ) || exit;

/**
 * Speicher der Zwei-Wege-Synchronisation.
 *
 * Die Tabelle vibono_sync hält je (Nutzer, Sammlung, Schlüssel) den aktuellen Stand und eine
 * fortlaufende Nummer (seq), die als Cursor dient. Jede Änderung bekommt eine neue seq,
 * deshalb sieht die App beim nächsten Abruf alles, was sich seitdem geändert hat.
 *
 * Website-Seite (MyVibono): MyVibonoBridge gleicht vor jedem Abruf die Theme-Daten ab und
 * schreibt App-Änderungen in die Theme-Daten zurück.
 */
class SyncStore {

	const MAX_PULL = 1000;

	public static function get( int $user_id, string $collection, string $key ): ?array {
		global $wpdb;
		$t   = Install::table( 'sync' );
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $t WHERE user_id = %d AND collection = %s AND item_key = %s", $user_id, $collection, $key ), ARRAY_A );
		return $row ?: null;
	}

	/**
	 * Schreibt einen Eintrag (neue seq). Gibt die neue seq zurück.
	 */
	public static function put( int $user_id, string $collection, string $key, ?array $data, bool $deleted, int $updated_ms, string $source ): int {
		global $wpdb;
		$t = Install::table( 'sync' );
		// Coaching-Fortschritt: Punkte nur, wenn das Häkchen neu gesetzt wird (vorher fehlend oder gelöscht).
		$coaching = ! $deleted && in_array( $collection, array( 'lessons_done', 'courses_done' ), true );
		$was_set  = false;
		if ( $coaching ) {
			$prev    = self::get( $user_id, $collection, $key );
			$was_set = $prev && ! $prev['deleted'];
		}
		// Löschen + Einfügen statt UPDATE, damit seq (AUTO_INCREMENT) neu vergeben wird.
		$wpdb->query( $wpdb->prepare( "DELETE FROM $t WHERE user_id = %d AND collection = %s AND item_key = %s", $user_id, $collection, $key ) );
		$wpdb->insert(
			$t,
			array(
				'user_id'    => $user_id,
				'collection' => $collection,
				'item_key'   => $key,
				'data'       => $deleted ? null : wp_json_encode( $data ),
				'deleted'    => $deleted ? 1 : 0,
				'updated_at' => $updated_ms,
				'source'     => $source,
			)
		);
		$seq = (int) $wpdb->insert_id;
		if ( $coaching && ! $was_set ) {
			Coaching::on_done( $user_id, $collection, $key, $source );
		}
		return $seq;
	}

	/**
	 * Wendet eine Änderung aus der App an (Last-Write-Wins).
	 *
	 * @return array Ergebnis im Format von SyncPushResponse.results[].
	 */
	public static function apply( int $user_id, array $change, int $now_ms ): array {
		$collection = (string) ( $change['collection'] ?? '' );
		$key        = (string) ( $change['key'] ?? '' );
		$op         = (string) ( $change['op'] ?? '' );
		$result     = array(
			'client_change_id' => isset( $change['client_change_id'] ) ? (string) $change['client_change_id'] : null,
			'collection'       => $collection,
			'key'              => $key,
		);

		list( $data, $err ) = SyncRules::validate( $collection, $key, $op, $change['data'] ?? null );
		$ms                 = SyncRules::parse_time_ms( (string) ( $change['updated_at'] ?? '' ), $now_ms );
		if ( $err || null === $ms ) {
			return $result + array( 'status' => 'rejected', 'error' => $err ?: 'invalid_updated_at' );
		}

		$existing = self::get( $user_id, $collection, $key );
		if ( ! SyncRules::incoming_wins( $ms, $existing ? (int) $existing['updated_at'] : null ) ) {
			return $result + array( 'status' => 'stale', 'error' => null, 'server_item' => self::format( $existing ) );
		}

		$deleted = 'delete' === $op;
		self::put( $user_id, $collection, $key, $data, $deleted, $ms, 'app' );
		MyVibonoBridge::write_through( $user_id, $collection );
		do_action( 'vibono_api_synced', $user_id, $collection, $key, $data, $deleted );

		return $result + array( 'status' => 'applied', 'error' => null );
	}

	/**
	 * Änderungen seit Cursor.
	 *
	 * @return array{changes: array, cursor: string, has_more: bool, full: bool}
	 */
	public static function pull( int $user_id, ?string $cursor, array $collections, int $limit ): array {
		global $wpdb;
		$t     = Install::table( 'sync' );
		$since = $cursor ? self::decode_cursor( $cursor ) : 0;
		$full  = 0 === $since;
		$limit = max( 1, min( self::MAX_PULL, $limit ) );
		$in    = implode( ',', array_fill( 0, count( $collections ), '%s' ) );

		$sql  = "SELECT * FROM $t WHERE user_id = %d AND seq > %d AND collection IN ($in)";
		$args = array_merge( array( $user_id, $since ), $collections );
		if ( $full ) {
			// Vollabzug ohne Löschmarken.
			$sql .= ' AND deleted = 0';
		}
		$sql .= ' ORDER BY seq ASC LIMIT %d';
		$args[] = $limit + 1;

		$rows     = $wpdb->get_results( $wpdb->prepare( $sql, $args ), ARRAY_A ); // phpcs:ignore
		$has_more = count( $rows ) > $limit;
		$rows     = array_slice( $rows, 0, $limit );
		$last     = $rows ? (int) end( $rows )['seq'] : $since;
		if ( ! $rows && ! $has_more ) {
			$last = max( $since, self::max_seq( $user_id ) );
		}

		return array(
			'cursor'   => self::encode_cursor( $last ),
			'has_more' => $has_more,
			'full'     => $full,
			'changes'  => array_map( array( self::class, 'format' ), $rows ),
		);
	}

	public static function current( int $user_id, string $collection ): array {
		global $wpdb;
		$t    = Install::table( 'sync' );
		$rows = $wpdb->get_results( $wpdb->prepare( "SELECT * FROM $t WHERE user_id = %d AND collection = %s AND deleted = 0 ORDER BY item_key", $user_id, $collection ), ARRAY_A );
		return array_map( array( self::class, 'format' ), $rows );
	}

	/** Schlüssel => Daten aller aktiven Einträge einer Sammlung. */
	public static function current_map( int $user_id, string $collection ): array {
		$out = array();
		foreach ( self::current( $user_id, $collection ) as $item ) {
			$out[ $item['key'] ] = $item['data'];
		}
		return $out;
	}

	public static function max_seq( int $user_id ): int {
		global $wpdb;
		$t = Install::table( 'sync' );
		return (int) $wpdb->get_var( $wpdb->prepare( "SELECT MAX(seq) FROM $t WHERE user_id = %d", $user_id ) );
	}

	public static function format( ?array $row ): ?array {
		if ( ! $row ) {
			return null;
		}
		return array(
			'collection' => $row['collection'],
			'key'        => $row['item_key'],
			'deleted'    => (bool) $row['deleted'],
			'data'       => $row['deleted'] ? null : json_decode( (string) $row['data'], true ),
			'updated_at' => gmdate( 'Y-m-d\TH:i:s', (int) floor( $row['updated_at'] / 1000 ) ) . sprintf( '.%03dZ', $row['updated_at'] % 1000 ),
		);
	}

	public static function encode_cursor( int $seq ): string {
		return 'v1.' . $seq;
	}

	public static function decode_cursor( string $cursor ): int {
		return preg_match( '/^v1\.(\d+)$/', $cursor, $m ) ? (int) $m[1] : 0;
	}
}
