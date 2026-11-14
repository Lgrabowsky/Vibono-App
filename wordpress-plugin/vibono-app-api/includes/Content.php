<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\CoachingCalendar;
use Vibono\AppApi\Core\ReadingRules;
use Vibono\AppApi\Core\SyncRules;

defined( 'ABSPATH' ) || exit;

/**
 * Inhalte für die App: Lektionen (my_coaching), Rezepte, Vibono-Tipps, Tipp des Tages,
 * und die Tagesübersicht für den Startbildschirm.
 *
 * ANNAHMEN (Theme-Code fehlt): Post-Typen und Taxonomien siehe Settings; Rezept-Merkmale
 * (vegetarisch, vegan, ut-geeignet, Unverträglichkeiten) werden als Begriffs-Slugs in irgendeiner
 * Taxonomie des Rezept-Typs gesucht; Bewegungstipps als Beiträge der Kategorie "bewegung".
 */
class Content {

	const TYPES = array(
		'lessons'         => 'lesson',
		'recipes'         => 'recipe',
		'tips'            => 'tip',
		'tips-of-the-day' => 'tip_of_the_day',
	);

	public static function init(): void {
		Plugin::hook( 'transition_post_status', array( self::class, 'track_removed' ), 10, 3 );
	}

	public static function post_type( string $kind ): string {
		$map = array(
			'lesson'         => 'lesson_post_type',
			'recipe'         => 'recipe_post_type',
			'tip'            => 'tip_post_type',
			'tip_of_the_day' => 'tip_of_day_post_type',
		);
		return (string) Settings::get( $map[ $kind ] );
	}

	public static function kind_of( \WP_Post $p ): string {
		foreach ( array( 'lesson', 'recipe', 'tip', 'tip_of_the_day' ) as $k ) {
			if ( self::post_type( $k ) === $p->post_type ) {
				return $k;
			}
		}
		return 'tip';
	}

	public static function lesson_taxonomy(): string {
		$tax = (string) Settings::get( 'lesson_taxonomy' );
		if ( $tax ) {
			return $tax;
		}
		$taxes = get_object_taxonomies( self::post_type( 'lesson' ) );
		return $taxes ? (string) reset( $taxes ) : '';
	}

	/** Gelöschte/depublizierte Inhalte merken, damit die App sie per since entfernen kann. */
	public static function track_removed( $new, $old, $post ): void {
		if ( 'publish' === $old && 'publish' !== $new ) {
			$list               = (array) get_option( 'vibono_api_removed', array() );
			$list[ $post->ID ]  = time();
			arsort( $list );
			update_option( 'vibono_api_removed', array_slice( $list, 0, 2000, true ), false );
		}
	}

	public static function summary( \WP_Post $p, int $user_id, ?array $done = null ): array {
		$kind      = self::kind_of( $p );
		$locked    = ! Membership::can_view( $user_id, $p->ID );
		$tags      = array();
		foreach ( get_object_taxonomies( $p->post_type ) as $tax ) {
			$terms = get_the_terms( $p, $tax );
			if ( is_array( $terms ) ) {
				foreach ( $terms as $t ) {
					$tags[] = $t->slug;
				}
			}
		}
		$course = null;
		$lkind  = null;
		if ( 'lesson' === $kind ) {
			$tax   = self::lesson_taxonomy();
			$terms = $tax ? get_the_terms( $p, $tax ) : false;
			$course = is_array( $terms ) ? (int) $terms[0]->term_id : null;
			$meta   = (string) Settings::get( 'lesson_kind_meta_key' );
			$lkind  = $meta ? ( (string) get_post_meta( $p->ID, $meta, true ) ?: null ) : null;
		}
		$ed_key = (string) Settings::get( 'recipe_ed_meta_key' );
		$ed     = 'recipe' === $kind && $ed_key ? get_post_meta( $p->ID, $ed_key, true ) : '';
		$words  = Reading::eligible( $p->ID ) ? Reading::word_count( $p->ID ) : 0;
		$thumb  = get_the_post_thumbnail_url( $p, 'medium_large' );
		// Zutaten nur für freigeschaltete Rezepte (sonst wäre das Rezept über die Einkaufsliste lesbar).
		$recipe = 'recipe' === $kind && ! $locked ? Recipes::data( $p ) : array( 'servings' => null, 'ingredients' => null );

		return array(
			'id'                  => $p->ID,
			'type'                => $kind,
			'title'               => html_entity_decode( wp_strip_all_tags( get_the_title( $p ) ), ENT_QUOTES, 'UTF-8' ),
			'excerpt'             => $locked ? '' : wp_trim_words( wp_strip_all_tags( $p->post_excerpt ?: strip_shortcodes( $p->post_content ) ), 30 ),
			'thumbnail_url'       => $thumb ?: null,
			'url'                 => get_permalink( $p ),
			'tags'                => array_values( array_unique( $tags ) ),
			'lesson_kind'         => $lkind,
			'course_id'           => $course,
			'servings'            => $recipe['servings'],
			'ingredients'         => $recipe['ingredients'],
			'energy_density'      => is_numeric( str_replace( ',', '.', (string) $ed ) ) ? (float) str_replace( ',', '.', (string) $ed ) : null,
			'reading_minutes'     => $words ? max( 1, (int) round( $words / max( 1, (int) Settings::get( 'reading_wpm' ) ) ) ) : null,
			'points_for_reading'  => $user_id && ! $locked ? Reading::points_for( $user_id, $p->ID ) : 0,
			'requires_membership' => Membership::is_restricted( $p->ID ),
			'locked'              => $locked,
			'done'                => 'lesson' === $kind && null !== $done ? isset( $done[ (string) $p->ID ] ) : null,
			'modified_at'         => Plugin::iso( $p->post_modified_gmt ),
		);
	}

