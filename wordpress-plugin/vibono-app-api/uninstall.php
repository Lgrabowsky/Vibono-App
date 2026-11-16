<?php
/**
 * Läuft, wenn das Plugin in WordPress gelöscht wird (Plugins → Deaktivieren → Löschen).
 *
 * Immer:   Cron-Job, Permalink-Cache und kurzlebige Zwischenspeicher (Transients) entfernen.
 * Optional: Nur wenn unter "Vibono-Punkte → Module & Anbindung" die Option
 *          "Beim Löschen alle Daten entfernen" gesetzt ist, werden Tabellen, Einstellungen und
 *          Vibono-Meta-Felder gelöscht. Standard ist Behalten, weil die Tabellen die Punktestände
 *          der Kund*innen (Guthaben) enthalten. Vorher sichern: wp vibono export-points > punkte.csv
 *
 * Nie angefasst: Bestellungen und deren Gutschein-Zeilen, Inhalte, Nutzerkonten und die
 * MyVibono-Felder des Themes.
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

/**
 * Räumt eine einzelne Website auf.
 */
function vibono_api_uninstall_site(): void {
	global $wpdb;

	wp_clear_scheduled_hook( 'vibono_points_daily' );
	delete_option( 'rewrite_rules' );

	// Transients (Login-Links, Bremsen, Fehlerhinweis) sind immer entbehrlich.
	$wpdb->query( $wpdb->prepare( "DELETE FROM {$wpdb->options} WHERE option_name LIKE %s OR option_name LIKE %s", $wpdb->esc_like( '_transient_vibono_' ) . '%', $wpdb->esc_like( '_transient_timeout_vibono_' ) . '%' ) );

	$settings = get_option( 'vibono_api_settings', array() );
	if ( empty( $settings['delete_data_on_uninstall'] ) ) {
		return;
	}

	foreach ( array( 'tokens', 'sync', 'points_ledger', 'campaigns', 'reading', 'devices' ) as $name ) {
		$wpdb->query( 'DROP TABLE IF EXISTS `' . esc_sql( $wpdb->prefix . 'vibono_' . $name ) . '`' ); // phpcs:ignore
	}
	foreach ( array( 'vibono_api_settings', 'vibono_api_jwt_secret', 'vibono_api_db_version', 'vibono_api_removed', 'vibono_points_rate_log', 'vibono_api_anthropic_key' ) as $option ) {
		delete_option( $option );
	}
	// Nur die eigenen Beitrags-Meta-Felder (Quizfrage, Wortzahl). Bestell-Meta bleibt für die Buchhaltung.
	$wpdb->query( "DELETE FROM {$wpdb->postmeta} WHERE meta_key IN ('_vibono_quiz', '_vibono_word_count')" ); // phpcs:ignore
}

// Vor dem Aufräumen lesen: Danach ist die Einstellung selbst gelöscht. Nutzer-Meta ist netzwerkweit,
// deshalb entscheidet bei Multisite die Einstellung der Hauptseite.
$vibono_main_settings = is_multisite() ? get_blog_option( get_main_site_id(), 'vibono_api_settings', array() ) : get_option( 'vibono_api_settings', array() );
$vibono_delete_all    = is_array( $vibono_main_settings ) && ! empty( $vibono_main_settings['delete_data_on_uninstall'] );

if ( is_multisite() ) {
	foreach ( get_sites( array( 'fields' => 'ids', 'number' => 0 ) ) as $vibono_site_id ) {
		switch_to_blog( (int) $vibono_site_id );
		vibono_api_uninstall_site();
		restore_current_blog();
	}
} else {
	vibono_api_uninstall_site();
}

if ( $vibono_delete_all ) {
	global $wpdb;
	$wpdb->query( $wpdb->prepare( "DELETE FROM {$wpdb->usermeta} WHERE meta_key LIKE %s", $wpdb->esc_like( '_vibono_' ) . '%' ) );
}
