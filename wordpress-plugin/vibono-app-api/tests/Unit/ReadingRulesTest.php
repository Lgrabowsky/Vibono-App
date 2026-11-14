<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\ReadingRules;

final class ReadingRulesTest extends TestCase {
	public function test_min_seconds_scales_with_words_and_is_capped(): void {
		// 1100 Wörter / 220 wpm = 5 min = 300 s; 40 % = 120 s.
		$this->assertSame( 120, ReadingRules::min_active_seconds( 1100, 220, 0.4, 20, 300 ) );
		$this->assertSame( 20, ReadingRules::min_active_seconds( 50, 220, 0.4, 20, 300 ) );
		$this->assertSame( 300, ReadingRules::min_active_seconds( 20000, 220, 0.4, 20, 300 ) );
	}

	public function test_client_cannot_claim_more_time_than_elapsed(): void {
		$s = array( 'accepted_seconds' => 0, 'last_beat_at' => 1000, 'scroll_depth' => 0, 'beats' => 0 );
		// Behauptet 600 s, aber nur 10 s vergangen.
		$s = array_merge( $s, ReadingRules::beat( $s, 600, 0.5, 1010, 10 ) );
		$this->assertSame( 10, $s['accepted_seconds'] );
	}

	public function test_long_gap_counts_only_two_intervals(): void {
		$s = array( 'accepted_seconds' => 0, 'last_beat_at' => 1000, 'scroll_depth' => 0, 'beats' => 0 );
		$s = array_merge( $s, ReadingRules::beat( $s, 500, 0.5, 1500, 10 ) );
		$this->assertSame( 22, $s['accepted_seconds'] );
	}

	public function test_honest_reader_completes(): void {
		$s   = array( 'accepted_seconds' => 0, 'last_beat_at' => 0, 'scroll_depth' => 0, 'beats' => 0 );
		$now = 0;
		for ( $i = 1; $i <= 6; $i++ ) {
			$now += 10;
			$s    = array_merge( $s, ReadingRules::beat( $s, $i * 10, min( 1, $i * 0.18 ), $now, 10 ) );
		}
		$this->assertSame( array(), ReadingRules::missing( $s, 60, 0.9 ) );
	}

	public function test_missing_conditions_reported(): void {
		$s = array( 'accepted_seconds' => 30, 'scroll_depth' => 0.5, 'beats' => 1 );
		$this->assertSame( array( 'active_time', 'scroll_depth', 'heartbeats' ), ReadingRules::missing( $s, 60, 0.9 ) );
	}

	public function test_scroll_depth_never_decreases(): void {
		$s = array( 'accepted_seconds' => 0, 'last_beat_at' => 0, 'scroll_depth' => 0.8, 'beats' => 1 );
		$this->assertSame( 0.8, ReadingRules::beat( $s, 10, 0.2, 10, 10 )['scroll_depth'] );
	}

	public function test_word_count_ignores_markup_and_shortcodes(): void {
		$html = '<p>Iss dich <strong>satt</strong>!</p><script>var x = 1;</script>[vibono_box id="3"] Genuss statt Verzicht.';
		$this->assertSame( 6, ReadingRules::word_count( $html ) ); // Iss dich satt Genuss statt Verzicht
	}
}