	public static function detail( \WP_Post $p, int $user_id ) {
		if ( ! Membership::can_view( $user_id, $p->ID ) ) {
			return Plugin::error( 'vibono_membership_required', 'Dieser Inhalt ist Teil einer Vibono-Mitgliedschaft.', 403, array( 'required_plans' => (array) Settings::get( 'coaching_membership_plans' ) ) );
		}
		$done = SyncStore::current_map( $user_id, 'lessons_done' );
		$html = apply_filters( 'the_content', $p->post_content ); // phpcs:ignore
		return array_merge(
			self::summary( $p, $user_id, $done ),
			array(
				'content_html' => $html,
				'word_count'   => ReadingRules::word_count( $html ),
			)
		);
	}

	public static function query( string $kind, int $user_id, array $args ): array {
		$q = array(
			'post_type'      => self::post_type( $kind ),
			'post_status'    => 'publish',
			'posts_per_page' => max( 1, min( 100, (int) ( $args['per_page'] ?? 20 ) ) ),
			'paged'          => max( 1, (int) ( $args['page'] ?? 1 ) ),
			'orderby'        => 'lesson' === $kind ? array( 'menu_order' => 'ASC', 'date' => 'ASC' ) : 'date',
			'order'          => 'lesson' === $kind ? 'ASC' : 'DESC',
		);
		if ( ! empty( $args['search'] ) ) {
			$q['s'] = sanitize_text_field( $args['search'] );
		}
		if ( ! empty( $args['since'] ) && strtotime( $args['since'] ) ) {
			$q['date_query'] = array( array( 'column' => 'post_modified_gmt', 'after' => gmdate( 'Y-m-d H:i:s', strtotime( $args['since'] ) ) ) );
			$q['orderby']    = 'modified';
			$q['order']      = 'ASC';
		}
		if ( 'lesson' === $kind && ! empty( $args['course'] ) && self::lesson_taxonomy() ) {
			$q['tax_query'] = array( array( 'taxonomy' => self::lesson_taxonomy(), 'terms' => (int) $args['course'] ) ); // phpcs:ignore
		}
		if ( ! empty( $args['tags'] ) ) {
			$tax_query = self::tag_query( self::post_type( $kind ), array_map( 'sanitize_title', explode( ',', $args['tags'] ) ) );
			if ( $tax_query ) {
				$q['tax_query'] = array_merge( $q['tax_query'] ?? array(), $tax_query ); // phpcs:ignore
			}
		}
		$wpq  = new \WP_Query( $q );
		$done = 'lesson' === $kind ? SyncStore::current_map( $user_id, 'lessons_done' ) : null;

		$removed = array();
		if ( ! empty( $args['since'] ) && strtotime( $args['since'] ) ) {
			$since = strtotime( $args['since'] );
			foreach ( (array) get_option( 'vibono_api_removed', array() ) as $id => $ts ) {
				if ( $ts > $since && get_post_type( $id ) === self::post_type( $kind ) ) {
					$removed[] = (int) $id;
				}
			}
		}
		return array(
			'items'       => array_map( static fn( $p ) => self::summary( $p, $user_id, $done ), $wpq->posts ),
			'deleted_ids' => $removed,
			'server_time' => Plugin::iso( time() ),
			'total'       => (int) $wpq->found_posts,
			'total_pages' => (int) $wpq->max_num_pages,
		);
	}

