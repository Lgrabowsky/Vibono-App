<?php
/**
 * Rahmen der Testumgebung: E-Mails abfangen, Links auf die lokale Seite umbiegen, Hinweise im Backend,
 * WooCommerce ruhigstellen, Bildauswertung ohne Claude-Schlüssel simulieren.
 */

defined( 'ABSPATH' ) || exit;

// ------------------------------------------------------------------ E-Mails
// Es gibt keinen Mailserver. Alle Mails (Passwort vergessen, Bestellbestätigung …) landen in der Testzentrale.
add_filter(
	'pre_wp_mail',
	static function ( $null, $atts ) {
		$list = get_option( 'vt_mails', array() );
		array_unshift(
			$list,
			array(
				'id'      => wp_generate_password( 10, false ),
				'at'      => time(),
				'to'      => implode( ', ', (array) $atts['to'] ),
				'subject' => (string) $atts['subject'],
				'message' => (string) $atts['message'],
				'html'    => false !== stripos( implode( "\n", (array) $atts['headers'] ), 'text/html' ) || false !== stripos( (string) $atts['message'], '<html' ),
			)
		);
		update_option( 'vt_mails', array_slice( $list, 0, 50 ), false );
		return true;
	},
	10,
	2
);
// WooCommerce verschickt HTML-Mails über einen eigenen Header-Filter.
add_filter( 'wp_mail_content_type', static fn( $t ) => $t );

// ------------------------------------------------------ Links und Einstellungen
// Links, die die App aus GET /config bekommt, zeigen auf diese Testseite statt auf vibono.de.
add_filter(
	'vibono_api_setting',
	static function ( $value, $key ) {
		switch ( $key ) {
			case 'shop_url':
				return home_url( '/shop/' );
			case 'support_url':
			case 'privacy_url':
				return home_url( '/' );
		}
		return $value;
	},
	10,
	2
);

// ---------------------------------------------------------------- Backend
add_action(
	'admin_notices',
	static function () {
		echo '<div class="notice notice-info"><p><strong>Vibono-Testumgebung</strong> – läuft nur auf diesem Rechner, keine Verbindung zu vibono.de. '
			. '<a href="' . esc_url( home_url( '/testzentrale/' ) ) . '">Zur Testzentrale</a></p></div>';
	}
);
add_action(
	'admin_bar_menu',
	static function ( $bar ) {
		$bar->add_node(
			array(
				'id'    => 'vt-testzentrale',
				'title' => '🧪 Testzentrale',
				'href'  => home_url( '/testzentrale/' ),
			)
		);
	},
	100
);
add_action(
	'admin_menu',
	static function () {
		add_menu_page( 'Testzentrale', 'Testzentrale', 'read', 'vt-testzentrale', '__return_null', 'dashicons-admin-tools', 2 );
	}
);
add_action(
	'admin_init',
	static function () {
		if ( isset( $_GET['page'] ) && 'vt-testzentrale' === $_GET['page'] ) { // phpcs:ignore
			wp_safe_redirect( home_url( '/testzentrale/' ) );
			exit;
		}
	}
);

// Anmeldeseite: Zugangsdaten anzeigen.
add_filter(
	'login_message',
	static function ( $m ) {
		return $m . '<p class="message">Testumgebung: Benutzer <strong>admin</strong>, Passwort <strong>vibono-test</strong>. Testkonten (anna@vibono-test.local …) haben dasselbe Passwort.</p>';
	}
);

// ------------------------------------------------- Keine Update-Prüfung
// Die Testumgebung soll nichts aus dem Internet laden (und nicht bei wordpress.org nachfragen).
foreach ( array( 'update_core', 'update_plugins', 'update_themes' ) as $vt_transient ) {
	add_filter(
		'pre_site_transient_' . $vt_transient,
		static fn() => (object) array( 'last_checked' => time(), 'version_checked' => get_bloginfo( 'version' ), 'updates' => array(), 'response' => array(), 'translations' => array(), 'checked' => array() )
	);
}
remove_action( 'admin_init', '_maybe_update_core' );
remove_action( 'admin_init', '_maybe_update_plugins' );
remove_action( 'admin_init', '_maybe_update_themes' );
remove_action( 'init', 'wp_schedule_update_checks' );
add_filter( 'pre_http_request', static function ( $pre, $args, $url ) {
	$host = (string) wp_parse_url( $url, PHP_URL_HOST );
	// Alles außer dieser Testseite und der Claude API wird ohne Netzwerkzugriff abgelehnt.
	if ( '' !== $host && ! in_array( $host, array( 'localhost', '127.0.0.1', 'api.anthropic.com', (string) wp_parse_url( home_url(), PHP_URL_HOST ) ), true ) ) {
		return new WP_Error( 'vt_offline', 'Testumgebung: keine Verbindung nach außen (' . $host . ').' );
	}
	return $pre;
}, 1, 3 );

