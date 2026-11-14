<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Reading;

defined( 'ABSPATH' ) || exit;

class ReadingController extends Controller {

	public function register(): void {
		$this->route( '/reading/start', 'POST', array( $this, 'start' ) );
		$this->route( '/reading/heartbeat', 'POST', array( $this, 'heartbeat' ) );
		$this->route( '/reading/complete', 'POST', array( $this, 'complete' ) );
	}

	public function start( \WP_REST_Request $r ) {
		$limit = $this->throttle( 'reading_start', 60, HOUR_IN_SECONDS );
		if ( is_wp_error( $limit ) ) {
			return $limit;
		}
		$res = Reading::start( $this->uid(), (int) $r['post_id'], 'web' === $r['channel'] ? 'web' : 'app' );
		return is_wp_error( $res ) ? $res : $this->ok( $res );
	}

	public function heartbeat( \WP_REST_Request $r ) {
		$res = Reading::heartbeat( $this->uid(), (string) $r['session_id'], (int) $r['active_seconds'], (float) $r['scroll_depth'] );
		return is_wp_error( $res ) ? $res : $this->ok( $res );
	}

	public function complete( \WP_REST_Request $r ) {
		$answer = null === $r['quiz_answer'] ? null : (int) $r['quiz_answer'];
		$res    = Reading::complete( $this->uid(), (string) $r['session_id'], $answer );
		return is_wp_error( $res ) ? $res : $this->ok( $res );
	}
}
