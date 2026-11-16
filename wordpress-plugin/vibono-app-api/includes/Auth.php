<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\Jwt;

defined( 'ABSPATH' ) || exit;

/**
 * Token-Login für die App: kurzlebiges JWT (Access) + rotierendes Refresh-Token.
 *
 * - Access-Token: 60 min, HS256, Geheimnis in VIBONO_JWT_SECRET (wp-config.php) oder Option.
 * - Refresh-Token: 90 Tage, nur SHA-256-Hash in der DB, wird bei jeder Nutzung ersetzt.
 *   Wird ein bereits ersetztes Token erneut benutzt (Diebstahl-Indiz), wird die ganze Token-Familie widerrufen.
 * - Passwortänderung in WordPress widerruft alle Tokens des Nutzers.
 */
class Auth {

	const ACCESS_TTL  = 3600;
	const REFRESH_TTL = 7776000; // 90 Tage.

	public static function init(): void {
		Plugin::hook( 'determine_current_user', array( self::class, 'determine_user' ), 20 );
		Plugin::hook( 'after_password_reset', array( self::class, 'revoke_user' ) );
		Plugin::hook( 'profile_update', array( self::class, 'on_profile_update' ), 10, 3 );
	}

	/** Bearer-Token nur für Anfragen an unseren Namespace auswerten. */
	public static function determine_user( $user_id ) {
		if ( $user_id ) {
			return $user_id;
		}
		if ( ! self::is_our_rest_request() ) {
			return $user_id;
		}
		$token = self::bearer();
		if ( ! $token ) {
			return $user_id;
		}
		$claims = Jwt::decode( $token, Settings::jwt_secret() );
		if ( ! $claims || ( $claims['typ'] ?? '' ) !== 'access' || ( $claims['iss'] ?? '' ) !== home_url() ) {
			return $user_id;
		}
		$uid = (int) ( $claims['sub'] ?? 0 );
		// Token-Version: steigt bei Passwortänderung/Logout auf allen Geräten.
		if ( (int) get_user_meta( $uid, '_vibono_token_version', true ) !== (int) ( $claims['ver'] ?? 0 ) ) {
			return $user_id;
		}
		return $uid ?: $user_id;
	}

	private static function is_our_rest_request(): bool {
		$uri = $_SERVER['REQUEST_URI'] ?? '';
		$pfx = '/' . rest_get_url_prefix() . '/' . VIBONO_API_NS . '/';
		if ( false !== strpos( $uri, $pfx ) ) {
			return true;
		}
		$route = isset( $_GET['rest_route'] ) ? (string) $_GET['rest_route'] : ''; // phpcs:ignore
		return 0 === strpos( ltrim( $route, '/' ), VIBONO_API_NS . '/' );
	}

	private static function bearer(): ?string {
		$h = $_SERVER['HTTP_AUTHORIZATION'] ?? ( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '' );
		if ( ! $h && function_exists( 'getallheaders' ) ) {
			foreach ( (array) getallheaders() as $k => $v ) {
				if ( strtolower( $k ) === 'authorization' ) {
					$h = $v;
				}
			}
		}
		return preg_match( '/^Bearer\s+(\S+)$/i', trim( (string) $h ), $m ) ? $m[1] : null;
	}

	/** Prüft Login-Daten inkl. Bremse gegen Durchprobieren. */
	public static function check_credentials( string $username, string $password ) {
		$ip       = $_SERVER['REMOTE_ADDR'] ?? '';
		$lock_key = 'vibono_login_' . md5( strtolower( $username ) . '|' . $ip );
		$fails    = (int) get_transient( $lock_key );
		if ( $fails >= 5 ) {
			return Plugin::error( 'vibono_too_many_attempts', 'Zu viele Versuche. Bitte warte 15 Minuten.', 429 );
		}
		$user = wp_authenticate( $username, $password );
		if ( is_wp_error( $user ) ) {
			set_transient( $lock_key, $fails + 1, 15 * MINUTE_IN_SECONDS );
			return Plugin::error( 'vibono_invalid_credentials', 'E-Mail oder Passwort ist falsch.', 401 );
		}
		delete_transient( $lock_key );
		return $user;
	}

