<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\StreakMath;

final class StreakMathTest extends TestCase {

	private function levels(): array {
		return StreakMath::levels(
			5,
			array(
				array( 'from_day' => 30, 'points' => 12 ),
				array( 'from_day' => 3, 'points' => 6 ),
				array( 'from_day' => 7, 'points' => 8 ),
				array( 'from_day' => 14, 'points' => 10 ),
			)
		);
	}

	private function state( int $days, string $last, ?string $grace_month = null, int $used = 0 ): array {
		return array( 'days' => $days, 'best' => $days, 'last_date' => $last, 'grace_month' => $grace_month, 'grace_used' => $used );
	}

	public function test_levels_are_sorted_and_start_at_day_one(): void {
		$l = $this->levels();
		$this->assertSame( array( 1, 3, 7, 14, 30 ), array_column( $l, 'from_day' ) );
		$this->assertSame( array( 5, 6, 8, 10, 12 ), array_column( $l, 'points' ) );
		// Tag 1 und Unsinn werden ignoriert, doppelte Tage: letzter Wert gilt.
		$l = StreakMath::levels( 5, array( array( 'from_day' => 1, 'points' => 99 ), array( 'from_day' => 0, 'points' => 3 ), array( 'from_day' => 4, 'points' => 7 ), array( 'from_day' => 4, 'points' => 9 ) ) );
		$this->assertSame( array( array( 'from_day' => 1, 'points' => 5 ), array( 'from_day' => 4, 'points' => 9 ) ), $l );
	}

	public function test_stage_and_next_stage(): void {
		$l = $this->levels();
		$this->assertSame( 5, StreakMath::stage( 1, $l )['points'] );
		$this->assertSame( 5, StreakMath::stage( 2, $l )['points'] );
		$this->assertSame( 6, StreakMath::stage( 3, $l )['points'] );
		$s = StreakMath::stage( 12, $l );
		$this->assertSame( 8, $s['points'] );
		$this->assertSame( array( 'from_day' => 14, 'points' => 10, 'days_left' => 2 ), $s['next_stage'] );
		$this->assertNull( StreakMath::stage( 100, $l )['next_stage'] );
		$this->assertSame( 12, StreakMath::stage( 100, $l )['points'] );
	}

	public function test_first_open_and_consecutive_days(): void {
		$l = $this->levels();
		$r = StreakMath::advance( null, '2026-11-18', $l, 2, 'drop_level' );
		$this->assertSame( 'first', $r['event'] );
		$this->assertSame( 1, $r['state']['days'] );
		$r = StreakMath::advance( $r['state'], '2026-11-19', $l, 2, 'drop_level' );
		$this->assertSame( 'continued', $r['event'] );
		$this->assertSame( 2, $r['state']['days'] );
		$this->assertSame( '2026-11-19', $r['state']['last_date'] );
	}

	public function test_same_day_changes_nothing(): void {
		$s = $this->state( 5, '2026-11-18' );
		$r = StreakMath::advance( $s, '2026-11-18', $this->levels(), 2, 'reset' );
		$this->assertSame( 'same_day', $r['event'] );
		$this->assertSame( 5, $r['state']['days'] );
	}

	public function test_month_boundary_counts_as_consecutive(): void {
		$r = StreakMath::advance( $this->state( 9, '2026-11-30' ), '2026-12-01', $this->levels(), 0, 'reset' );
		$this->assertSame( 'continued', $r['event'] );
		$this->assertSame( 10, $r['state']['days'] );
	}

	public function test_grace_days_bridge_a_gap(): void {
		$l = $this->levels();
		// Einen Tag verpasst (17.), Schutztag hält die Serie, der verpasste Tag zählt nicht.
		$r = StreakMath::advance( $this->state( 6, '2026-11-16' ), '2026-11-18', $l, 2, 'reset' );
		$this->assertSame( 'bridged', $r['event'] );
		$this->assertSame( 1, $r['bridged_days'] );
		$this->assertSame( 7, $r['state']['days'] );
		$this->assertSame( '2026-11', $r['state']['grace_month'] );
		$this->assertSame( 1, $r['state']['grace_used'] );
		$this->assertSame( 1, StreakMath::grace_left( $r['state'], '2026-11-18', 2 ) );
		// Neuer Monat: wieder volle Schutztage.
		$this->assertSame( 2, StreakMath::grace_left( $r['state'], '2026-12-01', 2 ) );
	}

