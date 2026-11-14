<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\CoachingCalendar;

final class CoachingCalendarTest extends TestCase {
	public function test_phases(): void {
		$this->assertSame( 'vorbereitung', CoachingCalendar::day( null, '2026-11-14' )['key'] );
		$this->assertSame( 'vorbereitung', CoachingCalendar::day( '2026-11-16', '2026-11-14' )['key'] );
		$d1 = CoachingCalendar::day( '2026-11-16', '2026-11-16' );
		$this->assertSame( array( 'phase1', '1. Umstellungstag', 1 ), array( $d1['key'], $d1['day_label'], $d1['coaching_day'] ) );
		$this->assertSame( '2. Umstellungstag', CoachingCalendar::day( '2026-11-16', '2026-11-17' )['day_label'] );
		$p2 = CoachingCalendar::day( '2026-11-16', '2026-11-18' );
		$this->assertSame( array( 'phase2', 1, 'Tag 1 von 10' ), array( $p2['key'], $p2['day_in_phase'], $p2['day_label'] ) );
		$this->assertSame( 'phase2', CoachingCalendar::day( '2026-11-16', '2026-11-27' )['key'] );
		$this->assertSame( 'phase3', CoachingCalendar::day( '2026-11-16', '2026-11-28' )['key'] );
	}

	public function test_milestones(): void {
		$m = CoachingCalendar::milestones( '2026-01-31', array( 'target_weight_3m_kg' => 90, 'target_weight_6m_kg' => 85 ), 89.5, '2026-05-01' );
		$this->assertSame( '2026-05-01', $m[0]['date'] );
		$this->assertTrue( $m[0]['reached'] );
		$this->assertFalse( $m[1]['reached'] );
		$this->assertNull( $m[2]['target_weight_kg'] );
	}

	public function test_progress_by_weight(): void {
		$g = array( 'start_weight_kg' => 100, 'target_weight_12m_kg' => 80 );
		$this->assertSame( 0.25, CoachingCalendar::overall_progress( '2026-01-01', $g, 95.0, '2026-02-01' ) );
		$this->assertSame( 1.0, CoachingCalendar::overall_progress( '2026-01-01', $g, 78.0, '2026-02-01' ) );
	}
}
