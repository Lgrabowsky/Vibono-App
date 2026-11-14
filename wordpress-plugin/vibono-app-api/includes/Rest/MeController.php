<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Install;
use Vibono\AppApi\Plugin;
use Vibono\AppApi\Profile;

defined( 'ABSPATH' ) || exit;

class MeController extends Controller {

	public function register(): void {
		$this->route( '/me', 'GET', array( $this, 'get' ) );
		$this->route( '/me', 'DELETE', array( $this, 'delete' ) );
		$this->route( '/me/profile', 'PUT', array( $this, 'update' ) );
		$this->route( '/me/devices', 'POST', array( $this, 'add_device' ) );
		$this->route( '/me/devices', 'DELETE', array( $this, 'remove_device' ) );
	}

	public function get() {
		return $this->ok( Profile::me( $this->uid() ) );
	}

	public function update( \WP_REST_Request $r ) {
		$res = Profile::update( $this->uid(), (array) $r->get_json_params() );
		return is_wp_error( $res ) ? $res : $this->ok( Profile::me( $this->uid() ) );
	}

	/**
	 * Konto-Löschung beantragen (Pflicht für Apps mit Konto-Erstellung im App Store).
	 * Nutzt den WordPress-Datenschutz-Workflow (Werkzeuge → Personenbezogene Daten löschen).
	 */
	public function delete() {
		$user       = get_userdata( $this->uid() );
		$request_id = wp_create_user_request( $user->user_email, 'remove_personal_data', array(), 'confirmed' );
		if ( is_wp_error( $request_id ) && 'duplicate_request' !== $request_id->get_error_code() ) {
			return Plugin::error( 'vibono_delete_failed', 'Die Löschung konnte nicht beantragt werden. Bitte kontaktiere uns.', 500 );
		}
		update_user_meta( $user->ID, '_vibono_deletion_requested', gmdate( 'c' ) );
		do_action( 'vibono_api_account_deletion_requested', $user->ID );
		return $this->ok( array( 'ok' => true ), 202 );
	}

	public function add_device( \WP_REST_Request $r ) {
		global $wpdb;
		$token    = sanitize_text_field( (string) $r['token'] );
		$platform = in_array( $r['platform'], array( 'ios', 'android' ), true ) ? $r['platform'] : '';
		if ( ! $token || ! $platform ) {
			return Plugin::error( 'vibono_invalid_device', 'Token und Plattform sind nötig.', 400 );
		}
		$t = Install::table( 'devices' );
		$wpdb->query(
			$wpdb->prepare(
				"INSERT INTO $t (user_id, token, platform, app_version, locale, updated_at) VALUES (%d, %s, %s, %s, %s, %s)
				 ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), app_version = VALUES(app_version), locale = VALUES(locale), updated_at = VALUES(updated_at)",
				$this->uid(),
				$token,
				$platform,
				substr( sanitize_text_field( (string) $r['app_version'] ), 0, 20 ),
				substr( sanitize_text_field( (string) $r['locale'] ), 0, 10 ),
				gmdate( 'Y-m-d H:i:s' )
			)
		);
		return $this->ok( array( 'ok' => true ) );
	}

	public function remove_device( \WP_REST_Request $r ) {
		global $wpdb;
		$wpdb->delete( Install::table( 'devices' ), array( 'user_id' => $this->uid(), 'token' => (string) $r['token'] ) );
		return $this->ok( array( 'ok' => true ) );
	}
}
