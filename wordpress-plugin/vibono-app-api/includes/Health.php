<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Systemprüfung für die Anbindung an vibono.de. Wird im Backend (Module & Anbindung) und per
 * "wp vibono check" angezeigt. Prüft nur, ändert nichts.
 */
class Health {

	/** @return array<int, array{label:string,status:string,detail:string}> status: ok|warn|error|info */
	public static function checks(): array {
		global $wpdb;
		$out = array();
		$add = static function ( string $label, string $status, string $detail = '' ) use ( &$out ) {
			$out[] = array( 'label' => $label, 'status' => $status, 'detail' => $detail );
		};

		// --- Grundlagen -----------------------------------------------------
		$add( 'Notabschaltung', defined( 'VIBONO_API_DISABLE' ) && VIBONO_API_DISABLE ? 'warn' : 'ok', defined( 'VIBONO_API_DISABLE' ) && VIBONO_API_DISABLE ? 'VIBONO_API_DISABLE ist gesetzt, das Plugin ist ohne Funktion.' : 'nicht gesetzt' );
		$add( 'JWT-Geheimnis', defined( 'VIBONO_JWT_SECRET' ) && strlen( (string) VIBONO_JWT_SECRET ) >= 32 ? 'ok' : 'warn', defined( 'VIBONO_JWT_SECRET' ) ? ( strlen( (string) VIBONO_JWT_SECRET ) >= 32 ? 'aus wp-config.php' : 'zu kurz, mindestens 32 Zeichen' ) : 'Automatisch erzeugt und in der Datenbank gespeichert. Empfohlen: VIBONO_JWT_SECRET in wp-config.php.' );
		$add( 'HTTPS', 0 === strpos( home_url(), 'https://' ) ? 'ok' : 'error', home_url() );
		$add( 'Permalinks', get_option( 'permalink_structure' ) ? 'ok' : 'error', get_option( 'permalink_structure' ) ? 'sprechende Permalinks aktiv' : 'Einfache Permalinks: /wp-json/ ist nicht erreichbar.' );

		$missing = array();
		foreach ( array( 'tokens', 'sync', 'points_ledger', 'campaigns', 'reading', 'devices' ) as $t ) {
			if ( Install::table( $t ) !== $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', Install::table( $t ) ) ) ) {
				$missing[] = Install::table( $t );
			}
		}
		$add( 'Datenbanktabellen', $missing ? 'error' : 'ok', $missing ? 'fehlen: ' . implode( ', ', $missing ) . ' (Plugin einmal deaktivieren und aktivieren)' : '6 Tabellen vorhanden' );

		$cron = wp_next_scheduled( 'vibono_points_daily' );
		$add( 'Cron (Punkte bestätigen)', $cron ? 'ok' : 'warn', $cron ? 'nächster Lauf ' . wp_date( 'd.m.Y H:i', $cron ) . ( defined( 'DISABLE_WP_CRON' ) && DISABLE_WP_CRON ? ' (WP-Cron aus: System-Cron muss wp-cron.php aufrufen)' : '' ) : 'nicht geplant (Plugin einmal deaktivieren und aktivieren)' );

		$err = get_transient( Plugin::LAST_ERROR );
		$add( 'Abgefangene Fehler (7 Tage)', $err ? 'warn' : 'ok', $err ? wp_date( 'd.m.Y H:i', (int) $err['at'] ) . ' – ' . $err['message'] : 'keine' );

		// --- Shop -----------------------------------------------------------
		$wc = class_exists( 'WooCommerce' );
		$add( 'WooCommerce', $wc ? 'ok' : ( Settings::on( 'module_shop' ) ? 'error' : 'info' ), $wc ? 'Version ' . ( defined( 'WC_VERSION' ) ? WC_VERSION : '?' ) : 'nicht aktiv' );
		$add( 'WooCommerce Memberships', function_exists( 'wc_memberships' ) ? 'ok' : 'warn', function_exists( 'wc_memberships' ) ? 'aktiv' : 'nicht aktiv: gesperrte Coaching-Inhalte können nicht geprüft werden' );
		if ( $wc && Settings::on( 'module_shop' ) ) {
			$add( 'Gutscheine in WooCommerce', function_exists( 'wc_coupons_enabled' ) && wc_coupons_enabled() ? 'ok' : 'error', 'Das Einlösen nutzt einen virtuellen Gutschein „' . WooCommerce::COUPON . '“. Gutscheine müssen aktiviert sein.' );
			$clash = function_exists( 'wc_get_coupon_id_by_code' ) ? wc_get_coupon_id_by_code( WooCommerce::COUPON ) : 0;
			$add( 'Gutschein-Code frei', $clash ? 'error' : 'ok', $clash ? 'Es gibt bereits einen echten Gutschein „' . WooCommerce::COUPON . '“ (ID ' . $clash . ').' : 'kein echter Gutschein mit diesem Code' );
			$cart_page = function_exists( 'wc_get_page_id' ) ? wc_get_page_id( 'cart' ) : 0;
			$blocks    = $cart_page > 0 && has_block( 'woocommerce/cart', $cart_page );
			$add( 'Warenkorb-Seite', $blocks ? 'warn' : 'ok', $blocks ? 'Block-Warenkorb: Das Einlösefeld erscheint nur im klassischen Warenkorb ([woocommerce_cart]).' : 'klassischer Warenkorb' );
		}

		// --- Empfehlungen ---------------------------------------------------
		$raf = Referral::legacy_plugin_active();
		if ( Settings::on( 'module_referral' ) ) {
			$add( 'Refer a Friend', $raf ? 'warn' : 'ok', $raf ? 'Noch aktiv. Das Punktesystem wertet jetzt auch alte ?raf-Links aus: In Refer a Friend die Belohnungen abschalten (sonst doppelte Prämien) und nach 30 Tagen deaktivieren.' : 'abgeschaltet, alte ?raf-Links laufen über das Punktesystem' );
		} else {
			$add( 'Refer a Friend', 'info', $raf ? 'aktiv; Modul „Freunde werben“ ist aus, es gibt keine Überschneidung' : 'nicht aktiv' );
		}

		// --- MyVibono -------------------------------------------------------
		$keys = array();
		foreach ( array( 'favorites', 'lessons_done', 'courses_done', 'weight', 'sport', 'weekplan' ) as $c ) {
			if ( Settings::get( 'store_' . $c . '_meta' ) ) {
				$keys[] = $c;
			}
		}
		$mode = Settings::on( 'myvibono_write' ) ? 'lesen und schreiben' : 'nur lesen';
		$add( 'MyVibono-Speicherorte', $keys ? 'ok' : 'info', $keys ? count( $keys ) . ' von 6 eingetragen (' . implode( ', ', $keys ) . '), ' . $mode : 'keine eingetragen: App-Daten liegen nur im Plugin, die Website sieht sie nicht' );

		// --- Energiedichte --------------------------------------------------
		$key = '' !== Settings::anthropic_key();
		$sdk = is_readable( VIBONO_API_DIR . 'vendor/autoload.php' );
		$add( 'Bildauswertung (Energiedichte)', $key && $sdk ? 'ok' : 'info', ( $key ? 'Schlüssel hinterlegt' : 'kein Schlüssel' ) . ', ' . ( $sdk ? 'SDK installiert' : 'SDK fehlt (composer install --no-dev)' ) . '. Ohne beides funktioniert alles außer Rezept-Scan und Foto.' );

		return $out;
	}
}