	/** Begriffe mit diesen Slugs in irgendeiner Taxonomie des Post-Typs (UND-verknüpft). */
	private static function tag_query( string $post_type, array $slugs ): array {
		$out = array();
		foreach ( $slugs as $slug ) {
			foreach ( get_object_taxonomies( $post_type ) as $tax ) {
				if ( term_exists( $slug, $tax ) ) {
					$out[] = array( 'taxonomy' => $tax, 'field' => 'slug', 'terms' => $slug );
					break;
				}
			}
		}
		return $out;
	}

	// ------------------------------------------------------- Tagesübersicht

	private static function pick( array $ids, int $n, int $seed ): array {
		if ( ! $ids ) {
			return array();
		}
		mt_srand( $seed );
		shuffle( $ids );
		mt_srand();
		return array_slice( $ids, 0, $n );
	}

	private static function recipe_ids_for( int $user_id, string $phase ): array {
		$o         = Profile::onboarding( $user_id );
		$diet      = $o['nutrition']['diet'] ?? null;
		$tags      = array();
		if ( in_array( $diet, array( 'vegetarisch', 'vegan' ), true ) ) {
			$tags[] = $diet;
		}
		if ( 'phase1' === $phase ) {
			$tags[] = 'ut-geeignet'; // ANNAHME: Kennzeichnung Umstellungstag-Rezepte.
		}
		foreach ( (array) ( $o['nutrition']['intolerances'] ?? array() ) as $i ) {
			$tags[] = $i . 'frei'; // ANNAHME: z. B. "laktosefrei", "glutenfrei".
		}
		$type = self::post_type( 'recipe' );
		$q    = array(
			'post_type'      => $type,
			'post_status'    => 'publish',
			'posts_per_page' => 300,
			'fields'         => 'ids',
			'no_found_rows'  => true,
		);
		$tax = self::tag_query( $type, $tags );
		if ( $tax ) {
			$q['tax_query'] = $tax; // phpcs:ignore
		}
		$ids = get_posts( $q );
		if ( count( $ids ) < 3 && $tax ) {
			unset( $q['tax_query'] );
			$ids = get_posts( $q );
		}
		$dislikes = array_filter( array_map( 'mb_strtolower', (array) ( $o['nutrition']['dislikes'] ?? array() ) ) );
		if ( $dislikes ) {
			$ids = array_values(
				array_filter(
					$ids,
					static function ( $id ) use ( $dislikes ) {
						$title = mb_strtolower( get_the_title( $id ) );
						foreach ( $dislikes as $d ) {
							if ( false !== mb_strpos( $title, $d ) ) {
								return false;
							}
						}
						return true;
					}
				)
			);
		}
		return $ids;
	}

	/** Wochenplan-Einträge eines Tages in fester Reihenfolge der Mahlzeiten. Leer = nichts geplant. */
	public static function planned_meals( int $user_id, string $date ): array {
		MyVibonoBridge::reconcile( $user_id, array( 'weekplan' ) );
		$map = SyncStore::current_map( $user_id, 'weekplan' );
		$out = array();
		foreach ( SyncRules::WEEKPLAN_SLOTS as $slot ) {
			$e = $map[ $date . ':' . $slot ] ?? null;
			if ( ! is_array( $e ) ) {
				continue;
			}
			$out[] = array(
				'slot'      => $slot,
				'recipe_id' => empty( $e['recipe_id'] ) ? null : (int) $e['recipe_id'],
				'portions'  => isset( $e['portions'] ) ? (int) $e['portions'] : null,
				'note'      => (string) ( $e['note'] ?? '' ),
			);
		}
		return $out;
	}

