<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\PointsMath;

defined( 'ABSPATH' ) || exit;

/**
 * Punkte im Vibono-Shop (WooCommerce).
 *
 * Verdienen:  bezahlte Bestellungen bringen Punkte je Euro Warenwert (ohne Versand, nach Rabatten
 *             und Punkte-Einlösung). Vorgemerkt bis Ende der Widerrufsfrist, bei Storno/Erstattung verfallen.
 * Einlösen:   im Warenkorb/an der Kasse. Umsetzung als virtueller Gutschein "vibono-punkte"
 *             (Betrag = Punkte × aktueller Cent-Wert), dadurch rechnet WooCommerce Steuern korrekt anteilig.
 *             Abbuchung beim Anlegen der Bestellung, Rückbuchung bei Storno/Fehlschlag/Erstattung.
 * Mein Konto: Reiter "Vibono-Punkte" mit Kontostand, Verlauf und Empfehlungslink.
 */
class WooCommerce {

	const COUPON   = 'vibono-punkte';
	const SESSION  = 'vibono_redeem_points';
	const ENDPOINT = 'vibono-punkte';

	public static function init(): void {
		// Verdienen.
		add_action( 'woocommerce_order_status_processing', array( self::class, 'on_paid' ) );
		add_action( 'woocommerce_order_status_completed', array( self::class, 'on_paid' ) );
		add_action( 'woocommerce_order_status_completed', array( self::class, 'on_completed' ), 20 );
		foreach ( array( 'cancelled', 'refunded', 'failed' ) as $status ) {
			add_action( 'woocommerce_order_status_' . $status, array( self::class, 'on_reversed' ) );
		}

		// Werbende Person beim Anlegen der Bestellung festhalten (Cookie ist nur hier verfügbar).
		add_action( 'woocommerce_checkout_order_created', array( self::class, 'on_order_created' ) );
		add_action( 'woocommerce_store_api_checkout_order_processed', array( self::class, 'on_order_created' ) );

		// Einlösen.
		add_filter( 'woocommerce_get_shop_coupon_data', array( self::class, 'virtual_coupon' ), 10, 2 );
		add_action( 'woocommerce_before_calculate_totals', array( self::class, 'sync_coupon' ), 20 );
		add_action( 'woocommerce_cart_totals_before_order_total', array( self::class, 'render_redeem_box' ) );
		add_action( 'woocommerce_review_order_before_order_total', array( self::class, 'render_redeem_box' ) );
		add_action( 'wp_loaded', array( self::class, 'handle_redeem_form' ), 30 );
		add_filter( 'woocommerce_cart_totals_coupon_label', array( self::class, 'coupon_label' ), 10, 2 );
		add_action( 'woocommerce_after_checkout_validation', array( self::class, 'validate_checkout' ), 10, 2 );
		add_action( 'woocommerce_checkout_create_order', array( self::class, 'store_redeem_on_order' ) );

		// Anzeige.
		add_action( 'woocommerce_single_product_summary', array( self::class, 'product_hint' ), 25 );
		add_action( 'init', array( self::class, 'add_endpoint' ) );
		add_filter( 'woocommerce_account_menu_items', array( self::class, 'account_menu' ) );
		add_action( 'woocommerce_account_' . self::ENDPOINT . '_endpoint', array( self::class, 'account_page' ) );
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
		if ( $uid ) {
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
		Referral::on_order_paid( $order );
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
		if ( $redeemed > 0 && $order->get_customer_id() && ! Points::has_key( 'redeem_refund:' . $order_id ) ) {
			Points::book(
				(int) $order->get_customer_id(),
				$redeemed,
				'redeem_refund',
				'Punkte zurück (Bestellung ' . $order->get_order_number() . ' ' . wc_get_order_status_name( $order->get_status() ) . ')',
				array( 'ref_type' => 'order', 'ref_id' => (int) $order_id, 'idempotency_key' => 'redeem_refund:' . $order_id )
			);
		}
	}

	public static function on_order_created( $order ): void {
		if ( ! $order instanceof \WC_Order ) {
			$order = wc_get_order( $order );
		}
		if ( ! $order ) {
			return;
		}
		Referral::referrer_for_order( $order );
		self::deduct_redeemed( $order );
		$order->save();
	}

	// ------------------------------------------------------------ Einlösen

	private static function requested_points(): int {
		return ( function_exists( 'WC' ) && WC()->session ) ? (int) WC()->session->get( self::SESSION, 0 ) : 0;
	}

	/** Warenwert brutto ohne Versand nach anderen Rabatten (ohne unseren Gutschein), in Cent. */
	private static function cart_goods_cents( \WC_Cart $cart ): int {
		$total = 0.0;
		foreach ( $cart->get_cart() as $item ) {
			$total += (float) $item['line_subtotal'] + (float) $item['line_subtotal_tax'];
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

	/** Gutschein passend zur Session an- oder abmelden. */
	public static function sync_coupon( \WC_Cart $cart ): void {
		static $running = false;
		if ( $running || ! is_user_logged_in() ) {
			return;
		}
		$running = true;
		$want    = self::requested_points() > 0;
		$has     = $cart->has_discount( self::COUPON );
		if ( $want && ! $has ) {
			$cart->apply_coupon( self::COUPON );
			wc_clear_notices();
		} elseif ( ! $want && $has ) {
			$cart->remove_coupon( self::COUPON );
		}
		$running = false;
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

	public static function render_redeem_box(): void {
		if ( ! is_user_logged_in() || ! Settings::get( 'points_enabled' ) ) {
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

	public static function store_redeem_on_order( \WC_Order $order ): void {
		$req = self::requested_points();
		if ( ! $req || ! $order->get_customer_id() ) {
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

	// ------------------------------------------------------------ Anzeige

	public static function product_hint(): void {
		global $product;
		if ( ! $product || ! Settings::get( 'points_enabled' ) ) {
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

	public static function account_menu( array $items ): array {
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
		$ref     = Referral::info( $uid );
		echo '<h3>Deine Vibono-Punkte</h3>';
		printf( '<p><strong>%s Punkte</strong> = %s', esc_html( number_format_i18n( $summary['balance'] ) ), wp_kses_post( wc_price( $summary['value_cents'] / 100 ) ) );
		if ( $summary['pending'] ) {
			printf( ' · %s Punkte vorgemerkt', esc_html( number_format_i18n( $summary['pending'] ) ) );
		}
		echo '</p>';
		foreach ( $summary['campaigns'] as $c ) {
			if ( $c['active'] ) {
				printf( '<p class="woocommerce-info">Aktion: %s</p>', esc_html( $c['name'] . ( $c['description'] ? ' – ' . $c['description'] : '' ) ) );
			}
		}
		echo '<h3>Freunde werben</h3>';
		printf( '<p>Für jede*n Freund*in, die oder der über deinen Link zum ersten Mal bestellt, bekommst du <strong>%d Punkte</strong>. Dein Link:</p>', (int) $ref['points_per_referral'] );
		printf( '<p><input type="text" readonly class="input-text" style="width:100%%" value="%s" onclick="this.select()"></p>', esc_attr( $ref['link'] ) );
		printf( '<p>%d registriert · %d bestellt · %d Punkte verdient</p>', (int) $ref['invited'], (int) $ref['converted'], (int) $ref['points_earned'] );
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
