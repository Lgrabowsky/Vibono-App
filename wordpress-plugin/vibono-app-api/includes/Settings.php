<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Zentrale Einstellungen (Option "vibono_api_settings").
 *
 * Werte mit "ANNAHME" hängen vom Theme-/Plugin-Code von vibono.de ab und müssen
 * nach Sichtung des Theme-Codes bestätigt oder angepasst werden.
 */
class Settings {

	const OPTION = 'vibono_api_settings';

	public static function defaults(): array {
		return array(
			// --- Module ---------------------------------------------------
			// Schalter für eine schrittweise Einführung. Ausgeschaltete Module registrieren keine
			// Hooks und ändern nichts an Website, Shop oder Theme (siehe docs/ANBINDUNG.md).
			'module_api'                => true,  // App-Schnittstelle unter /wp-json/vibono/v1 (nur für die App sichtbar).
			'module_shop'               => false, // Punkte im Shop sammeln/einlösen, Hinweis am Produkt, Reiter in "Mein Konto".
			'module_referral'           => false, // Freunde werben. Erst einschalten, wenn Refer a Friend abgeschaltet ist.
			'module_web_reading'        => false, // Lese-Nachweis und Lesepunkte auf der Website (Skript auf Beitragsseiten).
			'module_rewards'            => false, // Prämien: Punkte gegen exklusive Inhalte, eBooks/PDFs und Verlängerungsrabatt (App + Mein Konto).
			'myvibono_write'            => false, // App-Änderungen in die MyVibono-Felder des Themes schreiben (sonst nur lesen).
			'delete_data_on_uninstall'  => false, // Beim Löschen des Plugins alle Vibono-Daten entfernen (inkl. Punktestände).

			// --- Punkte ---------------------------------------------------
			'points_enabled'            => true,
			'cents_per_point'           => 1.0,   // 1 Punkt = 1 Cent (Vorgabe Vibono).
			'earn_app_open'             => 5,     // Vorschlag. Grundwert = Tag 1 der Serie.
			// Serie (Streak) fürs tägliche Öffnen: je mehr Tage in Folge, desto mehr Punkte pro Tag (Vorschlag).
			'streak_enabled'            => true,
			'streak_levels'             => array(
				array( 'from_day' => 3, 'points' => 6 ),
				array( 'from_day' => 7, 'points' => 8 ),
				array( 'from_day' => 14, 'points' => 10 ),
				array( 'from_day' => 30, 'points' => 12 ),
			),
			'streak_grace_per_month'    => 2,     // Schutztage: so viele verpasste Tage pro Monat halten die Serie.
			'streak_on_break'           => 'drop_level', // reset = zurück auf Tag 1 | drop_level = eine Stufe zurück.
			'earn_article_read'         => 10,    // Vorschlag. Artikel komplett gelesen (mit Lese-Nachweis).
			'article_read_daily_cap'    => 3,     // Max. belohnte Artikel pro Tag.
			// Coaching-Fortschritt (Vorschlag): Lektion erledigt und Kurs abgeschlossen.
			'earn_lesson_done'          => 10,
			'lesson_done_daily_cap'     => 5,     // Max. belohnte Lektionen pro Tag (0 = unbegrenzt).
			'earn_course_done'          => 50,    // Bonus, wenn alle Lektionen eines Kurses erledigt sind.
			'earn_referral'             => 500,   // Werbende Person, wenn Freund*in die erste Bestellung bezahlt hat.
			'earn_referral_friend'      => 200,   // Willkommensbonus für Geworbene (mit erster Bestellung).
			'referral_min_order_cents'  => 1500,  // Mindestbestellwert der ersten Bestellung.
			// Punkte für Einkäufe gehören seit dem 21.11.2026 nicht mehr zu den Anlässen (Vorgabe Vibono).
			// Bleibt abschaltbar vorhanden, falls Vibono es später wieder möchte.
			'earn_purchases'            => false,
			'earn_purchase_per_euro'    => 5,     // Nur wirksam mit earn_purchases. 5 Punkte je Euro = 5 % bei 1 Cent/Punkt.
			'pending_days'              => 14,    // Kauf-/Empfehlungspunkte erst nach Widerrufsfrist bestätigen.
			// Punkte als Guthaben an der Kasse für beliebige Produkte. Seit dem 21.11.2026 nicht mehr vorgesehen:
			// Punkte werden gegen Prämien eingelöst (module_rewards). Abschaltbar vorhanden.
			'redeem_at_checkout'        => false,
			'max_redeem_percent'        => 50,    // Max. Anteil des Warenkorbs (ohne Versand), der mit Punkten bezahlt werden kann.
			'min_redeem_points'         => 100,

			// --- Prämien ----------------------------------------------------
			// Welche Prämienarten die App selbst einlösen darf (sonst nur auf vibono.de unter Mein Konto).
			// Verlängerungsrabatt in der App standardmäßig aus: Gutschein für eine Mitgliedschaft außerhalb
			// der Stores (siehe docs/APP-STORE.md).
			'rewards_app_ios'           => array( 'content' => true, 'download' => true, 'renewal_discount' => false ),
			'rewards_app_android'       => array( 'content' => true, 'download' => true, 'renewal_discount' => false ),
			'reward_download_minutes'   => 15,    // Gültigkeit eines Download-Links.

			// --- Lese-Nachweis --------------------------------------------
			'reading_wpm'               => 220,   // Angenommene Lesegeschwindigkeit.
			'reading_min_factor'        => 0.4,   // Mind. 40 % der erwarteten Lesezeit aktiv lesen.
			'reading_min_seconds'       => 20,
			'reading_max_seconds'       => 300,   // Deckel, damit lange Artikel nicht unzumutbar werden.
			'reading_min_scroll'        => 0.9,
			'reading_quiz_mode'         => 'if_available', // off | if_available | required.
			'reading_heartbeat_seconds' => 10,
			'reading_eligible_types'    => array( 'post', 'my_coaching', 'rezepte', 'coaching_briefe' ),

			// --- Empfehlungen ---------------------------------------------
			'referral_param'            => 'vref',
			'referral_legacy_params'    => array( 'raf' ), // ANNAHME: Parameter von WPGens Refer-a-friend.
			'referral_cookie_days'      => 30,             // Wie bisher bei Refer-a-friend (cookieTime 30).
			'referral_legacy_meta_key'  => 'gens_referral_id', // ANNAHME: Nutzer-Meta mit altem RAF-Code.

			// --- Inhalte (ANNAHMEN aus dem MyCoaching-Quelltext) ---------
			'lesson_post_type'          => 'my_coaching',
			'lesson_taxonomy'           => '',        // Leer = erste Taxonomie von my_coaching automatisch.
			'lesson_kind_meta_key'      => '',        // Meta-Feld für wichtig|lesen|aufgaben|… (ANNAHME, unbekannt).
			'recipe_post_type'          => 'rezepte',
			'tip_post_type'             => 'post',    // Vibono-Tipp = Blogbeitrag unter /tipps/.
			'tip_of_day_post_type'      => 'apptipps',
			'food_post_type'            => 'energiedichte',
			'food_kcal_meta_key'        => 'kcal',    // ANNAHME.
			'recipe_ed_meta_key'        => 'energiedichte', // ANNAHME.
			'recipe_ingredients_meta_key' => '',      // Leer = automatisch (WP Recipe Maker, sonst "zutaten"/"ingredients"). ANNAHME.
			'recipe_servings_meta_key'  => '',        // Leer = automatisch ("portionen"/"servings"). ANNAHME.
			'phase_terms'               => array(
				'vorbereitung' => array(),
				'phase1'       => array(),
				'phase2'       => array(),
				'phase3'       => array(),
			),
			'phase1_days'               => 2,
			'phase2_days'               => 10,
			'coaching_membership_plans' => array(), // Leer = jede aktive Mitgliedschaft schaltet frei.

			// --- MyVibono-Speicherorte (ANNAHMEN, Theme-Code fehlt) -------
			// Leer = Daten nur im Plugin. Gesetzt = Plugin spiegelt in dieses Nutzer-Meta.
			'store_favorites_meta'      => '',
			'store_lessons_done_meta'   => '',
			'store_courses_done_meta'   => '',
			'store_weight_meta'         => '',
			'store_sport_meta'          => '',
			'store_weekplan_meta'       => '',

			// --- App / Store-Regeln ---------------------------------------
			'min_app_version'           => '1.0.0',
			'shop_url'                  => 'https://www.vibono.de/produkte/',
			// iOS: Punkte-Einlösen-Link standardmäßig aus, weil Apple ihn als Kauf-Link werten kann (siehe docs/APP-STORE.md).
			'shop_links_ios'            => array( 'physical_products' => true, 'memberships' => false, 'points_redemption' => false ),
			'shop_links_android'        => array( 'physical_products' => true, 'memberships' => false, 'points_redemption' => true ),
			'support_url'               => 'https://www.vibono.de/kontakt/',
			'privacy_url'               => 'https://www.vibono.de/datenschutz/',

			// --- Vision (Energiedichte) -----------------------------------
			'vision_model'              => 'claude-opus-5-5',
			'vision_daily_limit'        => 20,
		);
	}