	public static function today( int $user_id, string $date ): array {
		$goals = Profile::goals( $user_id );
		$phase = CoachingCalendar::day( $goals['coaching_start_date'], $date, (int) Settings::get( 'phase1_days' ), (int) Settings::get( 'phase2_days' ) );
		$seed  = crc32( $user_id . '|' . $date );
		$done  = SyncStore::current_map( $user_id, 'lessons_done' );
		$kg    = Profile::current_weight( $user_id );

		// Lektionen der aktuellen Phase.
		$terms   = (array) ( Settings::get( 'phase_terms' )[ $phase['key'] ] ?? array() );
		$tax     = self::lesson_taxonomy();
		$lessons = array();
		if ( $terms && $tax ) {
			$lessons = get_posts(
				array(
					'post_type'      => self::post_type( 'lesson' ),
					'post_status'    => 'publish',
					'posts_per_page' => 200,
					'orderby'        => array( 'menu_order' => 'ASC', 'date' => 'ASC' ),
					'tax_query'      => array( array( 'taxonomy' => $tax, 'terms' => array_map( 'intval', $terms ) ) ), // phpcs:ignore
				)
			);
		}
		$open     = array_values( array_filter( $lessons, static fn( $p ) => ! isset( $done[ (string) $p->ID ] ) ) );
		$todays   = array_slice( $open, 0, 6 );
		$sections = array( 'essen' => array(), 'bewegung' => array(), 'wissen' => array(), 'sonstiges' => array() );
		foreach ( $todays as $p ) {
			$s    = self::summary( $p, $user_id, $done );
			$kind = $s['lesson_kind'];
			if ( 'rezepte' === $kind ) {
				$sections['essen'][] = $s;
			} elseif ( in_array( $kind, array( 'lesen', 'wichtig', 'hinweise' ), true ) ) {
				$sections['wissen'][] = $s;
			} else {
				$sections['sonstiges'][] = $s;
			}
		}

		// Bewegung: Tipp aus Kategorie "bewegung" passend zum Tag (ANNAHME).
		$move = get_posts( array( 'post_type' => self::post_type( 'tip' ), 'category_name' => 'bewegung', 'posts_per_page' => 50, 'fields' => 'ids', 'no_found_rows' => true ) );
		foreach ( self::pick( $move, 1, $seed + 1 ) as $id ) {
			$sections['bewegung'][] = self::summary( get_post( $id ), $user_id, $done );
		}

		// Rezepte: was im Wochenplan für diesen Tag steht (bewusst freie Plätze ohne Rezept),
		// sonst drei Vorschläge passend zu Phase und Ernährung.
		$planned = self::planned_meals( $user_id, $date );
		if ( $planned ) {
			$source  = 'weekplan';
			$ids     = array_values( array_unique( array_filter( array_column( $planned, 'recipe_id' ) ) ) );
			$posts   = array_filter( array_map( 'get_post', $ids ), static fn( $p ) => $p instanceof \WP_Post && 'publish' === $p->post_status );
			$recipes = array_values( array_map( static fn( $p ) => self::summary( $p, $user_id ), $posts ) );
		} else {
			$source  = 'suggestion';
			$recipes = array_map( static fn( $id ) => self::summary( get_post( $id ), $user_id ), self::pick( self::recipe_ids_for( $user_id, $phase['key'] ), 3, $seed ) );
		}

		$tip_ids = get_posts( array( 'post_type' => self::post_type( 'tip' ), 'post_status' => 'publish', 'posts_per_page' => 60, 'fields' => 'ids', 'no_found_rows' => true ) );
		$tip     = self::pick( $tip_ids, 1, $seed + 2 );

		$tod_ids = get_posts( array( 'post_type' => self::post_type( 'tip_of_the_day' ), 'post_status' => 'publish', 'posts_per_page' => 500, 'fields' => 'ids', 'no_found_rows' => true, 'orderby' => 'ID', 'order' => 'ASC' ) );
		$tod     = null;
		if ( $tod_ids ) {
			$day_of_year = (int) ( new \DateTimeImmutable( $date ) )->format( 'z' );
			$tod_id      = $tod_ids[ $day_of_year % count( $tod_ids ) ];
			$tod         = array( 'id' => $tod_id, 'text' => wp_strip_all_tags( strip_shortcodes( get_post_field( 'post_content', $tod_id ) ) ) ?: get_the_title( $tod_id ) );
		}

		return array(
			'date'           => $date,
			'phase'          => array_intersect_key( $phase, array_flip( array( 'key', 'label', 'day_in_phase', 'day_label', 'coaching_day' ) ) ),
			'progress'       => array(
				'overall'    => round( CoachingCalendar::overall_progress( $goals['coaching_start_date'], $goals, $kg, $date ), 3 ),
				'phase'      => round( (float) $phase['phase_progress'], 3 ),
				'milestones' => CoachingCalendar::milestones( $goals['coaching_start_date'], $goals, $kg, $date ),
			),
			'next_step'      => $open ? self::summary( $open[0], $user_id, $done ) : null,
			'sections'       => $sections,
			'recipes'        => $recipes,
			'recipes_source' => $source,
			'planned_meals'  => $planned,
			'vibono_tip'     => $tip ? self::summary( get_post( $tip[0] ), $user_id ) : null,
			'tip_of_the_day' => $tod ?: array( 'id' => null, 'text' => 'Iss dich satt – mit Genuss statt Verzicht.' ),
			'points'         => array(
				'balance'                => Points::balance( $user_id ),
				'app_open_awarded_today' => Points::app_open_awarded_today( $user_id ),
			),
		);
	}
}
