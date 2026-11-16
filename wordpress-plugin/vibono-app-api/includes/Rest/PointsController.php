<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Campaigns;
use Vibono\AppApi\Points;

defined( 'ABSPATH' ) || exit;

class PointsController extends Controller {

	public function register(): void {
		$this->route( '/points', 'GET', array( $this, 'summary' ) );
		$this->route( '/points/ledger', 'GET', array( $this, 'ledger' ) );
		$this->route( '/points/app-open', 'POST', array( $this, 'app_open' ) );
		$this->route( '/points/campaigns', 'GET', array( $this, 'campaigns' ), false );
	}

	public function summary() {
		return $this->ok( Points::summary( $this->uid() ) );
	}

	public function ledger( \WP_REST_Request $r ) {
		$page = max( 1, (int) ( $r['page'] ?: 1 ) );
		$per  = max( 1, min( 100, (int) ( $r['per_page'] ?: 30 ) ) );
		return $this->ok( Points::ledger( $this->uid(), $page, $per ) );
	}

	public function app_open() {
		return $this->ok( Points::app_open( $this->uid() ) );
	}

	public function campaigns() {
		$r = new \WP_REST_Response( array_map( array( Campaigns::class, 'format' ), Campaigns::visible() ) );
		$r->header( 'Cache-Control', 'public, max-age=300' );
		return $r;
	}
}
