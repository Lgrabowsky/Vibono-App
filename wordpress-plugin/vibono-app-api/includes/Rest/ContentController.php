<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Content;
use Vibono\AppApi\Core\SyncRules;
use Vibono\AppApi\Plugin;

defined( 'ABSPATH' ) || exit;

class ContentController extends Controller {

	public function register(): void {
		$this->route( '/coaching/today', 'GET', array( $this, 'today' ) );
		$this->route( '/content/(?P<type>lessons|recipes|tips|tips-of-the-day)', 'GET', array( $this, 'list' ) );
		$this->route( '/content/item/(?P<id>\d+)', 'GET', array( $this, 'item' ) );
	}

	public function today( \WP_REST_Request $r ) {
		$date = $r['date'] ? (string) $r['date'] : Plugin::today();
		if ( ! SyncRules::is_date( $date ) ) {
			return Plugin::error( 'vibono_invalid_date', 'Datum bitte als JJJJ-MM-TT.', 400 );
		}
		return $this->ok( Content::today( $this->uid(), $date ) );
	}

	public function list( \WP_REST_Request $r ) {
		$kind = Content::TYPES[ (string) $r['type'] ];
		$res  = Content::query( $kind, $this->uid(), $r->get_params() );
		$resp = $this->ok( array_diff_key( $res, array( 'total' => 1, 'total_pages' => 1 ) ) );
		$resp->header( 'X-WP-Total', (string) $res['total'] );
		$resp->header( 'X-WP-TotalPages', (string) $res['total_pages'] );
		return $resp;
	}

	public function item( \WP_REST_Request $r ) {
		$post    = get_post( (int) $r['id'] );
		$allowed = array_map( array( Content::class, 'post_type' ), array_values( Content::TYPES ) );
		if ( ! $post || 'publish' !== $post->post_status || ! in_array( $post->post_type, $allowed, true ) ) {
			return Plugin::error( 'vibono_not_found', 'Inhalt nicht gefunden.', 404 );
		}
		$res = Content::detail( $post, $this->uid() );
		return is_wp_error( $res ) ? $res : $this->ok( $res );
	}
}