// Browser soll nichts von außen nachladen: keine Gravatar-Bilder, keine Emoji-Grafiken von wordpress.org.
add_filter( 'get_avatar_url', static fn() => includes_url( 'images/blank.gif' ) );
add_filter( 'emoji_svg_url', '__return_false' );
remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
remove_action( 'wp_print_styles', 'print_emoji_styles' );
add_action(
	'admin_init',
	static function () {
		remove_action( 'admin_print_scripts', 'print_emoji_detection_script' );
		remove_action( 'admin_print_styles', 'print_emoji_styles' );
	}
);

// ------------------------------------------------------------- WooCommerce
add_filter( 'woocommerce_allow_marketplace_suggestions', '__return_false' );
add_filter( 'woocommerce_show_marketplace_suggestions', '__return_false' );
add_filter( 'woocommerce_admin_onboarding_task_list_enabled', '__return_false' );
add_filter( 'woocommerce_prevent_automatic_wizard_redirect', '__return_true' );
add_filter( 'woocommerce_enable_setup_wizard', '__return_false' );
add_filter( 'woocommerce_background_image_regeneration', '__return_false' );
// Kein paralleler Hintergrund-Aufruf: Der eingebaute PHP-Server bearbeitet nur eine Anfrage gleichzeitig.
add_filter( 'action_scheduler_allow_async_request_runner', '__return_false' );
add_filter( 'woocommerce_defer_transactional_emails', '__return_false' );

// ------------------------------------------------- Stündliche Aufgaben des Plugins
// WP-Cron ist abgeschaltet (siehe wp-config.php). Die stündliche Aufgabe des Plugins (vorgemerkte Punkte
// bestätigen, Lese-Sessions aufräumen) läuft beim Aufruf der Testzentrale, höchstens einmal pro Stunde,
// und jederzeit per Knopf.
function vt_stuendliche_aufgaben( $erzwingen = false ) {
	$last = (int) get_option( 'vt_cron_last', 0 );
	if ( ! $erzwingen && time() - $last < HOUR_IN_SECONDS ) {
		return false;
	}
	update_option( 'vt_cron_last', time(), false );
	do_action( 'vibono_points_daily' );
	return true;
}

