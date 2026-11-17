<?php
/**
 * Ersatz für "WooCommerce Memberships" (kostenpflichtiges Plugin, hier nicht enthalten).
 *
 * Stellt genau die Funktionen bereit, die das Plugin vibono-app-api aufruft (siehe includes/Membership.php):
 * - Mitglied ist, wer das Nutzer-Meta "_vt_mitglied" = "1" hat (Plan "coaching"). Umschalten in der Testzentrale.
 * - Nur für Mitglieder ist ein Beitrag mit Beitrags-Meta "_vt_nur_mitglieder" = "1".
 */

defined( 'ABSPATH' ) || exit;

final class VT_Membership_Plan {
	public function get_slug() {
		return 'coaching';
	}
	public function get_name() {
		return 'Vibono Coaching';
	}
}

final class VT_User_Membership {
	private $ends;
	public function __construct( $ends ) {
		$this->ends = $ends;
	}
	public function get_plan() {
		return new VT_Membership_Plan();
	}
	public function get_status() {
		return 'active';
	}
	public function get_end_date( $format = 'mysql' ) {
		if ( ! $this->ends ) {
			return null;
		}
		return 'timestamp' === $format ? $this->ends : gmdate( 'Y-m-d H:i:s', $this->ends );
	}
}

function vt_ist_mitglied( $user_id ) {
	return $user_id && '1' === get_user_meta( (int) $user_id, '_vt_mitglied', true );
}

function vt_mitglied_setzen( $user_id, $aktiv ) {
	if ( $aktiv ) {
		update_user_meta( (int) $user_id, '_vt_mitglied', '1' );
		update_user_meta( (int) $user_id, '_vt_mitglied_bis', time() + 90 * DAY_IN_SECONDS );
	} else {
		delete_user_meta( (int) $user_id, '_vt_mitglied' );
		delete_user_meta( (int) $user_id, '_vt_mitglied_bis' );
	}
}

if ( ! function_exists( 'wc_memberships_get_user_memberships' ) ) {
	// Nur damit die Systemprüfung des Plugins den Ersatz als aktiv erkennt.
	function wc_memberships() {
		return (object) array( 'version' => 'Testumgebung (Ersatz)' );
	}
	function wc_memberships_get_user_memberships( $user_id = null ) {
		$user_id = $user_id ? (int) $user_id : get_current_user_id();
		return vt_ist_mitglied( $user_id ) ? array( new VT_User_Membership( (int) get_user_meta( $user_id, '_vt_mitglied_bis', true ) ) ) : array();
	}
	function wc_memberships_get_user_active_memberships( $user_id = null ) {
		return wc_memberships_get_user_memberships( $user_id );
	}
	function wc_memberships_is_user_active_member( $user_id = null, $plan = null ) {
		$user_id = $user_id ? (int) $user_id : get_current_user_id();
		$slug    = is_object( $plan ) && method_exists( $plan, 'get_slug' ) ? $plan->get_slug() : $plan;
		return vt_ist_mitglied( $user_id ) && ( null === $slug || in_array( (string) $slug, array( 'coaching', 'vibono-coaching' ), true ) );
	}
	function wc_memberships_is_post_content_restricted( $post_id = null ) {
		$post_id = $post_id ? (int) $post_id : get_the_ID();
		return '1' === get_post_meta( (int) $post_id, '_vt_nur_mitglieder', true );
	}
}

// Recht "eingeschränkte Inhalte sehen" für Mitglieder (so prüft das Plugin den Zugriff auf einen Beitrag).
add_filter(
	'user_has_cap',
	static function ( $allcaps, $caps, $args, $user ) {
		if ( in_array( 'wc_memberships_view_restricted_post_content', (array) $caps, true ) ) {
			$allcaps['wc_memberships_view_restricted_post_content'] = vt_ist_mitglied( $user->ID ) || ! empty( $allcaps['manage_options'] );
		}
		return $allcaps;
	},
	10,
	4
);

// Website: Inhalte nur für Mitglieder ausblenden, wie es die Paywall auf vibono.de tut.
add_filter(
	'the_content',
	static function ( $html ) {
		$id = get_the_ID();
		if ( ! $id || ! wc_memberships_is_post_content_restricted( $id ) || current_user_can( 'wc_memberships_view_restricted_post_content', $id ) ) {
			return $html;
		}
		return '<div style="padding:1.5em;border:2px solid #9CC536;border-radius:12px;background:#F3F7E8"><strong>Dieser Inhalt ist Teil des Vibono Coachings.</strong><br>In der Testumgebung schaltest du die Mitgliedschaft in der Testzentrale um.</div>';
	},
	99
);
