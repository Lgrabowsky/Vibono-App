<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\HomeRules;

defined( 'ABSPATH' ) || exit;

/**
 * Startseite „Heute“ der App (GET /home): redaktionelle Vorgaben für Rezeptvorschläge,
 * Quiz des Tages, Challenges und Meldungen (Blog, Coaching-Brief, eBook, Angebote, Club).
 *
 * Challenges und eigene Meldungen pflegt das Team im Backend unter „App: Heute“
 * (eigene Inhaltstypen des Plugins, nur im Backend sichtbar, keine Seiten auf der Website).
 * Blog, Coaching-Briefe, eBooks und Angebote kommen automatisch aus WordPress bzw. WooCommerce.
 * Die App rechnet Rezeptvorschläge, Saison, Wetter und Fortschritt selbst aus.
 */
class Home {

	const CHALLENGE_TYPE = 'vibono_challenge';
	const NOTICE_TYPE    = 'vibono_notice';
	const META_PREFIX    = '_vibono_';

	const CHALLENGE_FIELDS = array(
		'kind'          => 'Art',
		'target'        => 'Ziel',
		'unit'          => 'Einheit',
		'daily_target'  => 'Ziel pro Tag',
		'starts_on'     => 'Beginn',
		'ends_on'       => 'Ende',
		'recipe_tags'   => 'Passende Rezept-Schlagwörter',
		'recipe_max_ed' => 'Rezepte bis Energiedichte',
		'suggestions'   => 'Ideen (Sammel-Challenge)',
	);

	const NOTICE_FIELDS = array(
		'kind'      => 'Art',
		'url'       => 'Link',
		'cta'       => 'Text auf dem Knopf',
		'starts_on' => 'Zeigen ab',
		'ends_on'   => 'Zeigen bis',
	);

	public static function init(): void {
		Plugin::hook( 'init', array( self::class, 'register_types' ) );
		if ( is_admin() ) {
			Plugin::hook( 'add_meta_boxes', array( self::class, 'meta_boxes' ) );
			Plugin::hook( 'save_post_' . self::CHALLENGE_TYPE, array( self::class, 'save_challenge' ), 10, 2 );
			Plugin::hook( 'save_post_' . self::NOTICE_TYPE, array( self::class, 'save_notice' ), 10, 2 );
		}
	}

	public static function register_types(): void {
		$common = array(
			'public'              => false,
			'show_ui'             => true,
			'show_in_menu'        => true,
			'show_in_rest'        => false,
			'exclude_from_search' => true,
			'publicly_queryable'  => false,
			'has_archive'         => false,
			'rewrite'             => false,
			'menu_icon'           => 'dashicons-smartphone',
			'supports'            => array( 'title', 'excerpt', 'thumbnail' ),
			'capability_type'     => 'post',
		);
		register_post_type(
			self::CHALLENGE_TYPE,
			array_merge(
				$common,
				array(
					'labels'        => array(
						'name'          => 'App-Challenges',
						'singular_name' => 'App-Challenge',
						'add_new_item'  => 'Neue Challenge',
						'edit_item'     => 'Challenge bearbeiten',
						'menu_name'     => 'App: Challenges',
					),
					'menu_position' => 57,
				)
			)
		);
		register_post_type(
			self::NOTICE_TYPE,
			array_merge(
				$common,
				array(
					'labels'        => array(
						'name'          => 'App-Meldungen',
						'singular_name' => 'App-Meldung',
						'add_new_item'  => 'Neue Meldung',
						'edit_item'     => 'Meldung bearbeiten',
						'menu_name'     => 'App: Meldungen',
					),
					'menu_position' => 58,
				)
			)
		);
	}

	// --------------------------------------------------------------- Backend

	public static function meta_boxes(): void {
		add_meta_box( 'vibono_challenge', 'Einstellungen der Challenge', array( self::class, 'challenge_box' ), self::CHALLENGE_TYPE, 'normal', 'high' );
		add_meta_box( 'vibono_notice', 'Einstellungen der Meldung', array( self::class, 'notice_box' ), self::NOTICE_TYPE, 'normal', 'high' );
	}

	private static function meta( int $post_id, string $key ): string {
		return (string) get_post_meta( $post_id, self::META_PREFIX . $key, true );
	}

	private static function input( string $name, string $value, string $type = 'text', string $help = '' ): void {
		printf( '<input type="%s" name="vibono[%s]" value="%s" class="regular-text" step="any">', esc_attr( $type ), esc_attr( $name ), esc_attr( $value ) );
		if ( $help ) {
			echo '<p class="description">' . esc_html( $help ) . '</p>';
		}
	}

