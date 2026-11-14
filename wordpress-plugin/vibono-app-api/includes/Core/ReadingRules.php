<?php
namespace Vibono\AppApi\Core;

/**
 * Lese-Nachweis. Reine Logik, ohne WordPress testbar.
 *
 * Kombination aus vier Signalen (siehe docs/PUNKTESYSTEM.md):
 *  1. Mindest-Aktivzeit abhängig von der Wortzahl.
 *  2. Aktivzeit wird nur anerkannt, soweit seit dem letzten Heartbeat auch Wanduhrzeit vergangen ist
 *     (ein manipulierter Client kann keine 10 Minuten in 1 Sekunde melden).
 *  3. Scrolltiefe bis (fast) zum Ende.
 *  4. Optional eine Quizfrage zum Inhalt.
 */
class ReadingRules {

	public static function min_active_seconds( int $words, int $wpm, float $factor, int $min, int $max ): int {
		$expected = $wpm > 0 ? ( $words / $wpm ) * 60 : 0;
		return (int) max( $min, min( $max, (int) ceil( $expected * $factor ) ) );
	}

	/**
	 * Verarbeitet einen Heartbeat.
	 *
	 * @param array $s Session: accepted_seconds, last_beat_at, scroll_depth, beats.
	 * @return array Neue Session-Werte.
	 */
	public static function beat( array $s, int $reported_total, float $scroll, int $now, int $interval ): array {
		$elapsed  = max( 0, $now - (int) $s['last_beat_at'] );
		// Pro Heartbeat höchstens die vergangene Zeit, max. 2 Intervalle (App kurz im Hintergrund zählt nicht).
		$allowed  = min( $elapsed, $interval * 2 + 2 );
		$claimed  = max( 0, $reported_total - (int) $s['accepted_seconds'] );
		$accepted = (int) $s['accepted_seconds'] + min( $claimed, $allowed );
		return array(
			'accepted_seconds' => $accepted,
			'last_beat_at'     => $now,
			'scroll_depth'     => max( (float) $s['scroll_depth'], max( 0.0, min( 1.0, $scroll ) ) ),
			'beats'            => (int) $s['beats'] + 1,
		);
	}

	/** @return string[] Fehlende Bedingungen (leer = erfüllt). */
	public static function missing( array $s, int $min_seconds, float $min_scroll ): array {
		$missing = array();
		if ( (int) $s['accepted_seconds'] < $min_seconds ) {
			$missing[] = 'active_time';
		}
		if ( (float) $s['scroll_depth'] + 0.0001 < $min_scroll ) {
			$missing[] = 'scroll_depth';
		}
		// Mindestens zwei Heartbeats, damit kein "Start + sofort Complete" durchgeht.
		if ( (int) $s['beats'] < 2 ) {
			$missing[] = 'heartbeats';
		}
		return $missing;
	}

	/** Wortzahl aus HTML. */
	public static function word_count( string $html ): int {
		$text = html_entity_decode( strip_tags( preg_replace( '#<(script|style)[^>]*>.*?</\1>#si', ' ', $html ) ), ENT_QUOTES, 'UTF-8' );
		$text = preg_replace( '/\[[^\]]+\]/', ' ', $text ); // Shortcodes.
		preg_match_all( '/[\p{L}\p{N}]+/u', $text, $m );
		return count( $m[0] );
	}
}
