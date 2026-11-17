<?php
/**
 * Vibono-Testumgebung: WordPress-Konfiguration.
 * Läuft nur auf diesem Rechner mit einer SQLite-Datei, ohne Verbindung zu vibono.de.
 */

// Datenbank: SQLite-Datei unter wp-content/database/ (kein MySQL nötig).
define( 'DB_NAME', 'vibono_test' );
define( 'DB_USER', '' );
define( 'DB_PASSWORD', '' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );
define( 'DB_DIR', __DIR__ . '/wp-content/database/' );
define( 'DB_FILE', '.ht.sqlite' );
$table_prefix = 'wp_';

// Adresse folgt dem Aufruf: http://localhost:8080 am PC, http://192.168.x.x:8080 vom Handy.
$vibono_host = isset( $_SERVER['HTTP_HOST'] ) && preg_match( '/^[A-Za-z0-9.\-:\[\]]+$/', $_SERVER['HTTP_HOST'] ) ? $_SERVER['HTTP_HOST'] : 'localhost:8080';
define( 'WP_HOME', 'http://' . $vibono_host );
define( 'WP_SITEURL', 'http://' . $vibono_host );

// Schlüssel nur für diese Testumgebung (beim Bauen zufällig erzeugt).
__SALTS__
define( 'VIBONO_JWT_SECRET', '__JWT__' );

// Abschottung: keine Verbindungen nach außen (also auch nicht zu vibono.de).
// Ausnahme: die Claude API für den Energiedichte-Rechner, falls ein Schlüssel eingetragen wird.
define( 'WP_HTTP_BLOCK_EXTERNAL', true );
define( 'WP_ACCESSIBLE_HOSTS', 'api.anthropic.com' );
define( 'AUTOMATIC_UPDATER_DISABLED', true );
define( 'WP_AUTO_UPDATE_CORE', false );
define( 'DISALLOW_FILE_MODS', true );
define( 'DISABLE_WP_CRON', true ); // Zeitgesteuerte Aufgaben startet die Testzentrale per Knopf.
define( 'WP_ENVIRONMENT_TYPE', 'local' );
define( 'VIBONO_TESTUMGEBUNG', true );

// Fehler in eine Datei schreiben statt auf die Seite.
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_DISPLAY', false );
define( 'WP_DEBUG_LOG', __DIR__ . '/wp-content/fehlerprotokoll.log' );
define( 'WP_MEMORY_LIMIT', '256M' );

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