// ---------------------------------------------- Bildauswertung ohne Schlüssel
// Ohne Claude-Schlüssel antwortet das Plugin mit "nicht verfügbar". Damit Foto-Schätzung und Rezept-Scan
// trotzdem ausprobiert werden können, liefert die Testumgebung dann eine deutlich markierte Beispiel-Antwort.
// Die Bildprüfung (Format, Größe) läuft trotzdem durch das Plugin.
add_filter(
	'rest_pre_dispatch',
	static function ( $result, $server, $request ) {
		$route = $request->get_route();
		if ( ! in_array( $route, array( '/vibono/v1/energy-density/analyze-photo', '/vibono/v1/energy-density/scan-recipe' ), true ) ) {
			return $result;
		}
		if ( ! class_exists( 'Vibono\\AppApi\\Settings' ) || '' !== \Vibono\AppApi\Settings::anthropic_key() || ! get_current_user_id() ) {
			return $result;
		}
		$img = \Vibono\AppApi\Vision::check_image( (string) $request['image_base64'], (string) $request['mime'] );
		if ( is_wp_error( $img ) ) {
			return $img;
		}
		if ( str_ends_with( $route, 'analyze-photo' ) ) {
			return rest_ensure_response(
				\Vibono\AppApi\Vision::finish_photo(
					array(
						'dish'       => 'Gemüsepfanne mit Reis (Beispiel)',
						'portion_g'  => 400,
						'kcal_total' => 440,
						'components' => array(
							array( 'name' => 'Gemüse', 'share_pct' => 55 ),
							array( 'name' => 'Reis', 'share_pct' => 35 ),
							array( 'name' => 'Öl und Soße', 'share_pct' => 10 ),
						),
						'confidence' => 0.5,
						'notes'      => 'Simulation der Testumgebung: kein Claude-Schlüssel hinterlegt, das Foto wurde nicht ausgewertet.',
					)
				) + array( 'simulation' => 'Testumgebung ohne Claude-Schlüssel: Beispielwerte, das Foto wurde nicht ausgewertet.' )
			);
		}
		return rest_ensure_response(
			\Vibono\AppApi\Vision::finish_recipe(
				array(
					'title'       => 'Linsen-Gemüse-Suppe (Beispiel)',
					'servings'    => 4,
					'ingredients' => array(
						array( 'name' => 'Rote Linsen', 'raw_text' => '200 g rote Linsen', 'amount_g' => 200, 'kcal_per_100g' => 330, 'confidence' => 0.9 ),
						array( 'name' => 'Karotten', 'raw_text' => '3 Karotten', 'amount_g' => 240, 'kcal_per_100g' => 36, 'confidence' => 0.7 ),
						array( 'name' => 'Zwiebel', 'raw_text' => '1 Zwiebel', 'amount_g' => 80, 'kcal_per_100g' => 28, 'confidence' => 0.8 ),
						array( 'name' => 'Gemüsebrühe', 'raw_text' => '1 l Gemüsebrühe', 'amount_g' => 1000, 'kcal_per_100g' => 5, 'confidence' => 0.9 ),
						array( 'name' => 'Olivenöl', 'raw_text' => '1 EL Olivenöl', 'amount_g' => 10, 'kcal_per_100g' => 884, 'confidence' => 0.8 ),
						array( 'name' => 'Gewürze', 'raw_text' => 'Salz, Pfeffer, Kreuzkümmel', 'amount_g' => null, 'kcal_per_100g' => null, 'confidence' => 0.3 ),
					),
				)
			) + array( 'simulation' => 'Testumgebung ohne Claude-Schlüssel: Beispielwerte, das Bild wurde nicht ausgewertet.' )
		);
	},
	10,
	3
);

// ------------------------------------------------- Demo-Serie frisch halten
// Die Datenbank wird beim Bauen eingerichtet. Startet jemand die Testumgebung ein paar Tage später (oder nach
// Zuruecksetzen.bat), wären die vorbereiteten Serien (z. B. Anna: 6 Tage bis gestern) sonst schon gerissen.
// Beim ersten Aufruf rücken deshalb die Serien und die Öffnen-Buchungen um die vergangenen Tage nach.
add_action(
	'init',
	static function () {
		if ( 'cli' === PHP_SAPI ) {
			return; // Beim Bauen nicht, erst beim ersten echten Aufruf.
		}
		$gebaut = (string) get_option( 'vt_demo_datum', '' );
		if ( '' === $gebaut || ! class_exists( 'Vibono\\AppApi\\Streak' ) ) {
			return;
		}
		delete_option( 'vt_demo_datum' );
		$tage = \Vibono\AppApi\Core\StreakMath::days_between( $gebaut, \Vibono\AppApi\Plugin::today() );
		if ( $tage <= 0 || $tage > 3650 ) {
			return;
		}
		global $wpdb;
		$t = \Vibono\AppApi\Install::table( 'points_ledger' );
		$wpdb->query( $wpdb->prepare( "UPDATE $t SET created_at = DATE_ADD(created_at, INTERVAL %d DAY) WHERE reason = 'app_open'", $tage ) ); // phpcs:ignore
		foreach ( (array) $wpdb->get_results( $wpdb->prepare( "SELECT user_id, meta_value FROM {$wpdb->usermeta} WHERE meta_key = %s", \Vibono\AppApi\Streak::META ) ) as $row ) {
			$s = maybe_unserialize( $row->meta_value );
			if ( is_array( $s ) && ! empty( $s['last_date'] ) ) {
				$s['last_date'] = ( new DateTimeImmutable( $s['last_date'] ) )->modify( "+$tage day" )->format( 'Y-m-d' );
				update_user_meta( (int) $row->user_id, \Vibono\AppApi\Streak::META, $s );
			}
		}
	},
	1
);
