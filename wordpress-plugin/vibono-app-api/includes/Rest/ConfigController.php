<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Settings;

defined( 'ABSPATH' ) || exit;

class ConfigController extends Controller {

	public function register(): void {
		$this->route( '/config', 'GET', array( $this, 'get' ), false );
	}

	public function get( \WP_REST_Request $r ) {
		$platform = in_array( $r['platform'], array( 'ios', 'android', 'web' ), true ) ? $r['platform'] : 'ios';
		$links    = 'web' === $platform
			? array( 'physical_products' => true, 'memberships' => true, 'points_redemption' => true )
			: array_map( 'boolval', (array) Settings::get( 'shop_links_' . $platform ) );
		$shop     = Settings::on( 'module_shop' ) && (bool) Settings::get( 'points_enabled' );
		// Ohne Modul "Punkte im Shop" gibt es im Shop nichts einzulösen.
		$links['points_redemption'] = ! empty( $links['points_redemption'] ) && $shop;
		$any      = in_array( true, $links, true );
		$resp     = new \WP_REST_Response(
			array(
				'api_version'     => VIBONO_API_VERSION,
				'min_app_version' => (string) Settings::get( 'min_app_version' ),
				'shop_links'      => array(
					'physical_products' => ! empty( $links['physical_products'] ),
					'memberships'       => ! empty( $links['memberships'] ),
					'points_redemption' => ! empty( $links['points_redemption'] ),
				),
				'shop_url'        => $any ? (string) Settings::get( 'shop_url' ) : null,
				'points_enabled'  => (bool) Settings::get( 'points_enabled' ),
				'cents_per_point' => (float) Settings::get( 'cents_per_point' ),
				'features'        => array(
					'referral'    => ReferralController::enabled(),
					'shop_points' => $shop,
					'web_reading' => Settings::on( 'module_web_reading' ) && (bool) Settings::get( 'points_enabled' ),
				),
				'support_url'     => (string) Settings::get( 'support_url' ),
				'privacy_url'     => (string) Settings::get( 'privacy_url' ),
			)
		);
		$resp->header( 'Cache-Control', 'public, max-age=300' );
		return $resp;
	}
}
