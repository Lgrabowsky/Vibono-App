<?php
namespace Vibono\AppApi\Core;

/**
 * Regeln des Prämien-Katalogs (Punkte einlösen). Reine Logik, ohne WordPress testbar.
 *
 * Prämienarten
 *  - content:          exklusiver Beitrag (Rezept, Tipp, …), einmal freischalten, danach dauerhaft lesbar.
 *  - download:         exklusives eBook/PDF, einmal freischalten, danach beliebig oft herunterladen.
 *  - renewal_discount: persönlicher Gutschein für die Verlängerung einer Mitgliedschaft im Shop.
 */
class RewardRules {

	const KINDS = array( 'content', 'download', 'renewal_discount' );

	/** Prämienarten, die nur einmal je Person eingelöst werden können. */
	const ONCE = array( 'content', 'download' );

	/**
	 * Prüft und normalisiert eine Prämie aus dem Backend.
	 *
	 * @return array{0: ?array, 1: ?string} [Prämie, Fehlermeldung]
	 */
	public static function normalize( array $in ): array {
		$kind  = (string) ( $in['kind'] ?? '' );
		$title = trim( (string) ( $in['title'] ?? '' ) );
		$cost  = (int) ( $in['cost_points'] ?? 0 );
		if ( ! in_array( $kind, self::KINDS, true ) ) {
			return array( null, 'Bitte eine Art wählen.' );
		}
		if ( '' === $title ) {
			return array( null, 'Bitte einen Titel angeben.' );
		}
		if ( $cost < 1 ) {
			return array( null, 'Die Prämie muss mindestens 1 Punkt kosten.' );
		}
		$out = array(
			'kind'            => $kind,
			'title'           => $title,
			'description'     => trim( (string) ( $in['description'] ?? '' ) ),
			'cost_points'     => $cost,
			'post_id'         => 0,
			'attachment_id'   => 0,
			'discount_type'   => 'fixed',
			'discount_amount' => 0.0,
			'product_ids'     => array(),
			'valid_days'      => 0,
			'per_user_limit'  => 1,
			'enabled'         => ! empty( $in['enabled'] ),
			'sort_order'      => (int) ( $in['sort_order'] ?? 0 ),
		);
		switch ( $kind ) {
			case 'content':
				$out['post_id'] = (int) ( $in['post_id'] ?? 0 );
				if ( $out['post_id'] <= 0 ) {
					return array( null, 'Bitte die ID des exklusiven Beitrags angeben.' );
				}
				break;
			case 'download':
				$out['attachment_id'] = (int) ( $in['attachment_id'] ?? 0 );
				if ( $out['attachment_id'] <= 0 ) {
					return array( null, 'Bitte die ID der Datei aus der Mediathek angeben.' );
				}
				break;
			case 'renewal_discount':
				$type   = 'percent' === ( $in['discount_type'] ?? '' ) ? 'percent' : 'fixed';
				$amount = round( (float) str_replace( ',', '.', (string) ( $in['discount_amount'] ?? 0 ) ), 2 );
				if ( $amount <= 0 || ( 'percent' === $type && $amount > 100 ) ) {
					return array( null, 'Bitte einen Rabatt größer 0 angeben (Prozent höchstens 100).' );
				}
				$out['discount_type']   = $type;
				$out['discount_amount'] = $amount;
				$out['product_ids']     = self::id_list( $in['product_ids'] ?? array() );
				$out['valid_days']      = max( 1, (int) ( $in['valid_days'] ?? 90 ) );
				$out['per_user_limit']  = max( 0, (int) ( $in['per_user_limit'] ?? 1 ) );
				break;
		}
		return array( $out, null );
	}

	/** "12, 13 x 14" → [12, 13, 14] */
	public static function id_list( $v ): array {
		$parts = is_array( $v ) ? $v : preg_split( '/[^0-9]+/', (string) $v );
		return array_values( array_unique( array_filter( array_map( 'intval', (array) $parts ), static fn( $i ) => $i > 0 ) ) );
	}

	/**
	 * Darf diese Person die Prämie jetzt einlösen?
	 *
	 * @param array $reward   Normalisierte Prämie (enabled, kind, cost_points, per_user_limit).
	 * @param int   $balance  Verfügbare Punkte.
	 * @param int   $redeemed Wie oft diese Person die Prämie schon eingelöst hat.
	 * @param bool  $here     Ist die Prämienart in diesem Kanal (App-Plattform/Website) erlaubt?
	 * @return string|null Fehlercode oder null.
	 */
	public static function check( array $reward, int $balance, int $redeemed, bool $here ): ?string {
		if ( empty( $reward['enabled'] ) ) {
			return 'disabled';
		}
		if ( ! $here ) {
			return 'not_available_here';
		}
		if ( in_array( $reward['kind'], self::ONCE, true ) && $redeemed > 0 ) {
			return 'already_unlocked';
		}
		$limit = (int) ( $reward['per_user_limit'] ?? 0 );
		if ( $limit > 0 && $redeemed >= $limit ) {
			return 'limit_reached';
		}
		if ( $balance < (int) $reward['cost_points'] ) {
			return 'insufficient_points';
		}
		return null;
	}

	/** Lesbarer Rabatt, z. B. "10 € Rabatt" oder "15 % Rabatt". */
	public static function discount_label( string $type, float $amount ): string {
		$n = fmod( $amount, 1.0 ) === 0.0 ? number_format( $amount, 0, ',', '.' ) : number_format( $amount, 2, ',', '.' );
		return 'percent' === $type ? $n . ' % Rabatt' : $n . ' € Rabatt';
	}

	/** Gutscheincode aus Zufallsbytes: VP-XXXX-XXXX ohne verwechselbare Zeichen (0/O, 1/I). */
	public static function coupon_code( string $random_bytes ): string {
		$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
		$out      = '';
		$bytes    = array_values( unpack( 'C*', $random_bytes ) ?: array() );
		for ( $i = 0; $i < 8; $i++ ) {
			$out .= $alphabet[ ( $bytes[ $i ] ?? 0 ) % strlen( $alphabet ) ];
		}
		return 'VP-' . substr( $out, 0, 4 ) . '-' . substr( $out, 4, 4 );
	}

	// ------------------------------------------------ Download-Links

	/** Signierter, kurzlebiger Download-Link: Nutzer, Prämie und Ablauf, HMAC-SHA256. */
	public static function download_token( int $user_id, int $reward_id, int $expires, string $secret ): string {
		$payload = $user_id . '.' . $reward_id . '.' . $expires;
		return $payload . '.' . self::b64( hash_hmac( 'sha256', 'dl|' . $payload, $secret, true ) );
	}

	/** @return array{user_id:int, reward_id:int, expires:int}|null */
	public static function verify_download_token( string $token, string $secret, int $now ): ?array {
		if ( ! preg_match( '/^(\d+)\.(\d+)\.(\d+)\.([A-Za-z0-9_-]+)$/', $token, $m ) ) {
			return null;
		}
		$expected = self::b64( hash_hmac( 'sha256', 'dl|' . $m[1] . '.' . $m[2] . '.' . $m[3], $secret, true ) );
		if ( ! hash_equals( $expected, $m[4] ) || (int) $m[3] < $now ) {
			return null;
		}
		return array( 'user_id' => (int) $m[1], 'reward_id' => (int) $m[2], 'expires' => (int) $m[3] );
	}

	private static function b64( string $raw ): string {
		return rtrim( strtr( base64_encode( $raw ), '+/', '-_' ), '=' );
	}
}
