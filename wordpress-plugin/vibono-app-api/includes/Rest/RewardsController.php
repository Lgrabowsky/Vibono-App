<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Plugin;
use Vibono\AppApi\Rewards;

defined( 'ABSPATH' ) || exit;

/**
 * Prämien: Punkte gegen exklusive Inhalte, eBooks/PDFs und Verlängerungsrabatt einlösen.
 * Welche Prämienarten die App je Plattform einlösen darf, steht in GET /config (features.reward_kinds).
 */
class RewardsController extends Controller {

	public function register(): void {
		$this->route( '/rewards', 'GET', array( $this, 'catalog' ) );
		$this->route( '/rewards/(?P<id>\d+)/redeem', 'POST', array( $this, 'redeem' ) );
		$this->route( '/rewards/(?P<id>\d+)/download', 'GET', array( $this, 'download' ) );
		// Öffentlich, abgesichert über das signierte, kurzlebige Token aus /rewards/{id}/download.
		$this->route( '/rewards/file', 'GET', array( $this, 'file' ), false );
	}

	private function channel( \WP_REST_Request $r ): string {
		return in_array( $r['platform'], array( 'ios', 'android', 'web' ), true ) ? (string) $r['platform'] : 'ios';
	}

	private function disabled() {
		return Plugin::error( 'vibono_feature_disabled', 'Prämien sind gerade nicht verfügbar.', 403 );
	}

	public function catalog( \WP_REST_Request $r ) {
		if ( ! Rewards::module_on() ) {
			return $this->disabled();
		}
		return $this->ok( Rewards::catalog( $this->uid(), $this->channel( $r ) ) );
	}

	public function redeem( \WP_REST_Request $r ) {
		if ( ! Rewards::module_on() ) {
			return $this->disabled();
		}
		$limit = $this->throttle( 'reward_redeem', 10, MINUTE_IN_SECONDS );
		if ( is_wp_error( $limit ) ) {
			return $limit;
		}
		$res = Rewards::redeem( $this->uid(), (int) $r['id'], $this->channel( $r ) );
		return is_wp_error( $res ) ? $res : $this->ok( $res );
	}

	public function download( \WP_REST_Request $r ) {
		if ( ! Rewards::module_on() ) {
			return $this->disabled();
		}
		$res = Rewards::download_link( $this->uid(), (int) $r['id'] );
		return is_wp_error( $res ) ? $res : $this->ok( $res );
	}

	public function file( \WP_REST_Request $r ) {
		if ( ! Rewards::module_on() ) {
			return $this->disabled();
		}
		return Rewards::serve_file( (string) $r['t'] );
	}
}
