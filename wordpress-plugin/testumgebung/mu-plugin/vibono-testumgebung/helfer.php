<?php
/**
 * Testhelfer für die Testzentrale (REST unter /wp-json/vibono-test/v1/).
 *
 * Sie stellen nach, was im echten Betrieb von außen passiert (Kund*in bestellt, Zeit vergeht, Mitgliedschaft
 * wird gekauft) und rufen dafür dieselben WooCommerce- und Plugin-Funktionen auf wie der Live-Betrieb.
 * Die Punkte selbst bucht immer das Plugin. Diese Helfer gibt es nur in der Testumgebung.
 */

defined( 'ABSPATH' ) || exit;

use Vibono\AppApi\Campaigns;
use Vibono\AppApi\Install;
use Vibono\AppApi\Plugin;
use Vibono\AppApi\Points;
use Vibono\AppApi\Profile;
use Vibono\AppApi\Referral;
use Vibono\AppApi\Settings;

const VT_NS = 'vibono-test/v1';

// ------------------------------------------------------------------ Funktionen

/** Adressen, unter denen andere Geräte im WLAN die Testumgebung erreichen. */
function vt_adressen() {
	$port = (int) ( $_SERVER['SERVER_PORT'] ?? 8080 );
	$port = $port ?: 8080;
	$ips  = array();
	$host = gethostname();
	foreach ( (array) ( $host ? gethostbynamel( $host ) : array() ) as $ip ) {
		if ( filter_var( $ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4 ) && 0 !== strpos( $ip, '127.' ) && 0 !== strpos( $ip, '169.254.' ) ) {
			$ips[] = $ip;
		}
	}
	$out = array( 'pc' => 'http://localhost:' . $port );
	foreach ( array_unique( $ips ) as $ip ) {
		$out['wlan'][] = 'http://' . $ip . ':' . $port;
	}
	return $out;
}

function vt_nutzer( $u ) {
	$u   = $u instanceof WP_User ? $u : get_userdata( (int) $u );
	$by  = (int) get_user_meta( $u->ID, Referral::BY_META, true );
	$g   = Profile::goals( $u->ID );
	return array(
		'id'                 => $u->ID,
		'name'               => $u->first_name ?: $u->display_name,
		'email'              => $u->user_email,
		'login'              => $u->user_login,
		'rolle'              => implode( ', ', $u->roles ),
		'admin'              => user_can( $u, 'manage_options' ),
		'mitglied'           => vt_ist_mitglied( $u->ID ),
		'punkte'             => Points::balance( $u->ID ),
		'vorgemerkt'         => Points::pending( $u->ID ),
		'empfehlungscode'    => Referral::code_for( $u->ID ),
		'geworben_von'       => $by ? ( get_userdata( $by )->first_name ?? '' ) : null,
		'coaching_start'     => $g['coaching_start_date'],
		'beschreibung'       => (string) get_user_meta( $u->ID, '_vt_beschreibung', true ),
		'testpasswort'       => '' !== (string) get_user_meta( $u->ID, '_vt_testpasswort', true ) ? (string) get_user_meta( $u->ID, '_vt_testpasswort', true ) : null,
	);
}

/**
 * Bestellung wie aus dem Shop anlegen: Kundenkonto, Rechnungsadresse aus dem Konto, Zahlart Nachnahme.
 * Löst dieselben Hooks aus wie die Kasse (Bestellung angelegt → bezahlt/in Bearbeitung).
 *
 * @param array $positionen [ [product_id, menge] ] oder leer, dann $betrag_cent als Testartikel.
 * @param array $adresse    Optional [Straße, PLZ, Ort] statt der Adresse aus dem Konto (z. B. um Selbstwerbung zu testen).
 */
