<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Core\SyncRules;
use Vibono\AppApi\MyVibonoBridge;
use Vibono\AppApi\Plugin;
use Vibono\AppApi\SyncStore;

defined( 'ABSPATH' ) || exit;

class SyncController extends Controller {

	const MAX_PUSH = 500;

	public function register(): void {
		$this->route( '/sync', 'GET', array( $this, 'pull' ) );
		$this->route( '/sync', 'POST', array( $this, 'push' ) );
		$this->route( '/me/(?P<collection>favorites|lessons-done|courses-done|weight|sport|weekplan)', 'GET', array( $this, 'get_collection' ) );
		$this->route( '/me/(?P<collection>favorites|lessons-done|courses-done|weight|sport|weekplan)', 'PUT', array( $this, 'put_collection' ) );
	}

	private function collections( $param ): array {
		if ( ! $param ) {
			return SyncRules::COLLECTIONS;
		}
		$list = array_intersect( array_map( 'trim', explode( ',', (string) $param ) ), SyncRules::COLLECTIONS );
		return $list ? array_values( $list ) : SyncRules::COLLECTIONS;
	}

	public function pull( \WP_REST_Request $r ) {
		$uid         = $this->uid();
		$collections = $this->collections( $r['collections'] );
		$cursor      = $r['cursor'] ? (string) $r['cursor'] : null;
		if ( $cursor && ! preg_match( '/^v1\.\d+$/', $cursor ) ) {
			return Plugin::error( 'vibono_cursor_expired', 'Bitte ohne Cursor neu laden.', 410 );
		}
		MyVibonoBridge::reconcile( $uid, $collections );
		return $this->ok( SyncStore::pull( $uid, $cursor, $collections, (int) ( $r['limit'] ?: 500 ) ) );
	}

	public function push( \WP_REST_Request $r ) {
		$changes = (array) $r['changes'];
		if ( count( $changes ) > self::MAX_PUSH ) {
			return Plugin::error( 'vibono_too_many_changes', 'Maximal ' . self::MAX_PUSH . ' Änderungen pro Aufruf.', 413 );
		}
		$uid = $this->uid();
		// Website-Stand zuerst übernehmen, damit Last-Write-Wins fair vergleicht.
		MyVibonoBridge::reconcile( $uid, array_values( array_unique( array_filter( array_column( $changes, 'collection' ), 'is_string' ) ) ) );
		$now     = Plugin::now_ms();
		$results = array();
		foreach ( $changes as $c ) {
			$results[] = SyncStore::apply( $uid, is_array( $c ) ? $c : array(), $now );
		}
		return $this->ok( array( 'results' => $results, 'cursor' => SyncStore::encode_cursor( SyncStore::max_seq( $uid ) ) ) );
	}

	public function get_collection( \WP_REST_Request $r ) {
		$uid        = $this->uid();
		$collection = SyncRules::collection_from_path( (string) $r['collection'] );
		MyVibonoBridge::reconcile( $uid, array( $collection ) );
		return $this->ok(
			array(
				'items'  => SyncStore::current( $uid, $collection ),
				'cursor' => SyncStore::encode_cursor( SyncStore::max_seq( $uid ) ),
			)
		);
	}

	public function put_collection( \WP_REST_Request $r ) {
		$collection = SyncRules::collection_from_path( (string) $r['collection'] );
		$changes    = array_map(
			static fn( $c ) => array_merge( is_array( $c ) ? $c : array(), array( 'collection' => $collection ) ),
			(array) $r['changes']
		);
		$r->set_param( 'changes', $changes );
		return $this->push( $r );
	}
}
