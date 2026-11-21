<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\PointsMath;

defined( 'ABSPATH' ) || exit;

/**
 * Punkte im Vibono-Shop (WooCommerce).
 *
 * Seit dem 21.11.2026 (Vorgabe Vibono) gibt es Punkte nicht mehr für Einkäufe, und Punkte werden gegen
 * Prämien eingelöst (siehe Rewards), nicht mehr als Guthaben an der Kasse. Beides ist hier weiter
 * vorhanden, aber standardmäßig aus (Einstellungen earn_purchases und redeem_at_checkout).
 *
 * Verdienen:  (nur mit earn_purchases) bezahlte Bestellungen bringen Punkte je Euro Warenwert (ohne Versand,
 *             nach Rabatten und Punkte-Einlösung). Vorgemerkt bis Ende der Widerrufsfrist, bei Storno/Erstattung verfallen.
 * Einlösen:   (nur mit redeem_at_checkout) im Warenkorb/an der Kasse. Umsetzung als virtueller Gutschein "vibono-punkte"
 *             (Betrag = Punkte × aktueller Cent-Wert), dadurch rechnet WooCommerce Steuern korrekt anteilig.
 *             Abbuchung beim Anlegen der Bestellung, Rückbuchung bei Storno/Fehlschlag/Erstattung.
 * Mein Konto: Reiter "Vibono-Punkte" mit Kontostand, Prämien, Verlauf und Empfehlungslink.
 * Prämie "Rabatt auf Verlängerung": persönlicher WooCommerce-Gutschein (create_reward_coupon).
 */
class WooCommerce {

	const COUPON   = 'vibono-punkte';
	const SESSION  = 'vibono_redeem_points';
	const ENDPOINT = 'vibono-punkte';

	/** Punkte im Shop sammeln und einlösen (Modul "Shop"). */
	public static function shop_on(): bool {
		return Settings::on( 'module_shop' ) && (bool) Settings::get( 'points_enabled' );
	}

	/** Punkte für Einkäufe (seit 21.11.2026 standardmäßig aus). */
	public static function purchase_points_on(): bool {
		return self::shop_on() && (bool) Settings::get( 'earn_purchases' );
	}

	/** Punkte als Guthaben im Warenkorb einlösen (seit 21.11.2026 standardmäßig aus). */
	public static function checkout_redeem_on(): bool {
		return self::shop_on() && (bool) Settings::get( 'redeem_at_checkout' );
	}

	/** Reiter "Mein Konto → Vibono-Punkte" anzeigen? */
	public static function account_tab_on(): bool {
		return self::shop_on() || Rewards::module_on();
	}

	public static function init(): void {
		// Buchhaltung, immer aktiv: berührt nur Vibono-Daten. So werden Punkte zu Bestellungen auch dann
		// korrekt bestätigt, abgebucht oder zurückgebucht, wenn ein Modul später abgeschaltet wird.
		Plugin::hook( 'woocommerce_order_status_completed', array( self::class, 'on_completed' ), 20 );
		foreach ( array( 'cancelled', 'refunded', 'failed' ) as $status ) {
			Plugin::hook( 'woocommerce_order_status_' . $status, array( self::class, 'on_reversed' ) );
		}
		Plugin::hook( 'woocommerce_checkout_order_created', array( self::class, 'on_order_created' ) );
		Plugin::hook( 'woocommerce_store_api_checkout_order_processed', array( self::class, 'on_order_created' ) );

		// Punkte für bezahlte Bestellungen (Einkauf und/oder Empfehlung).
		if ( self::purchase_points_on() || Settings::on( 'module_referral' ) ) {
			Plugin::hook( 'woocommerce_order_status_processing', array( self::class, 'on_paid' ) );
			Plugin::hook( 'woocommerce_order_status_completed', array( self::class, 'on_paid' ) );
		}

		// Einlösen als Guthaben an der Kasse.
		if ( self::checkout_redeem_on() ) {
			Plugin::hook( 'woocommerce_get_shop_coupon_data', array( self::class, 'virtual_coupon' ), 10, 2 );
			Plugin::hook( 'woocommerce_before_calculate_totals', array( self::class, 'sync_coupon' ), 20 );
			Plugin::hook( 'woocommerce_cart_totals_before_order_total', array( self::class, 'render_redeem_box' ) );
			Plugin::hook( 'woocommerce_review_order_before_order_total', array( self::class, 'render_checkout_row' ) );
			Plugin::hook( 'wp_loaded', array( self::class, 'handle_redeem_form' ), 30 );
			Plugin::hook( 'woocommerce_cart_totals_coupon_label', array( self::class, 'coupon_label' ), 10, 2 );
			Plugin::hook( 'woocommerce_after_checkout_validation', array( self::class, 'validate_checkout' ), 10, 2 );
			Plugin::hook( 'woocommerce_checkout_create_order', array( self::class, 'store_redeem_on_order' ) );
			Plugin::hook( 'woocommerce_store_api_checkout_update_order_meta', array( self::class, 'store_redeem_on_order' ) );
		}

		// Anzeige.
		if ( self::purchase_points_on() ) {
			Plugin::hook( 'woocommerce_single_product_summary', array( self::class, 'product_hint' ), 25 );
		}
		if ( ! self::account_tab_on() ) {
			return;
		}
		Plugin::hook( 'wp_loaded', array( Rewards::class, 'handle_account_form' ), 30 );
		Plugin::hook( 'init', array( self::class, 'add_endpoint' ) );
		Plugin::hook( 'woocommerce_get_query_vars', array( self::class, 'query_vars' ) );
		Plugin::hook( 'woocommerce_account_menu_items', array( self::class, 'account_menu' ) );
		Plugin::hook( 'woocommerce_account_' . self::ENDPOINT . '_endpoint', array( self::class, 'account_page' ) );
	}

