<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Core\SyncRules;
use Vibono\AppApi\Home;
use Vibono\AppApi\Plugin;

defined( 'ABSPATH' ) || exit;

/** Startseite „Heute“: Vorgaben für Rezeptvorschläge, Quiz, Challenges, Meldungen. */
class HomeController extends Controller {

	public function register(): void {
		$this->route( '/home', 'GET', array( $this, 'get' ) );
	}

	public function get( \WP_REST_Request $r ) {
		$date = $r['date'] ? (string) $r['date'] : Plugin::today();
		if ( ! SyncRules::is_date( $date ) ) {
			return Plugin::error( 'vibono_invalid_date', 'Datum bitte als JJJJ-MM-TT.', 400 );
		}
		$platform = in_array( $r['platform'], array( 'ios', 'android', 'web' ), true ) ? (string) $r['platform'] : 'ios';
		return $this->ok( Home::feed( $this->uid(), $date, $platform ) );
	}
}