function vt_bestellung_anlegen( $user_id, $positionen = array(), $betrag_cent = 0, $status = 'processing', $adresse = array() ) {
	$user = get_userdata( (int) $user_id );
	if ( ! $user ) {
		return new WP_Error( 'vt_user', 'Konto nicht gefunden.' );
	}
	$order = wc_create_order( array( 'customer_id' => $user->ID, 'created_via' => 'checkout' ) );
	if ( is_wp_error( $order ) ) {
		return $order;
	}
	if ( $positionen ) {
		foreach ( $positionen as $p ) {
			$product = wc_get_product( (int) $p['product_id'] );
			if ( $product ) {
				$order->add_product( $product, max( 1, (int) ( $p['menge'] ?? 1 ) ) );
			}
		}
	} else {
		$product = wc_get_product( (int) get_option( 'vt_testartikel_id' ) );
		if ( ! $product || $betrag_cent <= 0 ) {
			return new WP_Error( 'vt_betrag', 'Bitte einen Betrag oder Produkte angeben.' );
		}
		$euro = round( $betrag_cent / 100, 2 );
		$item = new WC_Order_Item_Product();
		$item->set_props( array( 'product' => $product, 'quantity' => 1, 'subtotal' => $euro, 'total' => $euro ) );
		$item->set_name( sprintf( 'Testeinkauf (%s €)', number_format( $euro, 2, ',', '.' ) ) );
		$order->add_item( $item );
	}
	$c = new WC_Customer( $user->ID );
	$order->set_billing_first_name( $c->get_billing_first_name() ?: $user->first_name );
	$order->set_billing_last_name( $c->get_billing_last_name() ?: 'Test' );
	$order->set_billing_email( $user->user_email );
	$order->set_billing_address_1( $c->get_billing_address_1() ?: 'Teststraße ' . $user->ID );
	$order->set_billing_postcode( $c->get_billing_postcode() ?: sprintf( '1%04d', $user->ID ) );
	$order->set_billing_city( $c->get_billing_city() ?: 'Teststadt' );
	$order->set_billing_country( 'DE' );
	if ( count( $adresse ) >= 3 ) {
		$order->set_billing_address_1( sanitize_text_field( $adresse[0] ) );
		$order->set_billing_postcode( sanitize_text_field( $adresse[1] ) );
		$order->set_billing_city( sanitize_text_field( $adresse[2] ) );
	}
	$order->set_payment_method( 'cod' );
	$order->set_payment_method_title( 'Nachnahme (Test)' );
	$order->calculate_totals( false );
	$order->save();
	// Wie die Kasse: Empfehlung zuordnen, eingelöste Punkte abbuchen (Hook des Plugins).
	do_action( 'woocommerce_checkout_order_created', $order );
	if ( $status && 'pending' !== $status ) {
		$order->update_status( $status, 'Testumgebung: simulierte Bestellung.' );
	}
	return wc_get_order( $order->get_id() );
}

function vt_bestellung( $order ) {
	global $wpdb;
	$t    = Install::table( 'points_ledger' );
	$rows = $wpdb->get_results( $wpdb->prepare( "SELECT user_id, points, reason, status FROM $t WHERE ref_type = 'order' AND ref_id = %d ORDER BY id", $order->get_id() ), ARRAY_A );
	return array(
		'id'         => $order->get_id(),
		'nummer'     => $order->get_order_number(),
		'kunde'      => $order->get_billing_first_name(),
		'kunde_id'   => $order->get_customer_id(),
		'summe'      => (float) $order->get_total(),
		'eingeloest' => (int) $order->get_meta( '_vibono_points_redeemed' ),
		'status'     => $order->get_status(),
		'status_text'=> wc_get_order_status_name( $order->get_status() ),
		'datum'      => $order->get_date_created() ? $order->get_date_created()->date_i18n( 'd.m.Y H:i' ) : '',
		'positionen' => array_values( array_map( static fn( $i ) => $i->get_quantity() . ' × ' . $i->get_name(), $order->get_items() ) ),
		'punkte'     => array_map(
			static function ( $r ) {
				$u = get_userdata( (int) $r['user_id'] );
				return array( 'wer' => $u ? ( $u->first_name ?: $u->display_name ) : '?', 'punkte' => (int) $r['points'], 'grund' => $r['reason'], 'status' => $r['status'] );
			},
			$rows
		),
		'bearbeiten' => $order->get_edit_order_url(),
	);
}

/** Widerrufsfrist überspringen: vorgemerkte Punkte sofort fällig machen, dann die Plugin-Aufgabe laufen lassen. */
function vt_frist_ueberspringen( $user_id = 0 ) {
	global $wpdb;
	$t   = Install::table( 'points_ledger' );
	$now = gmdate( 'Y-m-d H:i:s', time() - 1 );
	// Bestellungen, die noch nicht "abgeschlossen" sind, behalten ihre Frist (so wie im Live-Betrieb).
	$sql = "UPDATE $t SET confirms_at = %s WHERE status = 'pending' AND confirms_at IS NOT NULL AND confirms_at < %s";
	$far = gmdate( 'Y-m-d H:i:s', time() + 400 * DAY_IN_SECONDS );
	if ( $user_id ) {
		$wpdb->query( $wpdb->prepare( $sql . ' AND user_id = %d', $now, $far, $user_id ) ); // phpcs:ignore
	} else {
		$wpdb->query( $wpdb->prepare( $sql, $now, $far ) ); // phpcs:ignore
	}
	$before = (int) $wpdb->get_var( "SELECT COUNT(*) FROM $t WHERE status = 'pending'" ); // phpcs:ignore
	vt_stuendliche_aufgaben( true );
	$after = (int) $wpdb->get_var( "SELECT COUNT(*) FROM $t WHERE status = 'pending'" ); // phpcs:ignore
	return $before - $after;
}