	public static function issue( \WP_User $user, string $device = '', ?string $family = null ): array {
		global $wpdb;
		$now    = time();
		$access = Jwt::encode(
			array(
				'iss' => home_url(),
				'sub' => $user->ID,
				'iat' => $now,
				'exp' => $now + self::ACCESS_TTL,
				'typ' => 'access',
				'ver' => (int) get_user_meta( $user->ID, '_vibono_token_version', true ),
			),
			Settings::jwt_secret()
		);
		$refresh = bin2hex( random_bytes( 32 ) );
		$wpdb->insert(
			Install::table( 'tokens' ),
			array(
				'user_id'     => $user->ID,
				'token_hash'  => hash( 'sha256', $refresh ),
				'family'      => $family ?: bin2hex( random_bytes( 16 ) ),
				'device_name' => mb_substr( sanitize_text_field( $device ), 0, 100 ),
				'created_at'  => gmdate( 'Y-m-d H:i:s', $now ),
				'expires_at'  => gmdate( 'Y-m-d H:i:s', $now + self::REFRESH_TTL ),
			)
		);
		return array(
			'access_token'       => $access,
			'token_type'         => 'Bearer',
			'expires_in'         => self::ACCESS_TTL,
			'refresh_token'      => $refresh,
			'refresh_expires_in' => self::REFRESH_TTL,
		);
	}

	/** @return array|\WP_Error */
	public static function refresh( string $refresh ) {
		global $wpdb;
		$t   = Install::table( 'tokens' );
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $t WHERE token_hash = %s", hash( 'sha256', $refresh ) ) );
		if ( ! $row || strtotime( $row->expires_at . ' UTC' ) < time() ) {
			return Plugin::error( 'vibono_invalid_refresh_token', 'Bitte melde dich erneut an.', 401 );
		}
		if ( (int) $row->revoked ) {
			// Wiederverwendung eines ersetzten Tokens: ganze Familie sperren.
			$wpdb->update( $t, array( 'revoked' => 1 ), array( 'family' => $row->family ) );
			return Plugin::error( 'vibono_invalid_refresh_token', 'Bitte melde dich erneut an.', 401 );
		}
		$user = get_user_by( 'id', (int) $row->user_id );
		if ( ! $user ) {
			return Plugin::error( 'vibono_invalid_refresh_token', 'Bitte melde dich erneut an.', 401 );
		}
		$wpdb->update( $t, array( 'revoked' => 1 ), array( 'id' => $row->id ) );
		return array( self::issue( $user, $row->device_name, $row->family ), $user );
	}

	public static function revoke( string $refresh ): void {
		global $wpdb;
		$wpdb->update( Install::table( 'tokens' ), array( 'revoked' => 1 ), array( 'token_hash' => hash( 'sha256', $refresh ) ) );
	}

	public static function revoke_user( $user ): void {
		global $wpdb;
		$uid = is_object( $user ) ? $user->ID : (int) $user;
		$wpdb->update( Install::table( 'tokens' ), array( 'revoked' => 1 ), array( 'user_id' => $uid ) );
		update_user_meta( $uid, '_vibono_token_version', (int) get_user_meta( $uid, '_vibono_token_version', true ) + 1 );
	}

	public static function on_profile_update( $user_id, $old_user, $userdata = array() ): void {
		if ( $old_user && isset( $userdata['user_pass'] ) && $old_user->user_pass !== get_userdata( $user_id )->user_pass ) {
			self::revoke_user( $user_id );
		}
	}

	/** permission_callback für eingeloggte App-Nutzer. */
	public static function require_user() {
		return is_user_logged_in() ? true : Plugin::error( 'vibono_unauthorized', 'Bitte melde dich an.', 401 );
	}
}
