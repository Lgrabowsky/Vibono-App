<?php
/**
 * Richtet die Testumgebung beim Bauen ein (wird von build.sh mit dem PHP des Build-Rechners aufgerufen).
 *
 *   php einrichten.php install    <wordpress-ordner>   WordPress mit SQLite installieren
 *   php einrichten.php aktivieren <wordpress-ordner>   SQLite, WooCommerce und vibono-app-api aktivieren, Shop einstellen
 *   php einrichten.php demodaten  <wordpress-ordner>   Inhalte, Produkte, Testkonten, Punkte, Aktionen anlegen
 *
 * Jeder Schritt läuft in einem eigenen Prozess, damit WordPress die frisch aktivierten Plugins
 * wie bei einem normalen Seitenaufruf lädt.
 */

if ( PHP_SAPI !== 'cli' || $argc < 3 ) {
	exit( "Aufruf: php einrichten.php install|aktivieren|demodaten <wordpress-ordner>\n" );
}
list( , $step, $wp_dir ) = $argv;

$_SERVER['HTTP_HOST']       = 'localhost:8080';
$_SERVER['SERVER_NAME']     = 'localhost';
$_SERVER['SERVER_PORT']     = '8080';
$_SERVER['REQUEST_URI']     = '/';
$_SERVER['REQUEST_METHOD']  = 'GET';
$_SERVER['SERVER_PROTOCOL'] = 'HTTP/1.1';
$_SERVER['REMOTE_ADDR']     = '127.0.0.1';
define( 'VIBONO_TESTUMGEBUNG_SETUP', true );

if ( 'install' === $step ) {
	define( 'WP_INSTALLING', true );
	require $wp_dir . '/wp-load.php';
	require_once ABSPATH . 'wp-admin/includes/upgrade.php';
	$r = wp_install( 'Vibono Testumgebung', 'admin', 'admin@vibono-test.local', false, '', 'vibono-test' );
	update_option( 'permalink_structure', '/%postname%/' );
	update_option( 'timezone_string', 'Europe/Berlin' );
	update_option( 'date_format', 'j. F Y' );
	update_option( 'time_format', 'H:i' );
	update_option( 'start_of_week', 1 );
	update_option( 'blogdescription', 'Lokale Testumgebung für das Plugin „Vibono App API & Punkte“ – ohne Verbindung zu vibono.de' );
	update_option( 'default_role', 'subscriber' );
	update_option( 'users_can_register', 1 );
	update_option( 'blog_public', 0 );
	update_option( 'default_comment_status', 'closed' );
	wp_delete_post( 1, true ); // "Hallo Welt"
	wp_delete_post( 2, true ); // Beispielseite
	wp_delete_post( 3, true ); // Datenschutz-Entwurf
	echo "  WordPress installiert (Benutzer admin)\n";
	exit( 0 );
}

require $wp_dir . '/wp-load.php';
require_once ABSPATH . 'wp-admin/includes/plugin.php';
require_once ABSPATH . 'wp-admin/includes/admin.php';

if ( 'aktivieren' === $step ) {
	foreach ( array( 'sqlite-database-integration/load.php', 'woocommerce/woocommerce.php', 'vibono-app-api/vibono-app-api.php' ) as $plugin ) {
		$res = activate_plugin( $plugin );
		if ( is_wp_error( $res ) ) {
			fwrite( STDERR, "Fehler beim Aktivieren von $plugin: " . $res->get_error_message() . "\n" );
			exit( 1 );
		}
		echo "  aktiviert: $plugin\n";
	}
	// Alle Module an, damit jede Funktion ausprobiert werden kann (im Backend unter „Module & Anbindung“ abschaltbar).
	// Muss vor den Demodaten passieren: Das Plugin registriert seine Shop-Hooks beim Start nur für eingeschaltete Module.
	\Vibono\AppApi\Settings::update(
		array(
			'module_api'         => true,
			'module_shop'        => true,
			'module_referral'    => true,
			'module_web_reading' => true,
			'myvibono_write'     => false,
		)
	);
	exit( 0 );
}

if ( 'demodaten' === $step ) {
	if ( ! class_exists( 'WooCommerce' ) || ! class_exists( 'Vibono\\AppApi\\Points' ) ) {
		fwrite( STDERR, "WooCommerce oder vibono-app-api ist nicht geladen.\n" );
		exit( 1 );
	}
	require __DIR__ . '/demodaten.php';
	vt_demodaten_anlegen();
	exit( 0 );
}

fwrite( STDERR, "Unbekannter Schritt: $step\n" );
exit( 1 );
