<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\RewardRules;

final class RewardRulesTest extends TestCase {

	private function reward( array $o = array() ): array {
		return array_merge( array( 'id' => 1, 'kind' => 'content', 'cost_points' => 300, 'per_user_limit' => 1, 'enabled' => true ), $o );
	}

	public function test_normalize_content_needs_post(): void {
		list( $r, $err ) = RewardRules::normalize( array( 'kind' => 'content', 'title' => 'Rezept', 'cost_points' => 300 ) );
		$this->assertNull( $r );
		$this->assertNotNull( $err );
		list( $r, $err ) = RewardRules::normalize( array( 'kind' => 'content', 'title' => 'Rezept', 'cost_points' => 300, 'post_id' => 12, 'enabled' => '1' ) );
		$this->assertNull( $err );
		$this->assertSame( 12, $r['post_id'] );
		$this->assertSame( 1, $r['per_user_limit'], 'Inhalte gibt es einmal' );
		$this->assertTrue( $r['enabled'] );
	}

	public function test_normalize_rejects_unknown_kind_and_zero_cost(): void {
		$this->assertNotNull( RewardRules::normalize( array( 'kind' => 'cash', 'title' => 'x', 'cost_points' => 1 ) )[1] );
		$this->assertNotNull( RewardRules::normalize( array( 'kind' => 'download', 'title' => 'x', 'cost_points' => 0, 'attachment_id' => 3 ) )[1] );
		$this->assertNotNull( RewardRules::normalize( array( 'kind' => 'download', 'title' => '  ', 'cost_points' => 5, 'attachment_id' => 3 ) )[1] );
	}

	public function test_normalize_renewal_discount(): void {
		list( $r, $err ) = RewardRules::normalize(
			array( 'kind' => 'renewal_discount', 'title' => '10 € auf die Verlängerung', 'cost_points' => 1000, 'discount_amount' => '10,50', 'product_ids' => '12, 13 x 12', 'valid_days' => 0, 'per_user_limit' => 2 )
		);
		$this->assertNull( $err );
		$this->assertSame( 10.5, $r['discount_amount'] );
		$this->assertSame( 'fixed', $r['discount_type'] );
		$this->assertSame( array( 12, 13 ), $r['product_ids'] );
		$this->assertSame( 1, $r['valid_days'], 'mindestens 1 Tag' );
		$this->assertSame( 2, $r['per_user_limit'] );
		$this->assertNotNull( RewardRules::normalize( array( 'kind' => 'renewal_discount', 'title' => 'x', 'cost_points' => 5, 'discount_type' => 'percent', 'discount_amount' => 120 ) )[1] );
	}

	public function test_check_order_of_reasons(): void {
		$r = $this->reward();
		$this->assertNull( RewardRules::check( $r, 300, 0, true ) );
		$this->assertSame( 'insufficient_points', RewardRules::check( $r, 299, 0, true ) );
		$this->assertSame( 'already_unlocked', RewardRules::check( $r, 5000, 1, true ) );
		$this->assertSame( 'not_available_here', RewardRules::check( $r, 5000, 0, false ) );
		$this->assertSame( 'disabled', RewardRules::check( $this->reward( array( 'enabled' => false ) ), 5000, 0, true ) );
	}

	public function test_renewal_limit(): void {
		$r = $this->reward( array( 'kind' => 'renewal_discount', 'per_user_limit' => 2 ) );
		$this->assertNull( RewardRules::check( $r, 5000, 1, true ) );
		$this->assertSame( 'limit_reached', RewardRules::check( $r, 5000, 2, true ) );
		$this->assertNull( RewardRules::check( $this->reward( array( 'kind' => 'renewal_discount', 'per_user_limit' => 0 ) ), 5000, 9, true ), '0 = beliebig oft' );
	}

	public function test_discount_label(): void {
		$this->assertSame( '10 € Rabatt', RewardRules::discount_label( 'fixed', 10.0 ) );
		$this->assertSame( '7,50 € Rabatt', RewardRules::discount_label( 'fixed', 7.5 ) );
		$this->assertSame( '15 % Rabatt', RewardRules::discount_label( 'percent', 15.0 ) );
	}

	public function test_coupon_code_format(): void {
		$code = RewardRules::coupon_code( random_bytes( 8 ) );
		$this->assertMatchesRegularExpression( '/^VP-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/', $code );
	}

	public function test_download_token_roundtrip_and_tamper(): void {
		$t = RewardRules::download_token( 42, 7, 2000, 'geheim' );
		$this->assertSame( array( 'user_id' => 42, 'reward_id' => 7, 'expires' => 2000 ), RewardRules::verify_download_token( $t, 'geheim', 1999 ) );
		$this->assertNull( RewardRules::verify_download_token( $t, 'geheim', 2001 ), 'abgelaufen' );
		$this->assertNull( RewardRules::verify_download_token( $t, 'anders', 1000 ), 'falscher Schlüssel' );
		$this->assertNull( RewardRules::verify_download_token( str_replace( '42.7.', '43.7.', $t ), 'geheim', 1000 ), 'andere Person' );
		$this->assertNull( RewardRules::verify_download_token( 'kaputt', 'geheim', 1000 ) );
	}
}