	// ------------------------------------------------------------ Verdienen

	public static function goods_cents( \WC_Order $order ): int {
		return (int) round( ( (float) $order->get_total() - (float) $order->get_shipping_total() - (float) $order->get_shipping_tax() - (float) $order->get_total_refunded() ) * 100 );
	}

	public static function on_paid( $order_id ): void {
		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			return;
		}
		$uid = (int) $order->get_customer_id();
		if ( $uid && self::purchase_points_on() ) {
			$points = PointsMath::purchase_points( self::goods_cents( $order ), (float) Settings::get( 'earn_purchase_per_euro' ) );
			if ( $points > 0 ) {
				// Basis ist "Punkte je Euro"; Points::earn multipliziert mit Aktionen.
				Points::earn(
					$uid,
					'purchase',
					$points,
					array(
						'idempotency_key' => 'purchase:' . $order->get_id(),
						'label'           => 'Einkauf im Vibono-Shop (Bestellung ' . $order->get_order_number() . ')',
						'ref_type'        => 'order',
						'ref_id'          => $order->get_id(),
						// Vorläufig sehr lange vorgemerkt, Frist beginnt erst mit "abgeschlossen".
						'pending_days'    => 3650,
					)
				);
			}
		}
		if ( Settings::on( 'module_referral' ) && Settings::get( 'points_enabled' ) ) {
			Referral::on_order_paid( $order );
		}
		if ( 'completed' === $order->get_status() ) {
			self::on_completed( $order_id );
		}
	}

	/** Bestellung abgeschlossen (versendet/freigeschaltet): Widerrufsfrist läuft ab jetzt. */
	public static function on_completed( $order_id ): void {
		Points::set_confirm_at( 'order', (int) $order_id, time() + DAY_IN_SECONDS * (int) Settings::get( 'pending_days' ) );
	}

	public static function on_reversed( $order_id ): void {
		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			return;
		}
		Points::void_ref( 'order', (int) $order_id, array( 'purchase', 'referral', 'referral_friend' ) );
		$redeemed = (int) $order->get_meta( '_vibono_points_redeemed' );
		// Nur zurückbuchen, was wirklich abgebucht wurde, und nur einmal.
		if ( $redeemed > 0 && $order->get_customer_id() && Points::has_key( 'redeem:' . $order_id ) && ! Points::has_key( 'redeem_refund:' . $order_id ) ) {
			Points::book(
				(int) $order->get_customer_id(),
				$redeemed,
				'redeem_refund',
				'Punkte zurück (Bestellung ' . $order->get_order_number() . ' ' . wc_get_order_status_name( $order->get_status() ) . ')',
				array( 'ref_type' => 'order', 'ref_id' => (int) $order_id, 'idempotency_key' => 'redeem_refund:' . $order_id )
			);
		}
	}

	/**
	 * Holt Buchungen für eine Bestellung nach, deren Status sich geändert hat, während das Plugin
	 * deaktiviert oder per VIBONO_API_DISABLE abgeschaltet war. Mehrfach ausführbar.
	 *
	 * @return string Was getan wurde (leer = nichts nötig).
	 */
	public static function reconcile_order( \WC_Order $order, bool $dry = false ): string {
		global $wpdb;
		$t      = Install::table( 'points_ledger' );
		$id     = (int) $order->get_id();
		$status = $order->get_status();
		if ( in_array( $status, array( 'cancelled', 'refunded', 'failed' ), true ) ) {
			$active   = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM $t WHERE ref_type = 'order' AND ref_id = %d AND status IN ('pending','confirmed') AND reason IN ('purchase','referral','referral_friend')", $id ) );
			$redeemed = (int) $order->get_meta( '_vibono_points_redeemed' );
			$refund   = $redeemed > 0 && Points::has_key( 'redeem:' . $id ) && ! Points::has_key( 'redeem_refund:' . $id );
			if ( ! $active && ! $refund ) {
				return '';
			}
			if ( ! $dry ) {
				self::on_reversed( $id );
			}
			return sprintf( '%s: %d Gutschriften storniert%s', $status, $active, $refund ? ', ' . $redeemed . ' eingelöste Punkte zurückgebucht' : '' );
		}
		if ( 'completed' === $status ) {
			// Frist läuft ab "abgeschlossen". Platzhalter (sehr ferne Bestätigung) durch das echte Datum ersetzen.
			$days  = (int) Settings::get( 'pending_days' );
			$limit = gmdate( 'Y-m-d H:i:s', time() + ( $days + 1 ) * DAY_IN_SECONDS );
			$open  = (int) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM $t WHERE ref_type = 'order' AND ref_id = %d AND status = 'pending' AND confirms_at > %s", $id, $limit ) );
			if ( ! $open ) {
				return '';
			}
			if ( ! $dry ) {
				$done = $order->get_date_completed() ? $order->get_date_completed()->getTimestamp() : time();
				Points::set_confirm_at( 'order', $id, $done + DAY_IN_SECONDS * $days );
			}
			return sprintf( 'abgeschlossen: Frist für %d vorgemerkte Buchungen gesetzt', $open );
		}
		return '';
	}

	public static function on_order_created( $order ): void {
		if ( ! $order instanceof \WC_Order ) {
			$order = wc_get_order( $order );
		}
		if ( ! $order ) {
			return;
		}
		if ( Settings::on( 'module_referral' ) ) {
			// Speichert nur die eigenen Meta-Felder, kein erneutes $order->save() mit allen Folge-Hooks.
			Referral::referrer_for_order( $order );
			$order->save_meta_data();
		}
		self::deduct_redeemed( $order );
	}

	// ------------------------------------------------------------ Einlösen

	private static function requested_points(): int {
		return ( function_exists( 'WC' ) && WC()->session ) ? (int) WC()->session->get( self::SESSION, 0 ) : 0;
	}

	/** Warenwert brutto ohne Versand nach anderen Rabatten (ohne unseren Gutschein), in Cent. */
	private static function cart_goods_cents( \WC_Cart $cart ): int {
		$total = 0.0;
		foreach ( $cart->get_cart() as $item ) {
			$total += (float) ( $item['line_subtotal'] ?? 0 ) + (float) ( $item['line_subtotal_tax'] ?? 0 );
		}
		foreach ( $cart->get_coupon_discount_totals() as $code => $amount ) {
			if ( self::COUPON !== $code ) {
				$total -= (float) $amount + (float) ( $cart->get_coupon_discount_tax_totals()[ $code ] ?? 0 );
			}
		}
		return (int) round( max( 0, $total ) * 100 );
	}

	public static function calc( \WC_Cart $cart, int $user_id, int $requested ): array {
		$eff = PointsMath::effective_cents_per_point( (float) Settings::get( 'cents_per_point' ), Campaigns::all_for_math(), time() );
		return PointsMath::redeemable(
			$requested,
			Points::balance( $user_id ),
			self::cart_goods_cents( $cart ),
			$eff,
			(int) Settings::get( 'max_redeem_percent' ),
			(int) Settings::get( 'min_redeem_points' )
		);
	}

	public static function virtual_coupon( $data, $code ) {
		if ( self::COUPON !== wc_format_coupon_code( (string) $code ) || ! is_user_logged_in() || ! WC()->cart ) {
			return $data;
		}
		$calc = self::calc( WC()->cart, get_current_user_id(), self::requested_points() );
		if ( $calc['points'] <= 0 ) {
			return $data;
		}
		return array(
			'code'                 => self::COUPON,
			'discount_type'        => 'fixed_cart',
			'amount'               => wc_format_decimal( $calc['cents'] / 100, 2 ),
			'individual_use'       => false,
			'usage_limit'          => 0,
			'free_shipping'        => false,
			'exclude_sale_items'   => false,
			'virtual'              => true,
		);
	}

	/** Anderer Gutschein im Warenkorb, der nur allein gilt ("Individuelle Nutzung")? */
	private static function blocked_by_individual_coupon( \WC_Cart $cart ): string {
		foreach ( $cart->get_applied_coupons() as $code ) {
			if ( self::COUPON !== $code && ( new \WC_Coupon( $code ) )->get_individual_use() ) {
				return (string) $code;
			}
		}
		return '';
	}

	/**
	 * Gutschein passend zur Session leise an- oder abmelden. Bewusst ohne apply_coupon():
	 * das würde eine Erfolgsmeldung erzeugen, und deren Löschen würde fremde Shop-Hinweise mitlöschen.
	 */
	public static function sync_coupon( $cart ): void {
		if ( ! $cart instanceof \WC_Cart || ! is_user_logged_in() ) {
			return;
		}
		$applied = $cart->get_applied_coupons();
		$has     = in_array( self::COUPON, $applied, true );
		$want    = self::requested_points() > 0;
		// Nicht mehr einlösbar (anderer Gutschein "nur allein", Punktestand oder Warenkorb geändert):
		// Einlösung still zurücknehmen, statt WooCommerce einen ungültigen Gutschein melden zu lassen.
		if ( $want && ( self::blocked_by_individual_coupon( $cart ) || self::calc( $cart, get_current_user_id(), self::requested_points() )['points'] <= 0 ) ) {
			WC()->session->set( self::SESSION, 0 );
			$want = false;
		}
		if ( $want && ! $has ) {
			$applied[] = self::COUPON;
			$cart->set_applied_coupons( $applied );
		} elseif ( ! $want && $has ) {
			$cart->set_applied_coupons( array_values( array_diff( $applied, array( self::COUPON ) ) ) );
		}
	}

	public static function coupon_label( $label, $coupon ) {
		if ( $coupon->get_code() === self::COUPON ) {
			$calc = self::calc( WC()->cart, get_current_user_id(), self::requested_points() );
			return sprintf( '%s Vibono-Punkte eingelöst', number_format_i18n( $calc['points'] ) );
		}
		return $label;
	}

	public static function handle_redeem_form(): void {
		if ( empty( $_POST['vibono_redeem_action'] ) || ! is_user_logged_in() || ! function_exists( 'WC' ) || ! WC()->session ) {
			return;
		}
		if ( ! isset( $_POST['vibono_redeem_nonce'] ) || ! wp_verify_nonce( sanitize_key( $_POST['vibono_redeem_nonce'] ), 'vibono_redeem' ) ) {
			return;
		}
		if ( 'remove' === $_POST['vibono_redeem_action'] ) {
			WC()->session->set( self::SESSION, 0 );
			return;
		}
		$blocking = self::blocked_by_individual_coupon( WC()->cart );
		if ( $blocking ) {
			wc_add_notice( sprintf( 'Vibono-Punkte können nicht zusammen mit dem Gutschein „%s“ eingelöst werden.', $blocking ), 'error' );
			return;
		}
		$requested = absint( $_POST['vibono_redeem_points'] ?? 0 );
		$calc      = self::calc( WC()->cart, get_current_user_id(), $requested );
		if ( $calc['error'] ) {
			$messages = array(
				'below_minimum'    => sprintf( 'Du kannst ab %d Punkten einlösen.', (int) Settings::get( 'min_redeem_points' ) ),
				'cart_too_small'   => 'Dein Warenkorb ist zu klein, um Punkte einzulösen.',
				'nothing_to_redeem'=> 'Gerade können keine Punkte eingelöst werden.',
			);
			wc_add_notice( $messages[ $calc['error'] ] ?? 'Punkte konnten nicht eingelöst werden.', 'error' );
			WC()->session->set( self::SESSION, 0 );
			return;
		}
		WC()->session->set( self::SESSION, $calc['points'] );
		if ( $calc['points'] < $requested ) {
			wc_add_notice( sprintf( 'Es wurden %d Punkte eingelöst (max. %d %% des Warenwerts).', $calc['points'], (int) Settings::get( 'max_redeem_percent' ) ), 'notice' );
		}
	}

	/**
	 * Einlösefeld im Warenkorb. Die Summen-Box liegt im klassischen Warenkorb außerhalb des
	 * Warenkorb-Formulars, deshalb ist ein eigenes Formular hier zulässig.
	 */
	public static function render_redeem_box(): void {
		if ( ! is_user_logged_in() || ! WC()->cart ) {
			return;
		}
		$uid     = get_current_user_id();
		$balance = Points::balance( $uid );
		if ( $balance < (int) Settings::get( 'min_redeem_points' ) && ! self::requested_points() ) {
			return;
		}
		$eff  = PointsMath::effective_cents_per_point( (float) Settings::get( 'cents_per_point' ), Campaigns::all_for_math(), time() );
		$max  = self::calc( WC()->cart, $uid, $balance );
		$used = self::requested_points();
		echo '<tr class="vibono-points"><th>Vibono-Punkte</th><td><form method="post" class="vibono-redeem">';
		wp_nonce_field( 'vibono_redeem', 'vibono_redeem_nonce' );
		printf( '<p>Du hast <strong>%s Punkte</strong> (Wert %s).', esc_html( number_format_i18n( $balance ) ), wp_kses_post( wc_price( $balance * $eff / 100 ) ) );
		if ( $eff > (float) Settings::get( 'cents_per_point' ) ) {
			echo ' <strong>Aktion: Deine Punkte sind gerade mehr wert!</strong>';
		}
		echo '</p>';
		if ( $used ) {
			echo '<button type="submit" name="vibono_redeem_action" value="remove" class="button">Einlösung entfernen</button>';
		} elseif ( $max['points'] > 0 ) {
			printf( '<input type="number" name="vibono_redeem_points" min="%d" max="%d" value="%d" style="width:7em"> ', (int) Settings::get( 'min_redeem_points' ), (int) $max['points'], (int) $max['points'] );
			echo '<button type="submit" name="vibono_redeem_action" value="apply" class="button">Punkte einlösen</button>';
		}
		echo '</form></td></tr>';
	}

	/**
	 * Kasse: nur eine Info-Zeile mit Link zum Warenkorb. Ein Formular ginge hier nicht, weil die
	 * Bestellübersicht im Kassen-Formular liegt (verschachtelte Formulare würden die Bestellung absenden).
	 */
	public static function render_checkout_row(): void {
		if ( ! is_user_logged_in() || self::requested_points() ) {
			return; // Eingelöste Punkte stehen schon als Gutschein-Zeile in der Übersicht.
		}
		$balance = Points::balance( get_current_user_id() );
		if ( $balance < (int) Settings::get( 'min_redeem_points' ) ) {
			return;
		}
		printf(
			'<tr class="vibono-points"><th>Vibono-Punkte</th><td>Du hast %s Punkte. <a href="%s">Im Warenkorb einlösen</a></td></tr>',
			esc_html( number_format_i18n( $balance ) ),
			esc_url( wc_get_cart_url() )
		);
	}

	/** Vor dem Bestellen: Ist die Einlösung noch gedeckt? */
	public static function validate_checkout( $data, $errors ): void {
		$req = self::requested_points();
		if ( ! $req || ! is_user_logged_in() ) {
			return;
		}
		$calc = self::calc( WC()->cart, get_current_user_id(), $req );
		if ( $calc['points'] !== $req ) {
			WC()->session->set( self::SESSION, $calc['points'] );
			$errors->add( 'vibono_points', 'Dein Punktestand oder Warenkorb hat sich geändert. Bitte prüfe die eingelösten Punkte.' );
		}
	}

	public static function store_redeem_on_order( $order ): void {
		$req = self::requested_points();
		if ( ! $order instanceof \WC_Order || ! $req || ! $order->get_customer_id() || ! WC()->cart ) {
			return;
		}
		$calc = self::calc( WC()->cart, (int) $order->get_customer_id(), $req );
		$order->update_meta_data( '_vibono_points_redeemed', $calc['points'] );
		$order->update_meta_data( '_vibono_points_value_cents', $calc['cents'] );
	}

	private static function deduct_redeemed( \WC_Order $order ): void {
		$points = (int) $order->get_meta( '_vibono_points_redeemed' );
		$uid    = (int) $order->get_customer_id();
		if ( $points <= 0 || ! $uid || Points::has_key( 'redeem:' . $order->get_id() ) ) {
			return;
		}
		Points::book(
			$uid,
			-$points,
			'redeem',
			'Eingelöst bei Bestellung ' . $order->get_order_number(),
			array(
				'ref_type'        => 'order',
				'ref_id'          => $order->get_id(),
				'idempotency_key' => 'redeem:' . $order->get_id(),
				'meta'            => array( 'value_cents' => (int) $order->get_meta( '_vibono_points_value_cents' ) ),
			)
		);
		if ( WC()->session ) {
			WC()->session->set( self::SESSION, 0 );
		}
	}

	// ------------------------------------------- Prämie: Rabatt auf Verlängerung

	/**
	 * Persönlicher Einmal-Gutschein für die Verlängerung einer Mitgliedschaft.
	 * Nur für das E-Mail-Konto der Person, einmal nutzbar, auf die Verlängerungs-Produkte der Prämie
	 * beschränkt (leer = ganzer Warenkorb) und befristet.
	 *
	 * ANNAHME: Verlängert wird auf vibono.de durch einen neuen Kauf des Mitgliedschafts-Produkts.
	 * Automatische Abo-Verlängerungen (WooCommerce Subscriptions) übernehmen solche Gutscheine nicht;
	 * dafür gibt es den Filter "vibono_reward_coupon_args".
	 *
	 * @return array{code:string, coupon_id:int, expires_at:int}|\WP_Error
	 */
	public static function create_reward_coupon( int $user_id, array $reward ) {
		if ( ! class_exists( '\WC_Coupon' ) ) {
			return Plugin::error( 'vibono_shop_unavailable', 'Der Shop ist gerade nicht erreichbar.', 503 );
		}
		$user = get_userdata( $user_id );
		if ( ! $user || ! $user->user_email ) {
			return Plugin::error( 'vibono_no_email', 'Für den Gutschein fehlt eine E-Mail-Adresse im Konto.', 400 );
		}
		$expires = time() + max( 1, (int) $reward['valid_days'] ) * DAY_IN_SECONDS;
		for ( $try = 0; $try < 5; $try++ ) {
			$code = Core\RewardRules::coupon_code( random_bytes( 8 ) );
			if ( ! wc_get_coupon_id_by_code( $code ) ) {
				break;
			}
		}
		$args = apply_filters(
			'vibono_reward_coupon_args',
			array(
				'code'                 => $code,
				'discount_type'        => 'percent' === $reward['discount_type'] ? 'percent' : 'fixed_cart',
				'amount'               => wc_format_decimal( $reward['discount_amount'], 2 ),
				'product_ids'          => (array) $reward['product_ids'],
				'email_restrictions'   => array( $user->user_email ),
				'usage_limit'          => 1,
				'usage_limit_per_user' => 1,
				'individual_use'       => false,
				'date_expires'         => $expires,
				'description'          => sprintf( 'Vibono-Prämie „%s“ für Konto %d', $reward['title'], $user_id ),
			),
			$user_id,
			$reward
		);
		$coupon = new \WC_Coupon();
		$coupon->set_props( $args );
		$coupon->update_meta_data( '_vibono_reward_id', (int) $reward['id'] );
		$coupon->update_meta_data( '_vibono_user_id', $user_id );
		$id = (int) $coupon->save();
		if ( ! $id ) {
			return Plugin::error( 'vibono_coupon_failed', 'Der Gutschein konnte nicht angelegt werden.', 500 );
		}
		return array( 'code' => $coupon->get_code(), 'coupon_id' => $id, 'expires_at' => $expires );
	}

	/** Wurde der Gutschein schon benutzt? */
	public static function coupon_used( int $coupon_id ): bool {
		if ( ! $coupon_id || ! class_exists( '\WC_Coupon' ) ) {
			return false;
		}
		$c = new \WC_Coupon( $coupon_id );
		return $c->get_id() && $c->get_usage_count() > 0;
	}

	// ------------------------------------------------------------ Anzeige

	public static function product_hint(): void {
		global $product;
		if ( ! $product instanceof \WC_Product ) {
			return;
		}
		$base = PointsMath::purchase_points( (int) round( (float) wc_get_price_including_tax( $product ) * 100 ), (float) Settings::get( 'earn_purchase_per_euro' ) );
		$pts  = PointsMath::earn( $base, Campaigns::all_for_math(), time(), 'purchase' )['points'];
		if ( $pts > 0 ) {
			printf( '<p class="vibono-points-hint">Mit diesem Kauf sammelst du <strong>%s Vibono-Punkte</strong>.</p>', esc_html( number_format_i18n( $pts ) ) );
		}
	}

	public static function add_endpoint(): void {
		add_rewrite_endpoint( self::ENDPOINT, EP_ROOT | EP_PAGES );
	}

	public static function query_vars( $vars ) {
		$vars[ self::ENDPOINT ] = self::ENDPOINT;
		return $vars;
	}

	public static function account_menu( $items ) {
		if ( ! is_array( $items ) ) {
			return $items;
		}
		$out = array();
		foreach ( $items as $k => $v ) {
			if ( 'customer-logout' === $k ) {
				$out[ self::ENDPOINT ] = 'Vibono-Punkte';
			}
			$out[ $k ] = $v;
		}
		return $out;
	}

	public static function account_page(): void {
		$uid     = get_current_user_id();
		$summary = Points::summary( $uid );
		$ledger  = Points::ledger( $uid, 1, 50 );
		echo '<h3>Deine Vibono-Punkte</h3>';
		printf( '<p><strong>%s Punkte</strong>', esc_html( number_format_i18n( $summary['balance'] ) ) );
		if ( self::checkout_redeem_on() ) {
			printf( ' = %s', wp_kses_post( wc_price( $summary['value_cents'] / 100 ) ) );
		}
		if ( $summary['pending'] ) {
			printf( ' · %s Punkte vorgemerkt', esc_html( number_format_i18n( $summary['pending'] ) ) );
		}
		echo '</p>';
		foreach ( $summary['campaigns'] as $c ) {
			if ( $c['active'] && ( 'earn' === $c['kind'] || self::checkout_redeem_on() ) ) {
				printf( '<p class="woocommerce-info">Aktion: %s</p>', esc_html( $c['name'] . ( $c['description'] ? ' – ' . $c['description'] : '' ) ) );
			}
		}
		if ( Rewards::module_on() ) {
			Rewards::render_account_section( $uid );
		}
		if ( Settings::on( 'module_referral' ) ) {
			$ref = Referral::info( $uid );
			echo '<h3>Freunde werben</h3>';
			printf( '<p>Für jede*n Freund*in, die oder der über deinen Link zum ersten Mal bestellt, bekommst du <strong>%d Punkte</strong>. Dein Link:</p>', (int) $ref['points_per_referral'] );
			printf( '<p><input type="text" readonly class="input-text" style="width:100%%" value="%s" onclick="this.select()"></p>', esc_attr( $ref['link'] ) );
			printf( '<p>%d registriert · %d bestellt · %d Punkte verdient</p>', (int) $ref['invited'], (int) $ref['converted'], (int) $ref['points_earned'] );
		}
		echo '<h3>Verlauf</h3><table class="shop_table"><thead><tr><th>Datum</th><th>Was</th><th>Punkte</th></tr></thead><tbody>';
		foreach ( $ledger['items'] as $e ) {
			$status = 'pending' === $e['status'] ? ' (vorgemerkt)' : ( 'void' === $e['status'] ? ' (storniert)' : '' );
			printf(
				'<tr><td>%s</td><td>%s</td><td>%s%s</td></tr>',
				esc_html( wp_date( 'd.m.Y', strtotime( $e['created_at'] ) ) ),
				esc_html( $e['label'] ),
				esc_html( ( $e['points'] > 0 ? '+' : '' ) . number_format_i18n( $e['points'] ) ),
				esc_html( $status )
			);
		}
		echo '</tbody></table>';
	}
}
