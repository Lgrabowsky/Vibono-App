<?php
/**
 * Router für den eingebauten PHP-Webserver (php -S). Entspricht dem Router von "wp server":
 * Vorhandene Dateien direkt ausliefern, alles andere an WordPress (index.php) geben,
 * damit schöne Adressen wie /wp-json/vibono/v1/... funktionieren.
 */
$root = $_SERVER['DOCUMENT_ROOT'];
$path = '/' . ltrim( (string) parse_url( urldecode( $_SERVER['REQUEST_URI'] ), PHP_URL_PATH ), '/' );

// Datenbank, Protokolle und versteckte Dateien nie ausliefern.
if ( preg_match( '#/\.ht|/wp-content/database/|/wp-config\.php$|\.(log|sqlite)$#i', $path ) ) {
	http_response_code( 403 );
	exit( 'Verboten' );
}

if ( file_exists( $root . $path ) ) {
	if ( is_dir( $root . $path ) && substr( $path, -1 ) !== '/' ) {
		header( 'Location: ' . $path . '/' );
		exit;
	}
	if ( strpos( $path, '.php' ) !== false ) {
		chdir( dirname( $root . $path ) );
		require_once $root . $path;
		return true;
	}
	return false;
}

chdir( $root );
require_once $root . '/index.php';