	public static function ensure_defaults(): void {
		if ( false === get_option( self::OPTION ) ) {
			add_option( self::OPTION, self::defaults(), '', false );
		}
		if ( ! get_option( 'vibono_api_jwt_secret' ) && ! defined( 'VIBONO_JWT_SECRET' ) ) {
			add_option( 'vibono_api_jwt_secret', bin2hex( random_bytes( 32 ) ), '', false );
		}
	}

	public static function all(): array {
		$stored = get_option( self::OPTION, array() );
		return array_merge( self::defaults(), is_array( $stored ) ? $stored : array() );
	}

	/** @return mixed */
	public static function get( string $key ) {
		$all = self::all();
		return apply_filters( 'vibono_api_setting', $all[ $key ] ?? null, $key );
	}

	/** Ist ein Modul eingeschaltet? Module können per Filter "vibono_api_setting" erzwungen werden. */
	public static function on( string $module ): bool {
		return (bool) self::get( $module );
	}

	public static function update( array $values ): void {
		$merged = array_merge( self::all(), $values );
		update_option( self::OPTION, $merged, false );
	}

	public static function jwt_secret(): string {
		if ( defined( 'VIBONO_JWT_SECRET' ) && VIBONO_JWT_SECRET ) {
			return (string) VIBONO_JWT_SECRET;
		}
		$secret = get_option( 'vibono_api_jwt_secret' );
		if ( ! $secret ) {
			$secret = bin2hex( random_bytes( 32 ) );
			update_option( 'vibono_api_jwt_secret', $secret, false );
		}
		return (string) $secret;
	}

	public static function anthropic_key(): string {
		if ( defined( 'VIBONO_ANTHROPIC_API_KEY' ) && VIBONO_ANTHROPIC_API_KEY ) {
			return (string) VIBONO_ANTHROPIC_API_KEY;
		}
		$env = getenv( 'VIBONO_ANTHROPIC_API_KEY' );
		return $env ? (string) $env : (string) get_option( 'vibono_api_anthropic_key', '' );
	}
}
