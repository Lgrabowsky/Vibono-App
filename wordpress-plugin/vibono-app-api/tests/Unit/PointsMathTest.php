<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\PointsMath;

final class PointsMathTest extends TestCase {
	private function c( array $o ): array {
		return array_merge( array( 'id' => 1, 'kind' => 'earn', 'reasons' => array(), 'multiplier' => 2.0, 'starts_at' => 100, 'ends_at' => 200, 'enabled' => true ), $o );
	}

	public function test_no_campaign_means_base(): void {
		$r = PointsMath::earn( 500, array(), 150, 'referral' );
		$this->assertSame( 500, $r['points'] );
		$this->assertSame( 1.0, $r['multiplier'] );
	}

	public function test_double_referral_points_in_window_only(): void {
		$cs = array( $this->c( array( 'reasons' => array( 'referral' ) ) ) );
		$this->assertSame( 1000, PointsMath::earn( 500, $cs, 150, 'referral' )['points'] );
		$this->assertSame( 500, PointsMath::earn( 500, $cs, 200, 'referral' )['points'], 'Ende exklusiv' );
		$this->assertSame( 500, PointsMath::earn( 500, $cs, 99, 'referral' )['points'] );
		$this->assertSame( 10, PointsMath::earn( 10, $cs, 150, 'article_read' )['points'], 'gilt nur für referral' );
	}

	public function test_campaigns_do_not_stack(): void {
		$cs = array( $this->c( array( 'id' => 1, 'multiplier' => 2.0 ) ), $this->c( array( 'id' => 2, 'multiplier' => 3.0 ) ) );
		$r  = PointsMath::earn( 10, $cs, 150, 'app_open' );
		$this->assertSame( 30, $r['points'] );
		$this->assertSame( 2, $r['campaign']['id'] );
	}

	public function test_disabled_campaign_ignored(): void {
		$cs = array( $this->c( array( 'enabled' => false ) ) );
		$this->assertSame( 10, PointsMath::earn( 10, $cs, 150, 'app_open' )['points'] );
	}

	public function test_redeem_campaign_doubles_point_value(): void {
		$cs = array( $this->c( array( 'kind' => 'redeem' ) ) );
		$this->assertSame( 2.0, PointsMath::effective_cents_per_point( 1.0, $cs, 150 ) );
		$this->assertSame( 1.0, PointsMath::effective_cents_per_point( 1.0, $cs, 250 ) );
		// Verdien-Aktion beeinflusst den Einlösewert nicht.
		$this->assertSame( 1.0, PointsMath::effective_cents_per_point( 1.0, array( $this->c( array() ) ), 150 ) );
	}

	public function test_purchase_points(): void {
		$this->assertSame( 249, PointsMath::purchase_points( 4999, 5 ) );
		$this->assertSame( 0, PointsMath::purchase_points( -100, 5 ) );
	}

	public function test_redeemable_caps_at_percent_and_balance(): void {
		// 40 € Warenkorb, max 50 % = 20 € = 2000 Punkte bei 1 ct.
		$r = PointsMath::redeemable( 5000, 3000, 4000, 1.0, 50, 100 );
		$this->assertSame( 2000, $r['points'] );
		$this->assertSame( 2000, $r['cents'] );
		// Guthaben begrenzt.
		$this->assertSame( 800, PointsMath::redeemable( 5000, 800, 4000, 1.0, 50, 100 )['points'] );
	}

	public function test_redeemable_with_double_value(): void {
		// Punkte doppelt wert: 1000 Punkte = 20 €; Deckel 20 € → max 1000 Punkte.
		$r = PointsMath::redeemable( 3000, 3000, 4000, 2.0, 50, 100 );
		$this->assertSame( 1000, $r['points'] );
		$this->assertSame( 2000, $r['cents'] );
	}

	public function test_redeemable_minimum(): void {
		$this->assertSame( 'below_minimum', PointsMath::redeemable( 50, 3000, 4000, 1.0, 50, 100 )['error'] );
		$this->assertSame( 'cart_too_small', PointsMath::redeemable( 500, 3000, 150, 1.0, 50, 100 )['error'] );
	}
}
