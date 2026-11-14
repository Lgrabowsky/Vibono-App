<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\SyncRules;

final class SyncRulesTest extends TestCase {
	public function test_last_write_wins_server_wins_ties(): void {
		$this->assertTrue( SyncRules::incoming_wins( 2000, 1000 ) );
		$this->assertFalse( SyncRules::incoming_wins( 1000, 1000 ) );
		$this->assertFalse( SyncRules::incoming_wins( 999, 1000 ) );
		$this->assertTrue( SyncRules::incoming_wins( 1, null ) );
	}

	public function test_paths(): void {
		$this->assertSame( 'lessons_done', SyncRules::collection_from_path( 'lessons-done' ) );
		$this->assertNull( SyncRules::collection_from_path( 'passwords' ) );
	}

	public function test_favorites_key(): void {
		$this->assertSame( array( array( 'post_id' => 12, 'kind' => 'recipe' ), null ), SyncRules::validate( 'favorites', 'recipe:12', 'upsert', null ) );
		$this->assertSame( 'invalid_key', SyncRules::validate( 'favorites', 'recipe:abc', 'upsert', null )[1] );
	}

	public function test_weight_validation(): void {
		$this->assertSame( array( 'date' => '2026-11-14', 'kg' => 92.4 ), SyncRules::validate( 'weight', '2026-11-14', 'upsert', array( 'kg' => 92.43 ) )[0] );
		$this->assertSame( 'invalid_weight', SyncRules::validate( 'weight', '2026-11-14', 'upsert', array( 'kg' => 5 ) )[1] );
		$this->assertSame( 'invalid_key', SyncRules::validate( 'weight', '2026-02-30', 'upsert', array( 'kg' => 80 ) )[1] );
	}

	public function test_weekplan_has_slots_not_times(): void {
		$ok = SyncRules::validate( 'weekplan', '2026-11-16:mittag', 'upsert', array( 'recipe_id' => 5 ) );
		$this->assertSame( 'mittag', $ok[0]['slot'] );
		$this->assertSame( 'invalid_key', SyncRules::validate( 'weekplan', '2026-11-16:12:30', 'upsert', array( 'recipe_id' => 5 ) )[1] );
		$this->assertSame( 'invalid_weekplan', SyncRules::validate( 'weekplan', '2026-11-16:abend', 'upsert', array() )[1] );
	}

	public function test_sport_entry(): void {
		$r = SyncRules::validate( 'sport', 'a1b2c3d4-0000', 'upsert', array( 'date' => '2026-11-14', 'activity' => 'Spazieren', 'minutes' => 30 ) );
		$this->assertNull( $r[1] );
		$this->assertSame( 30, $r[0]['minutes'] );
	}

	public function test_future_timestamps_are_capped(): void {
		$now = 1_800_000_000_000;
		$this->assertSame( $now + 300000, SyncRules::parse_time_ms( '2030-01-01T00:00:00Z', $now ) );
		$this->assertSame( 1_763_125_200_250, SyncRules::parse_time_ms( '2025-11-14T13:00:00.25Z', $now ) );
		$this->assertNull( SyncRules::parse_time_ms( 'gestern', $now ) );
	}
}
