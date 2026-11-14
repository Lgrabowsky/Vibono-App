<?php
namespace Vibono\AppApi\Core;

/**
 * Minimaler JWT (HS256) ohne Abhängigkeiten. Reine Logik, ohne WordPress testbar.
 */
class Jwt {

	public static function encode( array $claims, string $secret ): string {
		$header = array( 'alg' => 'HS256', 'typ' => 'JWT' );
		$h      = self::b64( json_encode( $header ) );
		$p      = self::b64( json_encode( $claims ) );
		$sig    = self::b64( hash_hmac( 'sha256', "$h.$p", $secret, true ) );
		return "$h.$p.$sig";
	}

	/**
	 * @return array|null Claims oder null, wenn ungültig/abgelaufen.
	 */
	public static function decode( string $jwt, string $secret, ?int $now = null, int $leeway = 30 ): ?array {
		$parts = explode( '.', $jwt );
		if ( count( $parts ) !== 3 ) {
			return null;
		}
		list( $h, $p, $s ) = $parts;
		$header = json_decode( self::unb64( $h ), true );
		if ( ! is_array( $header ) || ( $header['alg'] ?? '' ) !== 'HS256' ) {
			return null;
		}
		$expected = self::b64( hash_hmac( 'sha256', "$h.$p", $secret, true ) );
		if ( ! hash_equals( $expected, $s ) ) {
			return null;
		}
		$claims = json_decode( self::unb64( $p ), true );
		if ( ! is_array( $claims ) ) {
			return null;
		}
		$now = $now ?? time();
		if ( isset( $claims['exp'] ) && $now > (int) $claims['exp'] + $leeway ) {
			return null;
		}
		if ( isset( $claims['nbf'] ) && $now + $leeway < (int) $claims['nbf'] ) {
			return null;
		}
		return $claims;
	}

	private static function b64( string $data ): string {
		return rtrim( strtr( base64_encode( $data ), '+/', '-_' ), '=' );
	}

	private static function unb64( string $data ): string {
		$pad = strlen( $data ) % 4;
		if ( $pad ) {
			$data .= str_repeat( '=', 4 - $pad );
		}
		return (string) base64_decode( strtr( $data, '-_', '+/' ), true );
	}
}
