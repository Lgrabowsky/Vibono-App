<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Plugin;
use Vibono\AppApi\Points;
use Vibono\AppApi\Referral;
use Vibono\AppApi\Settings;

defined( 'ABSPATH' ) || exit;

class ReferralController extends Controller {

	public function register(): void {
		$this->route( '/referral', 'GET', array( $this, 'info' ) );
		$this->route( '/referral/validate', 'GET', array( $this, 'validate' ), false );
	}

	/** Modul "Freunde werben" aus: Funktion in der App ausblenden (GET /config → features.referral). */
	public static function enabled(): bool {
		return Settings::on( 'module_referral' ) && (bool) Settings::get( 'points_enabled' );
	}

	private function disabled() {
		return Plugin::error( 'vibono_feature_disabled', 'Freunde werben ist gerade nicht verfügbar.', 403 );
	}

	public function info() {
		if ( ! self::enabled() ) {
			return $this->disabled();
		}
		return $this->ok( Referral::info( $this->uid() ) );
	}

	public function validate( \WP_REST_Request $r ) {
		if ( ! self::enabled() ) {
			return $this->disabled();
		}
		$limit = $this->throttle( 'ref_validate', 30, HOUR_IN_SECONDS );
		if ( is_wp_error( $limit ) ) {
			return $limit;
		}
		$uid  = Referral::user_by_code( (string) $r['code'] );
		$user = $uid ? get_userdata( $uid ) : null;
		return $this->ok(
			array(
				'valid'               => (bool) $user,
				'referrer_first_name' => $user && $user->first_name ? $user->first_name : null,
				'friend_bonus_points' => $user ? Points::summary( $uid )['earn_rules']['referral_friend'] : 0,
			)
		);
	}
}