	public function test_gap_larger_than_grace_breaks_with_reset(): void {
		$r = StreakMath::advance( $this->state( 20, '2026-11-14', '2026-11', 1 ), '2026-11-18', $this->levels(), 2, 'reset' );
		$this->assertSame( 'broken', $r['event'] );
		$this->assertSame( 1, $r['state']['days'] );
		$this->assertSame( 20, $r['state']['best'] );
		$this->assertSame( 1, $r['state']['grace_used'], 'Schutztage werden beim Abreißen nicht verbraucht' );
	}

	public function test_drop_level_falls_back_one_stage(): void {
		$l = $this->levels();
		$r = StreakMath::advance( $this->state( 20, '2026-11-10' ), '2026-11-18', $l, 2, 'drop_level' );
		$this->assertSame( 'broken', $r['event'] );
		$this->assertSame( 7, $r['state']['days'], 'Stufe ab 14 → Stufe ab 7' );
		$this->assertSame( 8, StreakMath::stage( $r['state']['days'], $l )['points'] );
		// Aus Stufe "ab 3" geht es auf Tag 1.
		$r = StreakMath::advance( $this->state( 4, '2026-11-10' ), '2026-11-18', $l, 0, 'drop_level' );
		$this->assertSame( 1, $r['state']['days'] );
	}

	public function test_no_grace_means_every_missed_day_breaks(): void {
		$r = StreakMath::advance( $this->state( 5, '2026-11-16' ), '2026-11-18', $this->levels(), 0, 'reset' );
		$this->assertSame( 'broken', $r['event'] );
	}

	public function test_view_before_and_after_opening(): void {
		$l = $this->levels();
		// Gestern Tag 6, heute noch nicht geöffnet: Serie lebt, heute wäre Tag 7 mit 8 Punkten.
		$v = StreakMath::view( $this->state( 6, '2026-11-17' ), '2026-11-18', $l, 2, 'drop_level' );
		$this->assertTrue( $v['alive'] );
		$this->assertFalse( $v['opened_today'] );
		$this->assertSame( 6, $v['days'] );
		$this->assertSame( array( 'day' => 7, 'points' => 8 ), $v['today'] );
		$this->assertSame( 14, $v['next_stage']['from_day'] );
		$this->assertSame( 7, $v['next_stage']['days_left'] );
		// Heute geöffnet.
		$v = StreakMath::view( $this->state( 7, '2026-11-18' ), '2026-11-18', $l, 2, 'drop_level' );
		$this->assertTrue( $v['opened_today'] );
		$this->assertSame( 7, $v['days'] );
		$this->assertSame( 8, $v['stage']['points'] );
		// Gerissen: Anzeige 0, heute zählt als Tag 7 (eine Stufe zurück von 20).
		$v = StreakMath::view( $this->state( 20, '2026-11-01' ), '2026-11-18', $l, 2, 'drop_level' );
		$this->assertFalse( $v['alive'] );
		$this->assertSame( 0, $v['days'] );
		$this->assertSame( 7, $v['today']['day'] );
		// Noch nie geöffnet.
		$v = StreakMath::view( null, '2026-11-18', $l, 2, 'reset' );
		$this->assertSame( 0, $v['days'] );
		$this->assertSame( array( 'day' => 1, 'points' => 5 ), $v['today'] );
	}

	public function test_from_dates_takes_run_ending_today_or_yesterday(): void {
		$dates = array( '2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04', '2026-11-15', '2026-11-16', '2026-11-17' );
		$s     = StreakMath::from_dates( $dates, '2026-11-18' );
		$this->assertSame( 3, $s['days'] );
		$this->assertSame( '2026-11-17', $s['last_date'] );
		$this->assertSame( 4, $s['best'] );
		$s = StreakMath::from_dates( $dates, '2026-11-20' );
		$this->assertSame( 0, $s['days'] );
		$this->assertSame( 4, $s['best'] );
		$this->assertSame( 0, StreakMath::from_dates( array(), '2026-11-20' )['days'] );
	}
}