	private static function select( string $name, string $value, array $options ): void {
		printf( '<select name="vibono[%s]">', esc_attr( $name ) );
		foreach ( $options as $k => $l ) {
			printf( '<option value="%s" %s>%s</option>', esc_attr( $k ), selected( $value, $k, false ), esc_html( $l ) );
		}
		echo '</select>';
	}

	public static function challenge_box( \WP_Post $post ): void {
		wp_nonce_field( 'vibono_home_meta', 'vibono_home_nonce' );
		echo '<p>Titel = Name der Challenge (z. B. „7 kg bis Weihnachten“), Auszug = kurze Beschreibung in der App, Beitragsbild = Bild der Karte.</p><table class="form-table"><tbody>';
		echo '<tr><th>Art</th><td>';
		self::select(
			'kind',
			self::meta( $post->ID, 'kind' ) ?: 'weight_loss',
			array(
				'weight_loss' => 'Abnehmziel (z. B. 7 kg bis Weihnachten)',
				'daily_goal'  => 'Tagesziel (z. B. 5 Portionen Obst und Gemüse an 14 Tagen)',
				'collect'     => 'Sammeln (z. B. 5 neue Lebensmittel probieren)',
			)
		);
		echo '</td></tr><tr><th>Ziel</th><td>';
		self::input( 'target', self::meta( $post->ID, 'target' ), 'number', 'Abnehmziel: Kilo. Tagesziel: Anzahl Tage, an denen das Tagesziel erreicht wird. Sammeln: Anzahl.' );
		echo '</td></tr><tr><th>Ziel pro Tag</th><td>';
		self::input( 'daily_target', self::meta( $post->ID, 'daily_target' ), 'number', 'Nur Tagesziel, z. B. 5 (Portionen).' );
		echo '</td></tr><tr><th>Einheit</th><td>';
		self::input( 'unit', self::meta( $post->ID, 'unit' ), 'text', 'Z. B. kg, Portionen, Lebensmittel. Leer = passend zur Art.' );
		echo '</td></tr><tr><th>Zeitraum</th><td>';
		self::input( 'starts_on', self::meta( $post->ID, 'starts_on' ), 'date' );
		echo ' bis ';
		self::input( 'ends_on', self::meta( $post->ID, 'ends_on' ), 'date', 'Leer = ohne Beginn bzw. ohne Ende. Die App zeigt das Enddatum, aber keinen Countdown.' );
		echo '</td></tr><tr><th>Passende Rezepte</th><td>';
		self::input( 'recipe_tags', self::meta( $post->ID, 'recipe_tags' ), 'text', 'Schlagwörter (Begriff-Slugs), kommagetrennt, z. B. gemuese, obst. Solche Rezepte schlägt die App während der Challenge bevorzugt vor.' );
		echo '<br>';
		self::input( 'recipe_max_ed', self::meta( $post->ID, 'recipe_max_ed' ), 'number', 'Optional: nur Rezepte bis zu dieser Energiedichte bevorzugen, z. B. 1,0.' );
		echo '</td></tr><tr><th>Ideen</th><td>';
		self::input( 'suggestions', self::meta( $post->ID, 'suggestions' ), 'text', 'Nur Sammeln: Vorschläge zum Antippen, kommagetrennt, z. B. Pastinake, Topinambur, Mangold.' );
		echo '</td></tr></tbody></table>';
	}

	public static function notice_box( \WP_Post $post ): void {
		wp_nonce_field( 'vibono_home_meta', 'vibono_home_nonce' );
		echo '<p>Für Meldungen, die nicht automatisch kommen: was im Club oder in der Gruppe los ist, eigene Aktionen, Hinweise. Blogartikel, Coaching-Briefe, neue eBooks und Shop-Angebote erscheinen von selbst. Titel = Überschrift, Auszug = Text.</p><table class="form-table"><tbody>';
		echo '<tr><th>Art</th><td>';
		self::select(
			'kind',
			self::meta( $post->ID, 'kind' ) ?: 'club',
			array(
				'club'  => 'Aus Club und Gruppe',
				'offer' => 'Angebot / Aktion (nur wo Shop-Links erlaubt sind)',
				'info'  => 'Hinweis',
			)
		);
		echo '</td></tr><tr><th>Link</th><td>';
		self::input( 'url', self::meta( $post->ID, 'url' ), 'url', 'Optional, z. B. Link zur Gruppe oder zum Angebot.' );
		echo '</td></tr><tr><th>Knopf</th><td>';
		self::input( 'cta', self::meta( $post->ID, 'cta' ), 'text', 'Optional, z. B. „Zur Gruppe“.' );
		echo '</td></tr><tr><th>Zeitraum</th><td>';
		self::input( 'starts_on', self::meta( $post->ID, 'starts_on' ), 'date' );
		echo ' bis ';
		self::input( 'ends_on', self::meta( $post->ID, 'ends_on' ), 'date', 'Leer = ab Veröffentlichung für die eingestellte Zahl an Tagen.' );
		echo '</td></tr></tbody></table>';
	}

