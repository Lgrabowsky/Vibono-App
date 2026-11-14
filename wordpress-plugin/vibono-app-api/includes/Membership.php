<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Brücke zu WooCommerce Memberships (Paywall von vibono.de).
 */
class Membership {

	public static function for_user( int $user_id ): array {
		if ( ! function_exists( 'wc_memberships_get_user_memberships' ) ) {
			return array();
		}
		$out = array();
		foreach ( (array) wc_memberships_get_user_memberships( $user_id ) as $m ) {
			$plan  = $m->get_plan();
			$end   = $m->get_end_date( 'timestamp' );
			$out[] = array(
				'plan'    => $plan ? $plan->get_slug() : '',
				'name'    => $plan ? $plan->get_name() : '',
				'status'  => $m->get_status(),
				'ends_at' => $end ? Plugin::iso( $end ) : null,
			);
		}
		return $out;
	}

	public static function has_coaching_access( int $user_id ): bool {
		if ( user_can( $user_id, 'manage_options' ) ) {
			return true;
		}
		if ( ! function_exists( 'wc_memberships_is_user_active_member' ) ) {
			return (bool) apply_filters( 'vibono_api_has_coaching_access', false, $user_id );
		}
		$plans = (array) Settings::get( 'coaching_membership_plans' );
		if ( ! $plans ) {
			$active = wc_memberships_get_user_active_memberships( $user_id );
			return (bool) apply_filters( 'vibono_api_has_coaching_access', ! empty( $active ), $user_id );
		}
		foreach ( $plans as $plan ) {
			if ( wc_memberships_is_user_active_member( $user_id, $plan ) ) {
				return (bool) apply_filters( 'vibono_api_has_coaching_access', true, $user_id );
			}
		}
		return (bool) apply_filters( 'vibono_api_has_coaching_access', false, $user_id );
	}

	/** Darf der Nutzer diesen Beitrag sehen? Nutzt die Inhaltsregeln von WooCommerce Memberships. */
	public static function can_view( int $user_id, int $post_id ): bool {
		if ( function_exists( 'wc_memberships_is_post_content_restricted' ) && wc_memberships_is_post_content_restricted( $post_id ) ) {
			return $user_id && ( user_can( $user_id, 'manage_options' ) || user_can( $user_id, 'wc_memberships_view_restricted_post_content', $post_id ) );
		}
		return 'publish' === get_post_status( $post_id );
	}

	public static function is_restricted( int $post_id ): bool {
		return function_exists( 'wc_memberships_is_post_content_restricted' ) && wc_memberships_is_post_content_restricted( $post_id );
	}
}
