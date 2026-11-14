<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Übergang App → Browser: Einmal-Link, mit dem Nutzer*innen eingeloggt auf vibono.de landen
 * (z. B. um Punkte im Shop einzulösen), ohne das Passwort erneut einzugeben.
 *
 * - Token 2 Minuten gültig, nur einmal nutzbar, nur der Hash wird gespeichert.
 * - Weiterleitung nur auf Pfade dieser Website.
 * - Ist im Browser bereits ein anderes Konto eingeloggt, wird nichts geändert.
 * - Für Administratoren deaktiviert.
 */
class WebSession {

	const PARAM = 'vibono_login';
	const TTL   = 120;

	public static function init(): void {
		add_action( 'init', array( self::class, 'consume' ), 1 );
	}

	public static function create( int $user_id, string $redirect ): array {
		$token = bin2hex( random_bytes( 24 ) );
		$path  = '/' . ltrim( wp_parse_url( $redirect, PHP_URL_PATH ) ?: '/', '/' );
		$query = wp_parse_url( $redirect, PHP_URL_QUERY );
		set_transient(
			'vibono_ws_' . hash( 'sha256', $token ),
			array( 'user_id' => $user_id, 'redirect' => $path . ( $query ? '?' . $query : '' ) ),
			self::TTL
		);
		return array(
			'url'        => add_query_arg( self::PARAM, $token, home_url( '/' ) ),
			'expires_at' => Plugin::iso( time() + self::TTL ),
		);
	}

	public static function consume(): void {
		if ( empty( $_GET[ self::PARAM ] ) ) { // phpcs:ignore
			return;
		}
		$token = sanitize_key( wp_unslash( $_GET[ self::PARAM ] ) ); // phpcs:ignore
		$key   = 'vibono_ws_' . hash( 'sha256', $token );
		$data  = get_transient( $key );
		delete_transient( $key );
		$target = home_url( '/' );
		if ( is_array( $data ) ) {
			$target  = home_url( $data['redirect'] );
			$user_id = (int) $data['user_id'];
			$current = get_current_user_id();
			if ( ! $current && ! user_can( $user_id, 'manage_options' ) ) {
				wp_set_current_user( $user_id );
				wp_set_auth_cookie( $user_id, true, is_ssl() );
				do_action( 'wp_login', get_userdata( $user_id )->user_login, get_userdata( $user_id ) );
			}
		}
		wp_safe_redirect( $target );
		exit;
	}
}
