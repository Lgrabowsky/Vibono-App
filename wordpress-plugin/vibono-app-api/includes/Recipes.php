<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\Ingredients;

defined( 'ABSPATH' ) || exit;

/**
 * Zutaten und Portionen eines Rezepts für die Einkaufsliste der App. Liest nur, schreibt nie.
 *
 * ANNAHME: Wo vibono.de die Zutaten speichert, ist noch offen (Theme-Code fehlt). Reihenfolge:
 *  1. Filter "vibono_api_recipe_ingredients" (eigener Adapter): array{servings:?int, ingredients:array}|null
 *  2. WP Recipe Maker, falls installiert (Meta "wprm_servings" und "wprm_ingredients" am Rezept)
 *  3. Eingestellte Felder (Backend → App-Schnittstelle), sonst die üblichen Feldnamen
 *     "zutaten"/"ingredients" und "portionen"/"servings". ACF-Wiederholer und Freitext werden erkannt.
 */
class Recipes {

	const INGREDIENT_KEYS = array( 'zutaten', 'ingredients', 'rezept_zutaten' );
	const SERVINGS_KEYS   = array( 'portionen', 'servings', 'personen', 'anzahl_portionen' );

	/** @return array{servings: ?int, ingredients: ?array} */
	public static function data( \WP_Post $p ): array {
		static $cache = array();
		$ck = $p->ID . '|' . $p->post_modified_gmt;
		if ( isset( $cache[ $ck ] ) ) {
			return $cache[ $ck ];
		}
		$result = array( 'servings' => null, 'ingredients' => null );

		$custom = apply_filters( 'vibono_api_recipe_ingredients', null, $p );
		if ( is_array( $custom ) ) {
			$result = array(
				'servings'    => Ingredients::servings( $custom['servings'] ?? null ),
				'ingredients' => isset( $custom['ingredients'] ) ? Ingredients::from_rows( (array) $custom['ingredients'] ) : null,
			);
		} else {
			$result = self::from_wprm( $p ) ?? self::from_fields( $p );
		}
		if ( is_array( $result['ingredients'] ) && ! $result['ingredients'] ) {
			$result['ingredients'] = null;
		}
		return $cache[ $ck ] = $result;
	}

	private static function from_wprm( \WP_Post $p ): ?array {
		if ( ! class_exists( 'WPRM_Recipe_Manager' ) ) {
			return null;
		}
		$ids = array();
		if ( 'wprm_recipe' === $p->post_type ) {
			$ids = array( $p->ID );
		} elseif ( is_callable( array( 'WPRM_Recipe_Manager', 'get_recipe_ids_from_post' ) ) ) {
			$ids = (array) \WPRM_Recipe_Manager::get_recipe_ids_from_post( $p->ID );
		}
		if ( ! $ids ) {
			return null;
		}
		$groups = get_post_meta( (int) $ids[0], 'wprm_ingredients', true );
		if ( ! is_array( $groups ) || ! $groups ) {
			return null;
		}
		return array(
			'servings'    => Ingredients::servings( get_post_meta( (int) $ids[0], 'wprm_servings', true ) ),
			'ingredients' => Ingredients::from_wprm( $groups ),
		);
	}

	private static function from_fields( \WP_Post $p ): array {
		$ing_key  = (string) Settings::get( 'recipe_ingredients_meta_key' );
		$serv_key = (string) Settings::get( 'recipe_servings_meta_key' );

		$ingredients = null;
		foreach ( $ing_key ? array( $ing_key ) : self::INGREDIENT_KEYS as $key ) {
			$raw = self::field( $p->ID, $key );
			if ( is_array( $raw ) && $raw ) {
				$ingredients = Ingredients::from_rows( $raw );
			} elseif ( is_string( $raw ) && '' !== trim( $raw ) ) {
				$ingredients = Ingredients::from_text( $raw );
			}
			if ( $ingredients ) {
				break;
			}
		}

		$servings = null;
		foreach ( $serv_key ? array( $serv_key ) : self::SERVINGS_KEYS as $key ) {
			$servings = Ingredients::servings( self::field( $p->ID, $key ) );
			if ( $servings ) {
				break;
			}
		}
		return array( 'servings' => $servings, 'ingredients' => $ingredients );
	}

	/** Feldwert lesen: über ACF, falls vorhanden (liefert Wiederholer als Zeilen), sonst als Meta-Feld. */
	private static function field( int $post_id, string $key ) {
		if ( function_exists( 'get_field' ) ) {
			$v = get_field( $key, $post_id );
			if ( null !== $v && false !== $v && '' !== $v ) {
				return $v;
			}
		}
		$v = get_post_meta( $post_id, $key, true );
		if ( is_string( $v ) && '' !== $v && ( '[' === $v[0] || '{' === $v[0] ) ) {
			$decoded = json_decode( $v, true );
			if ( is_array( $decoded ) ) {
				return $decoded;
			}
		}
		return $v;
	}
}