/**
 * Einen Tag vorspulen (nur für diese Person): Buchungen von heute wandern auf gestern, der Coaching-Start
 * einen Tag nach vorn. Danach gibt es wieder Punkte fürs Öffnen und neue Lesepunkte, und der Coaching-Tag steigt.
 */
function vt_tag_vorspulen( $user_id ) {
	global $wpdb;
	$t       = Install::table( 'points_ledger' );
	$start   = ( new DateTimeImmutable( 'today', wp_timezone() ) )->setTimezone( new DateTimeZone( 'UTC' ) )->format( 'Y-m-d H:i:s' );
	$today   = Plugin::today();
	// Der heutige Öffnen-Schlüssel bekommt einen eindeutigen Zusatz, damit heute erneut Punkte möglich sind.
	$wpdb->query( $wpdb->prepare( "UPDATE $t SET idempotency_key = CONCAT(idempotency_key, ':vorgespult:', id) WHERE idempotency_key = %s", 'app_open:' . $user_id . ':' . $today ) ); // phpcs:ignore
	$n = (int) $wpdb->query( $wpdb->prepare( "UPDATE $t SET created_at = DATE_SUB(created_at, INTERVAL 1 DAY) WHERE user_id = %d AND created_at >= %s", $user_id, $start ) ); // phpcs:ignore
	$g = Profile::goals( $user_id );
	if ( $g['coaching_start_date'] ) {
		$g['coaching_start_date'] = ( new DateTimeImmutable( $g['coaching_start_date'] ) )->modify( '-1 day' )->format( 'Y-m-d' );
		update_user_meta( $user_id, Profile::GOALS_META, $g );
	}
	// Ratenbegrenzungen (z. B. Foto-Auswertungen pro Tag) zurücksetzen.
	$wpdb->query( "DELETE FROM {$wpdb->options} WHERE option_name LIKE '\\_transient\\_vibono\\_rl\\_%' OR option_name LIKE '\\_transient\\_timeout\\_vibono\\_rl\\_%'" ); // phpcs:ignore
	return $n;
}

function vt_aktion_format( $c ) {
	$f = Campaigns::format( $c );
	$f['starts_local'] = wp_date( 'd.m.Y H:i', $c['starts_at'] );
	$f['ends_local']   = wp_date( 'd.m.Y H:i', $c['ends_at'] );
	$f['enabled']      = (bool) $c['enabled'];
	return $f;
}

// --------------------------------------------------------------------- REST

function vt_route( $path, $methods, $cb ) {
	register_rest_route(
		VT_NS,
		$path,
		array(
			'methods'             => $methods,
			'callback'            => static function ( WP_REST_Request $r ) use ( $cb ) {
				try {
					$res = $cb( $r );
				} catch ( Throwable $e ) {
					return new WP_Error( 'vt_fehler', $e->getMessage() . ' (' . basename( $e->getFile() ) . ':' . $e->getLine() . ')', array( 'status' => 500 ) );
				}
				return is_wp_error( $res ) ? $res : rest_ensure_response( $res );
			},
			// Nur in der lokalen Testumgebung vorhanden (siehe VIBONO_TESTUMGEBUNG in wp-config.php).
			'permission_callback' => '__return_true',
		)
	);
}

