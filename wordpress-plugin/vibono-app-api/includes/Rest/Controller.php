<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Auth;

defined( 'ABSPATH' ) || exit;

abstract class Controller {

	abstract public function register(): void;

	protected function route( string $path, string $methods, callable $cb, bool $auth = true, array $args = array() ): void {
		register_rest_route(
			VIBONO_API_NS,
			$path,
			array(
				'methods'             => $methods,
				'callback'            => $cb,
				'permission_callback' => $auth ? array( Auth::class, 'require_user' ) : '__return_true',
				'args'                => $args,
			)
		);
	}

	protected function uid(): int {
		return get_current_user_id();
	}

	/** Antwort ohne Caching (personenbezogene Daten). */
	protected function ok( $data, int $status = 200 ): \WP_REST_Response {
		$r = new \WP_REST_Response( $data, $status );
		$r->header( 'Cache-Control', 'no-store, private' );
		return $r;
	}

	/** Einfache Ratenbegrenzung je Nutzer/IP. */
	protected function throttle( string $bucket, int $max, int $window ) {
		$who = get_current_user_id() ?: ( $_SERVER['REMOTE_ADDR'] ?? 'x' );
		$key = 'vibono_rl_' . md5( $bucket . '|' . $who );
		$n   = (int) get_transient( $key );
		if ( $n >= $max ) {
			return new \WP_Error( 'vibono_rate_limited', 'Zu viele Anfragen. Bitte versuche es später noch einmal.', array( 'status' => 429 ) );
		}
		set_transient( $key, $n + 1, $window );
		return true;
	}
}
