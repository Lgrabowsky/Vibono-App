<?php
/**
 * Plugin Name: Vibono-Testumgebung
 * Description: Nur für die lokale Testumgebung. Stellt nach, was auf vibono.de das Theme und kostenpflichtige Plugins liefern (Inhaltstypen, WooCommerce Memberships), fängt E-Mails ab und liefert die Testzentrale unter /testzentrale/. Niemals auf vibono.de installieren.
 * Version: 1.0.0
 */

defined( 'ABSPATH' ) || exit;

// Läuft nur, wenn wp-config.php die Testumgebung kennzeichnet.
if ( ! defined( 'VIBONO_TESTUMGEBUNG' ) || ! VIBONO_TESTUMGEBUNG ) {
	return;
}

define( 'VT_DIR', __DIR__ . '/vibono-testumgebung/' );

require VT_DIR . 'inhaltstypen.php';
require VT_DIR . 'mitgliedschaften.php';
require VT_DIR . 'umgebung.php';
require VT_DIR . 'helfer.php';
require VT_DIR . 'testzentrale.php';
