<?php
/**
 * Inhaltstypen, wie sie das Theme auf vibono.de mitbringt (Annahmen aus dem Plugin, siehe dessen README):
 * Lektionen "my_coaching" mit Kursen, Rezepte "rezepte" mit Merkmalen, Tipps des Tages "apptipps",
 * Lebensmittel "energiedichte". Vibono-Tipps sind normale Beiträge.
 */

defined( 'ABSPATH' ) || exit;

add_action(
	'init',
	static function () {
		$common = array(
			'public'       => true,
			'show_ui'      => true,
			'show_in_rest' => true,
			'has_archive'  => true,
			'supports'     => array( 'title', 'editor', 'excerpt', 'thumbnail', 'custom-fields', 'page-attributes' ),
		);

		register_post_type(
			'my_coaching',
			array_merge(
				$common,
				array(
					'labels'        => array( 'name' => 'Mein Coaching', 'singular_name' => 'Lektion', 'add_new_item' => 'Neue Lektion' ),
					'menu_icon'     => 'dashicons-welcome-learn-more',
					'menu_position' => 20,
					'rewrite'       => array( 'slug' => 'mein-coaching' ),
				)
			)
		);
		register_taxonomy(
			'kurs',
			'my_coaching',
			array(
				'labels'            => array( 'name' => 'Kurse', 'singular_name' => 'Kurs' ),
				'hierarchical'      => true,
				'show_in_rest'      => true,
				'show_admin_column' => true,
			)
		);

		register_post_type(
			'rezepte',
			array_merge(
				$common,
				array(
					'labels'        => array( 'name' => 'Rezepte', 'singular_name' => 'Rezept', 'add_new_item' => 'Neues Rezept' ),
					'menu_icon'     => 'dashicons-carrot',
					'menu_position' => 21,
					'rewrite'       => array( 'slug' => 'rezepte' ),
				)
			)
		);
		register_taxonomy(
			'rezeptmerkmal',
			'rezepte',
			array(
				'labels'            => array( 'name' => 'Rezept-Merkmale', 'singular_name' => 'Merkmal' ),
				'hierarchical'      => false,
				'show_in_rest'      => true,
				'show_admin_column' => true,
			)
		);

		register_post_type(
			'apptipps',
			array_merge(
				$common,
				array(
					'labels'        => array( 'name' => 'Tipps des Tages', 'singular_name' => 'Tipp des Tages' ),
					'menu_icon'     => 'dashicons-lightbulb',
					'menu_position' => 22,
					'has_archive'   => false,
				)
			)
		);

		register_post_type(
			'energiedichte',
			array_merge(
				$common,
				array(
					'labels'        => array( 'name' => 'Lebensmittel', 'singular_name' => 'Lebensmittel' ),
					'menu_icon'     => 'dashicons-chart-bar',
					'menu_position' => 23,
				)
			)
		);
	},
	5
);

// Lebensmittel auf der Website: kcal-Wert unter dem Text zeigen (wie ein Theme es täte).
add_filter(
	'the_content',
	static function ( $html ) {
		if ( ! is_singular( 'energiedichte' ) || ! in_the_loop() ) {
			return $html;
		}
		return $html . '<p><strong>' . esc_html( (string) get_post_meta( get_the_ID(), 'kcal', true ) ) . ' kcal je 100 g</strong></p>';
	}
);
