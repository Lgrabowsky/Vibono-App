<?php
namespace Vibono\AppApi\Core;

/**
 * Regeln für Punkte aus dem Coaching-Fortschritt. Reine Logik, ohne WordPress testbar.
 *
 * - Lektion erledigt: einmal je Lektion, höchstens N Lektionen pro Tag.
 * - Kurs abgeschlossen: Bonus, sobald alle veröffentlichten Lektionen eines Kurses erledigt sind.
 * - Häkchen, die beim allerersten Abgleich von der Website übernommen werden, sind Vergangenheit
 *   und bringen keine Punkte (sonst gäbe es beim Start Punkte für alte Lektionen).
 */
class CoachingPoints {

	/**
	 * Warum es für ein neues Häkchen keine Lektionspunkte gibt (null = Punkte vergeben).
	 *
	 * @param string $source        app|web
	 * @param bool   $has_baseline  Wurde der Website-Stand dieser Person schon einmal übernommen?
	 * @param int    $awarded_today Lektionspunkte, die heute schon vergeben wurden (Anzahl Buchungen).
	 * @param int    $daily_cap     Höchstens so viele Lektionen pro Tag (0 = unbegrenzt).
	 * @param int    $points        Punkte je Lektion laut Einstellung.
	 */
	public static function lesson_block_reason( string $source, bool $has_baseline, int $awarded_today, int $daily_cap, int $points ): ?string {
		if ( $points <= 0 ) {
			return 'off';
		}
		if ( 'web' === $source && ! $has_baseline ) {
			return 'history';
		}
		if ( $daily_cap > 0 && $awarded_today >= $daily_cap ) {
			return 'daily_cap';
		}
		return null;
	}

	/** Sind alle Lektionen eines Kurses erledigt? Ein Kurs ohne Lektionen gilt nicht als abgeschlossen. */
	public static function course_complete( array $lesson_ids, array $done_map ): bool {
		if ( ! $lesson_ids ) {
			return false;
		}
		foreach ( $lesson_ids as $id ) {
			if ( ! isset( $done_map[ (string) $id ] ) ) {
				return false;
			}
		}
		return true;
	}
}
