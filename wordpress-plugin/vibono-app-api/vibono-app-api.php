<?php
/**
 * Plugin Name:       Vibono App API & Punkte
 * Description:       REST-Schnittstelle für die App "Vibono" (Login, Zwei-Wege-Synchronisation mit MyVibono, Coaching-Tagesansicht) und zentrales Punktesystem für App und WooCommerce-Shop.
 * Version:           1.0.0
 * Requires at least: 6.2
 * Requires PHP:      8.1
 * Author:            Vibono GmbH
 * Text Domain:       vibono-app-api
 * License:           Proprietär
 */

defined( 'ABSPATH' ) || exit;

define( 'VIBONO_API_VERSION', '1.0.0' );
define( 'VIBONO_API_DB_VERSION', '3' );
define( 'VIBONO_API_FILE', __FILE__ );
define( 'VIBONO_API_DIR', plugin_dir_path( __FILE__ ) );
define( 'VIBONO_API_URL', plugin_dir_url( __FILE__ ) );
define( 'VIBONO_API_NS', 'vibono/v1' );

spl_autoload_register(
	static function ( $class ) {
		$prefix = 'Vibono\\AppApi\\';
		if ( strncmp( $class, $prefix, strlen( $prefix ) ) !== 0 ) {
			return;
		}
		$relative = substr( $class, strlen( $prefix ) );
		$file     = VIBONO_API_DIR . 'includes/' . str_replace( '\\', '/', $relative ) . '.php';
		if ( is_readable( $file ) ) {
			require_once $file;
		}
	}
);

register_activation_hook( __FILE__, array( 'Vibono\\AppApi\\Install', 'activate' ) );
register_deactivation_hook( __FILE__, array( 'Vibono\\AppApi\\Install', 'deactivate' ) );

add_action( 'plugins_loaded', array( 'Vibono\\AppApi\\Plugin', 'boot' ) );
