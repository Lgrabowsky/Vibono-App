<?php
/**
 * Liefert die Testzentrale unter /testzentrale/ aus: eine Seite, die die Schnittstelle so aufruft wie die App
 * (Anmeldung mit Token, dann /wp-json/vibono/v1/...), plus die Testhelfer.
 * CSS und JavaScript werden eingebettet, damit der Browser nur eine Anfrage stellt
 * (der eingebaute PHP-Server bearbeitet Anfragen nacheinander).
 */

defined( 'ABSPATH' ) || exit;

add_action(
	'init',
	static function () {
		$path = (string) wp_parse_url( $_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH ); // phpcs:ignore
		if ( ! preg_match( '#^/testzentrale/?$#', $path ) ) {
			return;
		}
		if ( '/testzentrale' === $path ) {
			wp_safe_redirect( home_url( '/testzentrale/' ) );
			exit;
		}
		$dir    = VT_DIR . 'testzentrale/';
		$config = array(
			'api'     => rest_url( 'vibono/v1' ),
			'test'    => rest_url( 'vibono-test/v1' ),
			'home'    => home_url( '/' ),
			'plugin'  => class_exists( 'Vibono\\AppApi\\Points' ),
		);
		$html = (string) file_get_contents( $dir . 'index.html' );
		$html = str_replace(
			array( '/*__CSS__*/', '/*__CONFIG__*/', '/*__JS__*/' ),
			array( (string) file_get_contents( $dir . 'stil.css' ), 'window.VT = ' . wp_json_encode( $config ) . ';', (string) file_get_contents( $dir . 'app.js' ) ),
			$html
		);
		nocache_headers();
		header( 'Content-Type: text/html; charset=utf-8' );
		echo $html; // phpcs:ignore
		exit;
	},
	2
);
