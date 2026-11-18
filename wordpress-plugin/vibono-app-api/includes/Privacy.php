<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Anbindung an die Datenschutz-Werkzeuge von WordPress (Werkzeuge → Personenbezogene Daten
 * exportieren/löschen) und Aufräumen beim Löschen eines Kontos.
 *
 * So bleiben nach dem Löschen eines Kontos keine Vibono-Daten zurück, und die Löschanfrage aus der App
 * (DELETE /me erzeugt eine bestätigte Löschanfrage in WordPress) erfasst auch die Plugin-Daten.
 * Daten, die das Theme selbst speichert (MyVibono-Felder), löscht WordPress mit dem Konto.
 */
class Privacy {

	const TABLES = array( 'tokens', 'sync', 'points_ledger', 'reading', 'devices' );

	public static function init(): void {
		Plugin::hook( 'wp_privacy_personal_data_exporters', array( self::class, 'register_exporter' ) );
		Plugin::hook( 'wp_privacy_personal_data_erasers', array( self::class, 'register_eraser' ) );
		Plugin::hook( 'deleted_user', array( self::class, 'delete_user_data' ) );
	}

	public static function register_exporter( $exporters ) {
		$exporters['vibono-app-api'] = array(
			'exporter_friendly_name' => 'Vibono-App und Vibono-Punkte',
			'callback'               => array( self::class, 'export' ),
		);
		return $exporters;
	}

	public static function register_eraser( $erasers ) {
		$erasers['vibono-app-api'] = array(
			'eraser_friendly_name' => 'Vibono-App und Vibono-Punkte',
			'callback'             => array( self::class, 'erase' ),
		);
		return $erasers;
	}

	public static function export( $email, $page = 1 ): array {
		global $wpdb;
		$user = get_user_by( 'email', (string) $email );
		if ( ! $user ) {
			return array( 'data' => array(), 'done' => true );
		}
		$uid  = (int) $user->ID;
		$data = array();

		$profile = array();
		$labels  = array(
			Profile::ONBOARDING_META   => 'Angaben aus dem Onboarding',
			Profile::GOALS_META        => 'Ziele',
			'_vibono_privacy_consent'  => 'Einwilligung Datenschutz',
			Referral::CODE_META        => 'Empfehlungscode',
			Referral::BY_META          => 'Geworben von (Konto-ID)',
			'_vibono_referred_at'      => 'Geworben am',
			Streak::META               => 'Serie beim Öffnen der App',
		);
		foreach ( $labels as $key => $label ) {
			$v = get_user_meta( $uid, $key, true );
			if ( '' !== $v && null !== $v && array() !== $v ) {
				$profile[] = array( 'name' => $label, 'value' => is_scalar( $v ) ? (string) $v : wp_json_encode( $v ) );
			}
		}
		if ( $profile ) {
			$data[] = array( 'group_id' => 'vibono-profile', 'group_label' => 'Vibono-App: Profil', 'item_id' => 'vibono-profile-' . $uid, 'data' => $profile );
		}

		$sync = $wpdb->get_results( $wpdb->prepare( 'SELECT seq, collection, item_key, data FROM ' . Install::table( 'sync' ) . ' WHERE user_id = %d AND deleted = 0 ORDER BY collection, item_key', $uid ) );
		foreach ( $sync as $row ) {
			$data[] = array(
				'group_id'    => 'vibono-sync',
				'group_label' => 'Vibono-App: MyVibono-Daten',
				'item_id'     => 'vibono-sync-' . $row->seq,
				'data'        => array(
					array( 'name' => 'Bereich', 'value' => $row->collection ),
					array( 'name' => 'Eintrag', 'value' => $row->item_key ),
					array( 'name' => 'Daten', 'value' => (string) $row->data ),
				),
			);
		}

		$ledger = $wpdb->get_results( $wpdb->prepare( 'SELECT id, created_at, points, status, label FROM ' . Install::table( 'points_ledger' ) . ' WHERE user_id = %d ORDER BY id', $uid ) );
		foreach ( $ledger as $row ) {
			$data[] = array(
				'group_id'    => 'vibono-points',
				'group_label' => 'Vibono-Punkte',
				'item_id'     => 'vibono-points-' . $row->id,
				'data'        => array(
					array( 'name' => 'Datum (UTC)', 'value' => $row->created_at ),
					array( 'name' => 'Punkte', 'value' => (string) $row->points ),
					array( 'name' => 'Status', 'value' => $row->status ),
					array( 'name' => 'Buchung', 'value' => $row->label ),
				),
			);
		}

		$devices = $wpdb->get_results( $wpdb->prepare( 'SELECT id, platform, app_version, updated_at FROM ' . Install::table( 'devices' ) . ' WHERE user_id = %d', $uid ) );
		foreach ( $devices as $row ) {
			$data[] = array(
				'group_id'    => 'vibono-devices',
				'group_label' => 'Vibono-App: Geräte für Mitteilungen',
				'item_id'     => 'vibono-device-' . $row->id,
				'data'        => array(
					array( 'name' => 'Plattform', 'value' => $row->platform ),
					array( 'name' => 'App-Version', 'value' => $row->app_version ),
					array( 'name' => 'Zuletzt aktualisiert (UTC)', 'value' => $row->updated_at ),
				),
			);
		}

		return array( 'data' => $data, 'done' => true );
	}

	public static function erase( $email, $page = 1 ): array {
		$user = get_user_by( 'email', (string) $email );
		if ( ! $user ) {
			return array( 'items_removed' => false, 'items_retained' => false, 'messages' => array(), 'done' => true );
		}
		$removed = self::delete_user_data( (int) $user->ID );
		// Bereits ausgestellte App-Zugänge sofort ungültig machen (Konto selbst bleibt bestehen).
		update_user_meta( (int) $user->ID, '_vibono_token_version', time() );
		return array(
			'items_removed'  => $removed > 0,
			'items_retained' => false,
			'messages'       => $removed > 0 ? array( 'Vibono-App-Daten und Vibono-Punktestand wurden gelöscht.' ) : array(),
			'done'           => true,
		);
	}

	/** Alle Vibono-Daten eines Kontos löschen (Tabellen und Nutzer-Meta mit Präfix _vibono_). */
	public static function delete_user_data( $user_id ): int {
		global $wpdb;
		$uid = (int) $user_id;
		if ( $uid <= 0 ) {
			return 0;
		}
		$n = 0;
		foreach ( self::TABLES as $t ) {
			$n += (int) $wpdb->delete( Install::table( $t ), array( 'user_id' => $uid ), array( '%d' ) );
		}
		$n += (int) $wpdb->query( $wpdb->prepare( "DELETE FROM {$wpdb->usermeta} WHERE user_id = %d AND meta_key LIKE %s", $uid, $wpdb->esc_like( '_vibono_' ) . '%' ) );
		wp_cache_delete( $uid, 'user_meta' );
		return $n;
	}
}
