<?php
namespace Vibono\AppApi\Rest;

use Vibono\AppApi\Content;
use Vibono\AppApi\Plugin;
use Vibono\AppApi\Settings;
use Vibono\AppApi\Vision;

defined( 'ABSPATH' ) || exit;

class EnergyController extends Controller {

	public function register(): void {
		$this->route( '/foods', 'GET', array( $this, 'foods' ) );
		$this->route( '/energy-density/scan-recipe', 'POST', array( $this, 'scan_recipe' ) );
		$this->route( '/energy-density/analyze-photo', 'POST', array( $this, 'analyze_photo' ) );
	}

	/**
	 * Lebensmittelsuche. Quelle: Beiträge vom Typ "energiedichte" mit kcal-Feld (ANNAHME),
	 * erweiterbar über den Filter "vibono_api_foods" (z. B. eigene Tabelle oder BLS-Import).
	 */
	public function foods( \WP_REST_Request $r ) {
		$q = trim( sanitize_text_field( (string) $r['q'] ) );
		if ( mb_strlen( $q ) < 2 ) {
			return Plugin::error( 'vibono_query_too_short', 'Bitte mindestens 2 Zeichen eingeben.', 400 );
		}
		$limit = max( 1, min( 50, (int) ( $r['limit'] ?: 20 ) ) );
		$key   = (string) Settings::get( 'food_kcal_meta_key' );
		$posts = get_posts(
			array(
				'post_type'      => (string) Settings::get( 'food_post_type' ),
				'post_status'    => 'publish',
				's'              => $q,
				'posts_per_page' => $limit,
				'no_found_rows'  => true,
			)
		);
		$items = array();
		foreach ( $posts as $p ) {
			$kcal = str_replace( ',', '.', (string) get_post_meta( $p->ID, $key, true ) );
			if ( is_numeric( $kcal ) ) {
				$items[] = array(
					'id'            => 'wp:' . $p->ID,
					'name'          => html_entity_decode( get_the_title( $p ), ENT_QUOTES, 'UTF-8' ),
					'kcal_per_100g' => (float) $kcal,
					'source'        => 'vibono',
				);
			}
		}
		$items = apply_filters( 'vibono_api_foods', $items, $q, $limit );
		return $this->ok( array( 'items' => array_slice( $items, 0, $limit ) ) );
	}

	private function guard( \WP_REST_Request $r ) {
		$limit = $this->throttle( 'vision', (int) Settings::get( 'vision_daily_limit' ), DAY_IN_SECONDS );
		if ( is_wp_error( $limit ) ) {
			return $limit;
		}
		return Vision::check_image( (string) $r['image_base64'], (string) $r['mime'] );
	}

	public function scan_recipe( \WP_REST_Request $r ) {
		$img = $this->guard( $r );
		if ( is_wp_error( $img ) ) {
			return $img;
		}
		$res = Vision::analyze( $img[0], $img[1], Vision::RECIPE_PROMPT, Vision::recipe_schema() );
		return is_wp_error( $res ) ? $res : $this->ok( Vision::finish_recipe( $res ) );
	}

	public function analyze_photo( \WP_REST_Request $r ) {
		$img = $this->guard( $r );
		if ( is_wp_error( $img ) ) {
			return $img;
		}
		$res = Vision::analyze( $img[0], $img[1], Vision::PHOTO_PROMPT, Vision::photo_schema(), sanitize_text_field( (string) $r['description'] ) );
		return is_wp_error( $res ) ? $res : $this->ok( Vision::finish_photo( $res ) );
	}
}
