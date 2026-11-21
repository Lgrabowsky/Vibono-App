<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Datenbanktabellen, Cron-Jobs, Aktivierung.
 */
class Install {

	public static function activate(): void {
		self::install();
		// Permalink-Regeln beim nächsten Seitenaufruf neu aufbauen lassen (Reiter "Mein Konto → Vibono-Punkte").
		delete_option( 'rewrite_rules' );
	}

	private static function install(): void {
		self::create_tables();
		Settings::ensure_defaults();
		if ( ! wp_next_scheduled( 'vibono_points_daily' ) ) {
			wp_schedule_event( time() + 300, 'hourly', 'vibono_points_daily' );
		}
		update_option( 'vibono_api_db_version', VIBONO_API_DB_VERSION );
	}

	/**
	 * Deaktivieren: Cron entfernen und Permalink-Regeln ohne unseren Endpunkt neu aufbauen lassen.
	 * Daten bleiben erhalten, damit ein erneutes Aktivieren nahtlos weitergeht.
	 */
	public static function deactivate(): void {
		wp_clear_scheduled_hook( 'vibono_points_daily' );
		delete_option( 'rewrite_rules' );
	}

	public static function maybe_upgrade(): void {
		if ( get_option( 'vibono_api_db_version' ) !== VIBONO_API_DB_VERSION ) {
			self::install();
		}
	}

	public static function table( string $name ): string {
		global $wpdb;
		return $wpdb->prefix . 'vibono_' . $name;
	}

	public static function create_tables(): void {
		global $wpdb;
		require_once ABSPATH . 'wp-admin/includes/upgrade.php';
		$c = $wpdb->get_charset_collate();

		// Refresh-Tokens (nur Hash gespeichert).
		dbDelta(
			'CREATE TABLE ' . self::table( 'tokens' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			user_id bigint(20) unsigned NOT NULL,
			token_hash char(64) NOT NULL,
			family char(32) NOT NULL,
			device_name varchar(100) NOT NULL DEFAULT '',
			created_at datetime NOT NULL,
			expires_at datetime NOT NULL,
			revoked tinyint(1) NOT NULL DEFAULT 0,
			PRIMARY KEY  (id),
			UNIQUE KEY token_hash (token_hash),
			KEY user_id (user_id),
			KEY family (family)
		) $c;"
		);

		// Sync-Änderungsprotokoll: ein Datensatz je (Nutzer, Sammlung, Schlüssel), seq ist der Cursor.
		dbDelta(
			'CREATE TABLE ' . self::table( 'sync' ) . " (
			seq bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			user_id bigint(20) unsigned NOT NULL,
			collection varchar(32) NOT NULL,
			item_key varchar(100) NOT NULL,
			data longtext NULL,
			deleted tinyint(1) NOT NULL DEFAULT 0,
			updated_at bigint(20) unsigned NOT NULL,
			source varchar(10) NOT NULL DEFAULT 'app',
			PRIMARY KEY  (seq),
			UNIQUE KEY item (user_id,collection,item_key),
			KEY user_seq (user_id,seq)
		) $c;"
		);

		// Punkte-Hauptbuch. Kontostand = Summe bestätigter Einträge.
		dbDelta(
			'CREATE TABLE ' . self::table( 'points_ledger' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			user_id bigint(20) unsigned NOT NULL,
			points int(11) NOT NULL,
			reason varchar(32) NOT NULL,
			status varchar(10) NOT NULL DEFAULT 'confirmed',
			ref_type varchar(32) NOT NULL DEFAULT '',
			ref_id bigint(20) unsigned NOT NULL DEFAULT 0,
			idempotency_key varchar(120) NULL,
			base_points int(11) NOT NULL DEFAULT 0,
			multiplier decimal(6,3) NOT NULL DEFAULT 1.000,
			campaign_id bigint(20) unsigned NULL,
			label varchar(255) NOT NULL DEFAULT '',
			meta longtext NULL,
			created_at datetime NOT NULL,
			confirms_at datetime NULL,
			created_by bigint(20) unsigned NOT NULL DEFAULT 0,
			PRIMARY KEY  (id),
			UNIQUE KEY idempotency_key (idempotency_key),
			KEY user_status (user_id,status),
			KEY ref (ref_type,ref_id),
			KEY pending (status,confirms_at)
		) $c;"
		);

