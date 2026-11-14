<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\Jwt;

final class JwtTest extends TestCase {
	public function test_roundtrip(): void {
		$t = Jwt::encode( array( 'sub' => 7, 'exp' => 2000 ), 'geheim' );
		$this->assertSame( 7, Jwt::decode( $t, 'geheim', 1000 )['sub'] );
	}

	public function test_wrong_secret_rejected(): void {
		$t = Jwt::encode( array( 'sub' => 7 ), 'geheim' );
		$this->assertNull( Jwt::decode( $t, 'anders' ) );
	}

	public function test_expired_rejected_with_leeway(): void {
		$t = Jwt::encode( array( 'sub' => 7, 'exp' => 1000 ), 's' );
		$this->assertNotNull( Jwt::decode( $t, 's', 1020 ) );
		$this->assertNull( Jwt::decode( $t, 's', 1031 ) );
	}

	public function test_tampered_payload_rejected(): void {
		$t     = Jwt::encode( array( 'sub' => 7 ), 's' );
		$parts = explode( '.', $t );
		$parts[1] = rtrim( strtr( base64_encode( json_encode( array( 'sub' => 1 ) ) ), '+/', '-_' ), '=' );
		$this->assertNull( Jwt::decode( implode( '.', $parts ), 's' ) );
	}

	public function test_alg_none_rejected(): void {
		$h = rtrim( strtr( base64_encode( '{"alg":"none","typ":"JWT"}' ), '+/', '-_' ), '=' );
		$p = rtrim( strtr( base64_encode( '{"sub":1}' ), '+/', '-_' ), '=' );
		$this->assertNull( Jwt::decode( "$h.$p.", 's' ) );
	}
}
