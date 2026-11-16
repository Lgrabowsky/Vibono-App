<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\SyncRules;

defined( 'ABSPATH' ) || exit;

/**
 * Onboarding-Angaben und Ziele (Wunschgewicht nach 3, 6, 12 Monaten).
 * Gespeichert als Nutzer-Meta, damit auch die Website (MyVibono) sie anzeigen kann.
 */
class Profile {

	const ONBOARDING_META = '_vibono_onboarding';
	const GOALS_META      = '_vibono_goals';

	const ENUMS = array(
		'diet'           => array( 'alles', 'flexitarisch', 'vegetarisch', 'vegan' ),
		'meat_amount'    => array( 'viel', 'wenig', 'keins' ),
		'intolerances'   => array( 'laktose', 'gluten', 'fruktose', 'histamin', 'nuesse', 'ei', 'soja', 'fisch' ),
		'activity_level' => array( 'sportmuffel', 'eingerostet', 'moderat_aktiv', 'sehr_aktiv' ),
		'gender'         => array( 'weiblich', 'maennlich', 'divers', 'keine_angabe' ),
		'age_group'      => array( 'u30', '30-39', '40-49', '50-59', '60plus' ),
		'topics'         => array( 'rezepte', 'motivation', 'aufgaben', 'bewegung', 'wissen' ),
	);

	public static function onboarding( int $user_id ): array {
		$o = get_user_meta( $user_id, self::ONBOARDING_META, true );
		return is_array( $o ) ? $o : array( 'completed' => false );
	}

	public static function goals( int $user_id ): array {
		$g = get_user_meta( $user_id, self::GOALS_META, true );
		$g = is_array( $g ) ? $g : array();
		return array_merge(
			array(
				'height_cm'            => null,
				'start_weight_kg'      => null,
				'target_weight_3m_kg'  => null,
				'target_weight_6m_kg'  => null,
				'target_weight_12m_kg' => null,
				'coaching_start_date'  => null,
			),
			$g
		);
	}

	public static function me( int $user_id ): array {
		$u = get_userdata( $user_id );
		return array(
			'id'                 => $user_id,
			'email'              => $u->user_email,
			'first_name'         => (string) $u->first_name,
			'display_name'       => $u->display_name,
			'avatar_url'         => get_avatar_url( $user_id, array( 'size' => 192 ) ),
			'memberships'        => Membership::for_user( $user_id ),
			'has_coaching_access'=> Membership::has_coaching_access( $user_id ),
			'onboarding'         => self::onboarding( $user_id ),
			'goals'              => self::goals( $user_id ),
			'points_balance'     => Points::balance( $user_id ),
			'referral_code'      => Referral::code_for( $user_id ),
			'updated_at'         => Plugin::iso( (int) get_user_meta( $user_id, '_vibono_profile_updated', true ) ?: strtotime( $u->user_registered . ' UTC' ) ),
		);
	}