	private static function save_fields( int $post_id, array $fields ): void {
		if ( ! isset( $_POST['vibono_home_nonce'] ) || ! wp_verify_nonce( sanitize_text_field( wp_unslash( $_POST['vibono_home_nonce'] ) ), 'vibono_home_meta' ) ) {
			return;
		}
		if ( ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) || ! current_user_can( 'edit_post', $post_id ) ) {
			return;
		}
		$in = (array) wp_unslash( $_POST['vibono'] ?? array() ); // phpcs:ignore
		foreach ( array_keys( $fields ) as $k ) {
			$v = 'url' === $k ? esc_url_raw( (string) ( $in[ $k ] ?? '' ) ) : sanitize_text_field( (string) ( $in[ $k ] ?? '' ) );
			update_post_meta( $post_id, self::META_PREFIX . $k, $v );
		}
	}

	public static function save_challenge( int $post_id ): void {
		self::save_fields( $post_id, self::CHALLENGE_FIELDS );
	}

	public static function save_notice( int $post_id ): void {
		self::save_fields( $post_id, self::NOTICE_FIELDS );
	}

	// ------------------------------------------------------------------ Feed

	public static function feed( int $user_id, string $date, string $platform ): array {
		$links = 'web' === $platform
			? array( 'physical_products' => true, 'digital_products' => true )
			: (array) Settings::get( 'shop_links_' . $platform );
		$joined = array_map( 'intval', array_keys( SyncStore::current_map( $user_id, 'challenges' ) ) );
		$pool   = apply_filters( 'vibono_api_quiz_questions', HomeRules::default_quiz() );

		return array(
			'date'       => $date,
			'food'       => array(
				'keywords'  => array_values( (array) Settings::get( 'home_keywords' ) ),
				'spotlight' => '' !== trim( (string) Settings::get( 'home_spotlight' ) ) ? array( 'name' => trim( (string) Settings::get( 'home_spotlight' ) ) ) : null,
			),
			'plan'       => array(
				'quiz' => HomeRules::quiz_for( (array) $pool, $date ),
			),
			'challenges' => HomeRules::active_challenges( self::challenges(), $date, $joined ),
			'news'       => HomeRules::news( self::news_sources( $user_id ), $date, (int) Settings::get( 'home_news_max_age_days' ), (int) Settings::get( 'home_news_limit' ), $links ),
		);
	}

	/** Alle veröffentlichten Challenges, normalisiert. */
	public static function challenges(): array {
		$posts = get_posts(
			array(
				'post_type'      => self::CHALLENGE_TYPE,
				'post_status'    => 'publish',
				'posts_per_page' => 50,
				'orderby'        => 'date',
				'order'          => 'DESC',
			)
		);
		$out = array();
		foreach ( $posts as $p ) {
			$raw = array(
				'id'            => $p->ID,
				'title'         => html_entity_decode( get_the_title( $p ), ENT_QUOTES, 'UTF-8' ),
				'description'   => wp_strip_all_tags( $p->post_excerpt ),
				'thumbnail_url' => get_the_post_thumbnail_url( $p, 'medium_large' ) ?: null,
			);
			foreach ( array_keys( self::CHALLENGE_FIELDS ) as $k ) {
				$raw[ $k ] = self::meta( $p->ID, $k );
			}
			$c = HomeRules::challenge( $raw );
			if ( $c ) {
				$out[] = $c;
			}
		}
		return $out;
	}

	private static function item( string $kind, \WP_Post $p, array $extra = array() ): array {
		$thumb = get_the_post_thumbnail_url( $p, 'medium_large' );
		return array_merge(
			array(
				'id'            => $kind . ':' . $p->ID,
				'kind'          => $kind,
				'title'         => html_entity_decode( wp_strip_all_tags( get_the_title( $p ) ), ENT_QUOTES, 'UTF-8' ),
				'excerpt'       => wp_trim_words( wp_strip_all_tags( $p->post_excerpt ?: strip_shortcodes( $p->post_content ) ), 22 ),
				'thumbnail_url' => $thumb ?: null,
				'url'           => get_permalink( $p ),
				'content_id'    => null,
				'cta'           => null,
				'published_on'  => get_post_time( 'Y-m-d', false, $p ),
				'starts_on'     => null,
				'ends_on'       => null,
			),
			$extra
		);
	}

	private static function latest( string $post_type, int $n, array $extra_query = array() ): array {
		if ( '' === $post_type || ! post_type_exists( $post_type ) ) {
			return array();
		}
		return get_posts( array_merge( array( 'post_type' => $post_type, 'post_status' => 'publish', 'posts_per_page' => $n, 'orderby' => 'date', 'order' => 'DESC' ), $extra_query ) );
	}

	/** Meldungen aus allen Quellen; Filtern und Sortieren übernimmt HomeRules::news. */
	public static function news_sources( int $user_id ): array {
		$items = array();

		// Neue Blogartikel. Sind Vibono-Tipps ebenfalls Blogbeiträge, öffnet die App sie in der eigenen Leseansicht (mit Lesepunkten).
		$blog_type = (string) Settings::get( 'home_blog_post_type' );
		foreach ( self::latest( $blog_type, 2 ) as $p ) {
			$own     = Content::post_type( 'tip' ) === $blog_type;
			$items[] = self::item( 'blog', $p, array( 'content_id' => $own ? $p->ID : null ) );
		}

		// Coaching-Brief: nur mit Zugang, sonst wäre er über die App lesbar.
		foreach ( self::latest( (string) Settings::get( 'home_letter_post_type' ), 1 ) as $p ) {
			if ( Membership::can_view( $user_id, $p->ID ) ) {
				$items[] = self::item( 'coaching_letter', $p, array( 'cta' => 'Brief lesen' ) );
			}
		}

		// Neue eBooks und Angebote aus WooCommerce.
		if ( function_exists( 'wc_get_products' ) ) {
			$cat = (string) Settings::get( 'home_ebook_product_cat' );
			if ( '' !== $cat ) {
				foreach ( (array) wc_get_products( array( 'status' => 'publish', 'limit' => 1, 'orderby' => 'date', 'order' => 'DESC', 'category' => array( $cat ) ) ) as $prod ) {
					$p = get_post( $prod->get_id() );
					if ( $p ) {
						$items[] = self::item( 'ebook', $p, array( 'cta' => 'Ansehen' ) );
					}
				}
			}
			if ( function_exists( 'wc_get_product_ids_on_sale' ) ) {
				$ids = array_slice( array_map( 'intval', (array) wc_get_product_ids_on_sale() ), 0, 20 );
				rsort( $ids );
				foreach ( array_slice( $ids, 0, 2 ) as $id ) {
					$prod = wc_get_product( $id );
					$p    = get_post( $id );
					if ( ! $prod || ! $p || 'publish' !== $p->post_status || $prod->get_parent_id() ) {
						continue;
					}
					$to      = $prod->get_date_on_sale_to();
					$items[] = self::item(
						'offer',
						$p,
						array(
							'published_on' => self::today_if_older( $prod->get_date_on_sale_from() ? $prod->get_date_on_sale_from()->date( 'Y-m-d' ) : get_post_time( 'Y-m-d', false, $p ) ),
							'ends_on'      => $to ? $to->date( 'Y-m-d' ) : Core\HomeRules::add_days( Plugin::today(), 7 ),
							'cta'          => 'Zum Angebot',
						)
					);
				}
			}
		}

		// Eigene Meldungen (Club, Gruppe, Aktionen, Hinweise).
		foreach ( self::latest( self::NOTICE_TYPE, 10 ) as $p ) {
			$kind    = self::meta( $p->ID, 'kind' ) ?: 'club';
			$items[] = self::item(
				$kind,
				$p,
				array(
					'url'          => self::meta( $p->ID, 'url' ) ?: null,
					'cta'          => self::meta( $p->ID, 'cta' ) ?: null,
					'starts_on'    => self::meta( $p->ID, 'starts_on' ) ?: null,
					'ends_on'      => self::meta( $p->ID, 'ends_on' ) ?: null,
					'published_on' => self::meta( $p->ID, 'starts_on' ) ?: get_post_time( 'Y-m-d', false, $p ),
				)
			);
		}
		return apply_filters( 'vibono_api_home_news', $items, $user_id );
	}

	/** Laufende Angebote zählen als neu, auch wenn sie schon länger laufen. */
	private static function today_if_older( string $date ): string {
		$min = Core\HomeRules::add_days( Plugin::today(), -2 );
		return $date < $min ? $min : $date;
	}
}
