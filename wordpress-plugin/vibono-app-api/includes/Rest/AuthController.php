<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Auth;
use Vibono\AppApi\Plugin;
use Vibono\AppApi\Profile;
use Vibono\AppApi\Referral;
use Vibono\AppApi\WebSession;

defined( 'ABSPATH' ) || exit;

class AuthController extends Controller {

	public function register(): void {
		$this->route( '/auth/login', 'POST', array( $this, 'login' ), false );
		$this->route( '/auth/register', 'POST', array( $this, 'register_user' ), false );
		$this->route( '/auth/refresh', 'POST', array( $this, 'refresh' ), false );
		$this->route( '/auth/logout', 'POST', array( $this, 'logout' ) );
		$this->route( '/auth/password-reset', 'POST', array( $this, 'password_reset' ), false );
		$this->route( '/auth/web-session', 'POST', array( $this, 'web_session' ) );
	}

	public function login( \WP_REST_Request $r ) {
		$user = Auth::check_credentials( (string) $r['username'], (string) $r['password'] );
		if ( is_wp_error( $user ) ) {
			return $user;
		}
		wp_set_current_user( $user->ID );
		do_action( 'vibono_api_login', $user->ID );
		return $this->ok( Auth::issue( $user, (string) $r['device_name'] ) + array( 'user' => Profile::me( $user->ID ) ) );
	}

	public function register_user( \WP_REST_Request $r ) {
		$limit = $this->throttle( 'register', 5, HOUR_IN_SECONDS );
		if ( is_wp_error( $limit ) ) {
			return $limit;
		}
		$email = sanitize_email( (string) $r['email'] );
		$pass  = (string) $r['password'];
		if ( ! is_email( $email ) ) {
			return Plugin::error( 'vibono_invalid_email', 'Bitte gib eine gültige E-Mail-Adresse ein.', 400 );
		}
		if ( strlen( $pass ) < 8 ) {
			return Plugin::error( 'vibono_weak_password', 'Dein Passwort braucht mindestens 8 Zeichen.', 400 );
		}
		if ( true !== $r['accept_privacy'] ) {
			return Plugin::error( 'vibono_privacy_required', 'Bitte stimme der Datenschutzerklärung zu.', 400 );
		}
		if ( email_exists( $email ) ) {
			return Plugin::error( 'vibono_email_exists', 'Zu dieser E-Mail gibt es schon ein Vibono-Konto. Melde dich einfach an.', 409 );
		}
		$first = sanitize_text_field( (string) $r['first_name'] );
		if ( function_exists( 'wc_create_new_customer' ) ) {
			$uid = wc_create_new_customer( $email, '', $pass, array( 'first_name' => $first ) );
		} else {
			$uid = wp_insert_user(
				array(
					'user_login' => $email,
					'user_email' => $email,
					'user_pass'  => $pass,
					'first_name' => $first,
					'role'       => get_option( 'default_role', 'subscriber' ),
				)
			);
		}
		if ( is_wp_error( $uid ) ) {
			return Plugin::error( 'vibono_register_failed', $uid->get_error_message(), 400 );
		}
		update_user_meta( $uid, '_vibono_privacy_consent', array( 'at' => gmdate( 'c' ), 'channel' => 'app', 'health_data' => true ) );
		if ( $r['referral_code'] && ReferralController::enabled() ) {
			Referral::attach( (int) $uid, Referral::user_by_code( (string) $r['referral_code'] ) );
		}
		$user = get_userdata( $uid );
		wp_set_current_user( $uid );
		return $this->ok( Auth::issue( $user, (string) $r['device_name'] ) + array( 'user' => Profile::me( $uid ) ), 201 );
	}

	public function refresh( \WP_REST_Request $r ) {
		$res = Auth::refresh( (string) $r['refresh_token'] );
		if ( is_wp_error( $res ) ) {
			return $res;
		}
		list( $tokens, $user ) = $res;
		wp_set_current_user( $user->ID );
		return $this->ok( $tokens + array( 'user' => Profile::me( $user->ID ) ) );
	}

	public function logout( \WP_REST_Request $r ) {
		if ( $r['all_devices'] ) {
			Auth::revoke_user( $this->uid() );
		} elseif ( $r['refresh_token'] ) {
			Auth::revoke( (string) $r['refresh_token'] );
		}
		return $this->ok( array( 'ok' => true ) );
	}

	public function password_reset( \WP_REST_Request $r ) {
		$limit = $this->throttle( 'pwreset', 5, HOUR_IN_SECONDS );
		if ( is_wp_error( $limit ) ) {
			return $limit;
		}
		$user = get_user_by( 'email', sanitize_email( (string) $r['email'] ) );
		if ( $user ) {
			retrieve_password( $user->user_login );
		}
		return $this->ok( array( 'ok' => true ) );
	}

	public function web_session( \WP_REST_Request $r ) {
		return $this->ok( WebSession::create( $this->uid(), (string) ( $r['redirect'] ?: '/' ) ) );
	}
}
