<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\CoachingPoints;

final class CoachingPointsTest extends TestCase {

	public function test_app_lesson_awards_until_daily_cap(): void {
		$this->assertNull( CoachingPoints::lesson_block_reason( 'app', false, 0, 5, 10 ) );
		$this->assertNull( CoachingPoints::lesson_block_reason( 'app', false, 4, 5, 10 ) );
		$this->assertSame( 'daily_cap', CoachingPoints::lesson_block_reason( 'app', true, 5, 5, 10 ) );
		$this->assertNull( CoachingPoints::lesson_block_reason( 'app', true, 50, 0, 10 ), '0 = unbegrenzt' );
	}

	public function test_web_history_before_first_sync_brings_nothing(): void {
		$this->assertSame( 'history', CoachingPoints::lesson_block_reason( 'web', false, 0, 5, 10 ) );
		$this->assertNull( CoachingPoints::lesson_block_reason( 'web', true, 0, 5, 10 ) );
	}

	public function test_switched_off(): void {
		$this->assertSame( 'off', CoachingPoints::lesson_block_reason( 'app', true, 0, 5, 0 ) );
	}

	public function test_course_complete(): void {
		$this->assertTrue( CoachingPoints::course_complete( array( 1, 2 ), array( '1' => array(), '2' => array(), '9' => array() ) ) );
		$this->assertFalse( CoachingPoints::course_complete( array( 1, 2 ), array( '1' => array() ) ) );
		$this->assertFalse( CoachingPoints::course_complete( array(), array( '1' => array() ) ), 'leerer Kurs' );
	}
}