		// Aktionen (Multiplikatoren für Verdienen oder Einlösewert).
		dbDelta(
			'CREATE TABLE ' . self::table( 'campaigns' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			name varchar(120) NOT NULL,
			description text NULL,
			kind varchar(10) NOT NULL,
			reasons varchar(255) NOT NULL DEFAULT '',
			multiplier decimal(6,3) NOT NULL DEFAULT 2.000,
			starts_at datetime NOT NULL,
			ends_at datetime NOT NULL,
			enabled tinyint(1) NOT NULL DEFAULT 1,
			created_at datetime NOT NULL,
			PRIMARY KEY  (id),
			KEY kind_window (kind,enabled,starts_at,ends_at)
		) $c;"
		);

		// Prämien-Katalog (Punkte einlösen).
		dbDelta(
			'CREATE TABLE ' . self::table( 'rewards' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			kind varchar(20) NOT NULL,
			title varchar(190) NOT NULL,
			description text NULL,
			cost_points int(11) NOT NULL,
			post_id bigint(20) unsigned NOT NULL DEFAULT 0,
			attachment_id bigint(20) unsigned NOT NULL DEFAULT 0,
			discount_type varchar(10) NOT NULL DEFAULT 'fixed',
			discount_amount decimal(10,2) NOT NULL DEFAULT 0.00,
			product_ids varchar(255) NOT NULL DEFAULT '',
			valid_days int(11) NOT NULL DEFAULT 0,
			per_user_limit int(11) NOT NULL DEFAULT 1,
			enabled tinyint(1) NOT NULL DEFAULT 1,
			sort_order int(11) NOT NULL DEFAULT 0,
			created_at datetime NOT NULL,
			PRIMARY KEY  (id),
			KEY kind_enabled (kind,enabled),
			KEY post_id (post_id)
		) $c;"
		);

		// Eingelöste Prämien je Person.
		dbDelta(
			'CREATE TABLE ' . self::table( 'reward_unlocks' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			user_id bigint(20) unsigned NOT NULL,
			reward_id bigint(20) unsigned NOT NULL,
			kind varchar(20) NOT NULL,
			points int(11) NOT NULL,
			ledger_id bigint(20) unsigned NOT NULL DEFAULT 0,
			coupon_code varchar(40) NOT NULL DEFAULT '',
			coupon_id bigint(20) unsigned NOT NULL DEFAULT 0,
			channel varchar(10) NOT NULL DEFAULT '',
			created_at datetime NOT NULL,
			expires_at datetime NULL,
			PRIMARY KEY  (id),
			KEY user_reward (user_id,reward_id),
			KEY reward_id (reward_id)
		) $c;"
		);

		// Lese-Sessions für den Lese-Nachweis.
		dbDelta(
			'CREATE TABLE ' . self::table( 'reading' ) . " (
			id char(32) NOT NULL,
			user_id bigint(20) unsigned NOT NULL,
			post_id bigint(20) unsigned NOT NULL,
			word_count int(11) NOT NULL DEFAULT 0,
			min_active_seconds int(11) NOT NULL,
			started_at bigint(20) unsigned NOT NULL,
			last_beat_at bigint(20) unsigned NOT NULL,
			accepted_seconds int(11) NOT NULL DEFAULT 0,
			beats int(11) NOT NULL DEFAULT 0,
			scroll_depth decimal(4,3) NOT NULL DEFAULT 0,
			quiz_failed_at bigint(20) unsigned NOT NULL DEFAULT 0,
			completed tinyint(1) NOT NULL DEFAULT 0,
			channel varchar(10) NOT NULL DEFAULT 'app',
			PRIMARY KEY  (id),
			KEY user_post (user_id,post_id)
		) $c;"
		);

		// Push-Geräte.
		dbDelta(
			'CREATE TABLE ' . self::table( 'devices' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			user_id bigint(20) unsigned NOT NULL,
			token varchar(255) NOT NULL,
			platform varchar(10) NOT NULL,
			app_version varchar(20) NOT NULL DEFAULT '',
			locale varchar(10) NOT NULL DEFAULT '',
			updated_at datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY token (token(191)),
			KEY user_id (user_id)
		) $c;"
		);
	}
}