add_action(
	'rest_api_init',
	static function () {
		if ( ! class_exists( 'Vibono\\AppApi\\Points' ) ) {
			return; // Plugin nicht aktiv.
		}

		vt_route(
			'/status',
			'GET',
			static function () {
				vt_stuendliche_aufgaben();
				$s    = Settings::all();
				$keys = array( 'module_api', 'module_shop', 'module_referral', 'module_web_reading', 'myvibono_write', 'points_enabled' );
				$err  = get_transient( Plugin::LAST_ERROR );
				return array(
					'plugin'            => array( 'aktiv' => true, 'version' => VIBONO_API_VERSION, 'abgeschaltet' => defined( 'VIBONO_API_DISABLE' ) && VIBONO_API_DISABLE ),
					'module'            => array_combine( $keys, array_map( static fn( $k ) => (bool) Settings::get( $k ), $keys ) ),
					'werte'             => array_intersect_key( $s, array_flip( array( 'cents_per_point', 'earn_app_open', 'earn_article_read', 'article_read_daily_cap', 'earn_referral', 'earn_referral_friend', 'referral_min_order_cents', 'earn_purchase_per_euro', 'pending_days', 'max_redeem_percent', 'min_redeem_points', 'reading_min_seconds', 'reading_max_seconds', 'reading_min_scroll', 'reading_quiz_mode' ) ) ),
					'adressen'          => vt_adressen(),
					'claude_schluessel' => '' !== Settings::anthropic_key(),
					'letzter_fehler'    => is_array( $err ) ? $err['message'] . ' (' . wp_date( 'd.m.Y H:i', $err['at'] ) . ')' : null,
					'mails'             => count( (array) get_option( 'vt_mails', array() ) ),
					'links'             => array(
						'backend'      => admin_url(),
						'punkte'       => admin_url( 'admin.php?page=vibono-points' ),
						'regeln'       => admin_url( 'admin.php?page=vibono-points&tab=rules' ),
						'aktionen'     => admin_url( 'admin.php?page=vibono-points&tab=campaigns' ),
						'buchen'       => admin_url( 'admin.php?page=vibono-points&tab=adjust' ),
						'schnittstelle'=> admin_url( 'admin.php?page=vibono-points&tab=app' ),
						'module'       => admin_url( 'admin.php?page=vibono-points&tab=modules' ),
						'bestellungen' => admin_url( 'admin.php?page=wc-orders' ),
						'shop'         => home_url( '/shop/' ),
						'warenkorb'    => wc_get_cart_url(),
						'konto'        => wc_get_page_permalink( 'myaccount' ),
						'abmelden'     => home_url( '/wp-login.php?action=logout' ),
						'anmelden'     => wp_login_url(),
						'tipps'        => home_url( '/tipps/' ),
					),
				);
			}
		);

		vt_route( '/nutzer', 'GET', static fn() => array_map( 'vt_nutzer', get_users( array( 'orderby' => 'ID', 'order' => 'ASC' ) ) ) );

		vt_route(
			'/nutzer/(?P<id>\d+)/mitgliedschaft',
			'POST',
			static function ( $r ) {
				vt_mitglied_setzen( (int) $r['id'], (bool) $r['aktiv'] );
				return vt_nutzer( (int) $r['id'] );
			}
		);

		vt_route(
			'/nutzer/(?P<id>\d+)/tag-vorspulen',
			'POST',
			static function ( $r ) {
				$n = vt_tag_vorspulen( (int) $r['id'] );
				return array( 'verschoben' => $n, 'nutzer' => vt_nutzer( (int) $r['id'] ) );
			}
		);

		vt_route(
			'/nutzer/(?P<id>\d+)/passwort-merken',
			'POST',
			static function ( $r ) {
				update_user_meta( (int) $r['id'], '_vt_testpasswort', sanitize_text_field( (string) $r['passwort'] ) );
				if ( $r['beschreibung'] ) {
					update_user_meta( (int) $r['id'], '_vt_beschreibung', sanitize_text_field( (string) $r['beschreibung'] ) );
				}
				return vt_nutzer( (int) $r['id'] );
			}
		);

		vt_route(
			'/produkte',
			'GET',
			static function () {
				$out = array();
				foreach ( wc_get_products( array( 'status' => 'publish', 'limit' => 50, 'orderby' => 'menu_order', 'order' => 'ASC' ) ) as $p ) {
					if ( (int) $p->get_id() === (int) get_option( 'vt_testartikel_id' ) ) {
						continue;
					}
					$out[] = array( 'id' => $p->get_id(), 'name' => $p->get_name(), 'preis' => (float) $p->get_price(), 'link' => $p->get_permalink() );
				}
				return $out;
			}
		);

		vt_route(
			'/bestellungen',
			'GET',
			static function ( $r ) {
				$args = array( 'limit' => 30, 'orderby' => 'date', 'order' => 'DESC' );
				if ( $r['user_id'] ) {
					$args['customer_id'] = (int) $r['user_id'];
				}
				return array_map( 'vt_bestellung', wc_get_orders( $args ) );
			}
		);

		vt_route(
			'/bestellungen',
			'POST',
			static function ( $r ) {
				$o = vt_bestellung_anlegen( (int) $r['user_id'], (array) ( $r['positionen'] ?: array() ), (int) round( (float) $r['betrag_eur'] * 100 ), (string) ( $r['status'] ?: 'processing' ), (array) ( $r['adresse'] ?: array() ) );
				return is_wp_error( $o ) ? $o : vt_bestellung( $o );
			}
		);

		vt_route(
			'/bestellungen/(?P<id>\d+)/status',
			'POST',
			static function ( $r ) {
				$o      = wc_get_order( (int) $r['id'] );
				$status = sanitize_key( (string) $r['status'] );
				if ( ! $o || ! in_array( $status, array( 'processing', 'completed', 'cancelled', 'refunded', 'on-hold' ), true ) ) {
					return new WP_Error( 'vt_status', 'Bestellung oder Status ungültig.', array( 'status' => 400 ) );
				}
				if ( 'refunded' === $status ) {
					// Wie "Rückerstattung" im Backend: Erstattung über den vollen Betrag anlegen.
					wc_create_refund( array( 'order_id' => $o->get_id(), 'amount' => $o->get_remaining_refund_amount(), 'reason' => 'Testumgebung: Rückerstattung', 'refund_payment' => false, 'restock_items' => false ) );
					$o = wc_get_order( $o->get_id() );
					if ( 'refunded' !== $o->get_status() ) {
						$o->update_status( 'refunded' );
					}
				} else {
					$o->update_status( $status, 'Testumgebung: Status geändert.' );
				}
				return vt_bestellung( wc_get_order( $o->get_id() ) );
			}
		);

		vt_route(
			'/frist-ueberspringen',
			'POST',
			static fn( $r ) => array( 'bestaetigt' => vt_frist_ueberspringen( (int) $r['user_id'] ) )
		);

		vt_route(
			'/stuendliche-aufgaben',
			'POST',
			static function () {
				vt_stuendliche_aufgaben( true );
				return array( 'ok' => true );
			}
		);

		vt_route(
			'/aktionen',
			'GET',
			static function () {
				Campaigns::flush();
				return array_map( 'vt_aktion_format', Campaigns::all_for_math() );
			}
		);

		vt_route(
			'/aktionen',
			'POST',
			static function ( $r ) {
				$tz   = wp_timezone();
				$from = new DateTimeImmutable( (string) ( $r['von'] ?: 'now' ), $tz );
				$to   = $r['bis'] ? new DateTimeImmutable( (string) $r['bis'], $tz ) : $from->modify( '+' . max( 1, (int) $r['stunden'] ) . ' hours' );
				// Speichert über dieselbe Funktion wie das Backend (Vibono-Punkte → Aktionen).
				$id = Campaigns::save(
					array(
						'name'        => (string) $r['name'],
						'description' => (string) $r['beschreibung'],
						'kind'        => (string) $r['art'],
						'reasons'     => (array) ( $r['gruende'] ?: array() ),
						'multiplier'  => (float) $r['multiplikator'],
						'starts_at'   => $from->format( 'c' ),
						'ends_at'     => $to->format( 'c' ),
						'enabled'     => true,
					)
				);
				return is_wp_error( $id ) ? new WP_Error( $id->get_error_code(), $id->get_error_message(), array( 'status' => 400 ) ) : array( 'id' => $id );
			}
		);

		vt_route(
			'/aktionen/(?P<id>\d+)',
			'DELETE',
			static function ( $r ) {
				Campaigns::delete( (int) $r['id'] );
				return array( 'ok' => true );
			}
		);

		vt_route( '/mails', 'GET', static fn() => array_map( static fn( $m ) => $m + array( 'zeit' => wp_date( 'd.m.Y H:i:s', $m['at'] ) ), (array) get_option( 'vt_mails', array() ) ) );
		vt_route(
			'/mails',
			'DELETE',
			static function () {
				delete_option( 'vt_mails' );
				return array( 'ok' => true );
			}
		);

		vt_route(
			'/claude-schluessel',
			'POST',
			static function ( $r ) {
				$key = trim( (string) $r['schluessel'] );
				if ( '' === $key ) {
					delete_option( 'vibono_api_anthropic_key' );
				} else {
					update_option( 'vibono_api_anthropic_key', $key, false );
				}
				return array( 'claude_schluessel' => '' !== $key );
			}
		);

		vt_route(
			'/fehlerprotokoll',
			'GET',
			static function () {
				$file = WP_CONTENT_DIR . '/fehlerprotokoll.log';
				if ( ! is_readable( $file ) ) {
					return array( 'zeilen' => array() );
				}
				$lines = file( $file, FILE_IGNORE_NEW_LINES );
				return array( 'zeilen' => array_slice( $lines, -150 ) );
			}
		);
	}
);