	/** @return true|\WP_Error */
	public static function update( int $user_id, array $in ) {
		$errors = array();

		if ( isset( $in['first_name'] ) ) {
			wp_update_user( array( 'ID' => $user_id, 'first_name' => sanitize_text_field( $in['first_name'] ) ) );
		}

		if ( isset( $in['onboarding'] ) && is_array( $in['onboarding'] ) ) {
			$o   = self::onboarding( $user_id );
			$new = $in['onboarding'];

			if ( isset( $new['nutrition'] ) ) {
				$n = (array) $new['nutrition'];
				$o['nutrition'] = array_merge( (array) ( $o['nutrition'] ?? array() ), array_filter( array(
					'diet'         => self::enum( $n, 'diet', $errors, 'nutrition.diet' ),
					'meat_amount'  => self::enum( $n, 'meat_amount', $errors, 'nutrition.meat_amount' ),
					'intolerances' => isset( $n['intolerances'] ) ? self::enum_list( (array) $n['intolerances'], 'intolerances', $errors, 'nutrition.intolerances' ) : null,
					'dislikes'     => isset( $n['dislikes'] ) ? array_slice( array_values( array_filter( array_map( static fn( $s ) => mb_substr( sanitize_text_field( (string) $s ), 0, 60 ), (array) $n['dislikes'] ) ) ), 0, 50 ) : null,
				), static fn( $v ) => null !== $v ) );
			}
			if ( isset( $new['activity_level'] ) ) {
				$o['activity_level'] = self::enum( $new, 'activity_level', $errors, 'activity_level' );
			}
			if ( isset( $new['social'] ) ) {
				$s = (array) $new['social'];
				$o['social'] = array_merge( (array) ( $o['social'] ?? array() ), array_filter( array(
					'gender'         => self::enum( $s, 'gender', $errors, 'social.gender' ),
					'age_group'      => self::enum( $s, 'age_group', $errors, 'social.age_group' ),
					'household_size' => isset( $s['household_size'] ) ? self::int_range( $s['household_size'], 1, 15, $errors, 'social.household_size' ) : null,
					'children'       => isset( $s['children'] ) ? self::int_range( $s['children'], 0, 15, $errors, 'social.children' ) : null,
				), static fn( $v ) => null !== $v ) );
			}
			if ( isset( $new['communication'] ) ) {
				$c  = (array) $new['communication'];
				$oc = (array) ( $o['communication'] ?? array() );
				if ( isset( $c['notifications_per_day'] ) ) {
					$oc['notifications_per_day'] = self::int_range( $c['notifications_per_day'], 0, 10, $errors, 'communication.notifications_per_day' );
				}
				if ( isset( $c['topics'] ) ) {
					$oc['topics'] = self::enum_list( (array) $c['topics'], 'topics', $errors, 'communication.topics' );
				}
				if ( array_key_exists( 'quiet_hours', $c ) ) {
					$q = $c['quiet_hours'];
					if ( null === $q ) {
						$oc['quiet_hours'] = null;
					} elseif ( is_array( $q ) && self::is_hhmm( $q['start'] ?? '' ) && self::is_hhmm( $q['end'] ?? '' ) ) {
						$oc['quiet_hours'] = array( 'start' => $q['start'], 'end' => $q['end'] );
					} else {
						$errors[] = 'communication.quiet_hours';
					}
				}
				$o['communication'] = $oc;
			}
			if ( isset( $new['completed'] ) ) {
				$o['completed'] = (bool) $new['completed'];
			}
			if ( ! $errors ) {
				update_user_meta( $user_id, self::ONBOARDING_META, $o );
			}
		}

		if ( isset( $in['goals'] ) && is_array( $in['goals'] ) ) {
			$g = self::goals( $user_id );
			foreach ( array( 'height_cm' => array( 100, 250 ), 'start_weight_kg' => array( 30, 400 ), 'target_weight_3m_kg' => array( 30, 400 ), 'target_weight_6m_kg' => array( 30, 400 ), 'target_weight_12m_kg' => array( 30, 400 ) ) as $k => $range ) {
				if ( ! array_key_exists( $k, $in['goals'] ) ) {
					continue;
				}
				$v = $in['goals'][ $k ];
				if ( null === $v ) {
					$g[ $k ] = null;
				} elseif ( is_numeric( $v ) && $v >= $range[0] && $v <= $range[1] ) {
					$g[ $k ] = round( (float) $v, 1 );
				} else {
					$errors[] = 'goals.' . $k;
				}
			}
			if ( array_key_exists( 'coaching_start_date', $in['goals'] ) ) {
				$d = $in['goals']['coaching_start_date'];
				if ( null === $d || SyncRules::is_date( (string) $d ) ) {
					$g['coaching_start_date'] = $d;
				} else {
					$errors[] = 'goals.coaching_start_date';
				}
			}
			if ( ! $errors ) {
				update_user_meta( $user_id, self::GOALS_META, $g );
			}
		}

		if ( $errors ) {
			return Plugin::error( 'vibono_invalid_profile', 'Einige Angaben sind ungültig.', 400, array( 'fields' => array_values( array_unique( $errors ) ) ) );
		}
		update_user_meta( $user_id, '_vibono_profile_updated', time() );
		do_action( 'vibono_api_profile_updated', $user_id );
		return true;
	}

	private static function enum( array $in, string $field, array &$errors, string $path ): ?string {
		if ( ! isset( $in[ $field ] ) ) {
			return null;
		}
		if ( in_array( $in[ $field ], self::ENUMS[ $field ], true ) ) {
			return $in[ $field ];
		}
		$errors[] = $path;
		return null;
	}

	private static function enum_list( array $values, string $field, array &$errors, string $path ): array {
		$ok = array_values( array_unique( array_intersect( $values, self::ENUMS[ $field ] ) ) );
		if ( count( $ok ) !== count( array_unique( $values ) ) ) {
			$errors[] = $path;
		}
		return $ok;
	}

	private static function int_range( $v, int $min, int $max, array &$errors, string $path ): ?int {
		if ( is_numeric( $v ) && (int) $v >= $min && (int) $v <= $max ) {
			return (int) $v;
		}
		$errors[] = $path;
		return null;
	}

	private static function is_hhmm( $v ): bool {
		return is_string( $v ) && (bool) preg_match( '/^([01][0-9]|2[0-3]):[0-5][0-9]$/', $v );
	}

	/** Letztes eingetragenes Gewicht (aus der Sync-Sammlung weight). */
	public static function current_weight( int $user_id ): ?float {
		$items = SyncStore::current_map( $user_id, 'weight' );
		if ( ! $items ) {
			return null;
		}
		ksort( $items );
		return (float) end( $items )['kg'];
	}
}
