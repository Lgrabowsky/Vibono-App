<?php
namespace Vibono\AppApi;

use Vibono\AppApi\Core\PointsMath;
use Vibono\AppApi\Core\StreakMath;

defined( 'ABSPATH' ) || exit;

/**
 * Admin-Oberfläche "Vibono-Punkte": Übersicht, Umrechnungskurs & Regeln, Aktionen, Punkte buchen,
 * App-Schnittstelle (Inhalts-Zuordnung, MyVibono-Speicherorte, Store-Regeln).
 */
class Admin {

	const CAP  = 'manage_woocommerce';
	const SLUG = 'vibono-points';

	public static function init(): void {
		add_action( 'admin_menu', array( self::class, 'menu' ) );
		add_action( 'admin_post_vibono_save_settings', array( self::class, 'save_settings' ) );
		add_action( 'admin_post_vibono_save_campaign', array( self::class, 'save_campaign' ) );
		add_action( 'admin_post_vibono_delete_campaign', array( self::class, 'delete_campaign' ) );
		add_action( 'admin_post_vibono_adjust_points', array( self::class, 'adjust_points' ) );
	}

	private static function cap(): string {
		return current_user_can( self::CAP ) ? self::CAP : 'manage_options';
	}

	public static function menu(): void {
		add_menu_page( 'Vibono-Punkte', 'Vibono-Punkte', self::cap(), self::SLUG, array( self::class, 'page' ), 'dashicons-awards', 56 );
	}

	private static function url( string $tab, array $args = array() ): string {
		return add_query_arg( array_merge( array( 'page' => self::SLUG, 'tab' => $tab ), $args ), admin_url( 'admin.php' ) );
	}

	private static function guard( string $action ): void {
		if ( ! current_user_can( self::cap() ) || ! check_admin_referer( $action ) ) {
			wp_die( 'Keine Berechtigung.' );
		}
	}

	public static function page(): void {
		$tab  = sanitize_key( $_GET['tab'] ?? 'overview' ); // phpcs:ignore
		$tabs = array(
			'overview'  => 'Übersicht',
			'rules'     => 'Kurs & Regeln',
			'campaigns' => 'Aktionen',
			'adjust'    => 'Punkte buchen',
			'app'       => 'App-Schnittstelle',
			'modules'   => 'Module & Anbindung',
		);
		echo '<div class="wrap"><h1>Vibono-Punkte</h1>';
		if ( isset( $_GET['msg'] ) ) { // phpcs:ignore
			printf( '<div class="notice notice-%s is-dismissible"><p>%s</p></div>', isset( $_GET['err'] ) ? 'error' : 'success', esc_html( wp_unslash( $_GET['msg'] ) ) ); // phpcs:ignore
		}
		echo '<nav class="nav-tab-wrapper">';
		foreach ( $tabs as $k => $label ) {
			printf( '<a class="nav-tab %s" href="%s">%s</a>', $k === $tab ? 'nav-tab-active' : '', esc_url( self::url( $k ) ), esc_html( $label ) );
		}
		echo '</nav>';
		$method = 'tab_' . ( isset( $tabs[ $tab ] ) ? $tab : 'overview' );
		self::$method();
		echo '</div>';
	}

	// ------------------------------------------------------------ Übersicht

	private static function tab_overview(): void {
		global $wpdb;
		$t        = Install::table( 'points_ledger' );
		$open     = (int) $wpdb->get_var( "SELECT COALESCE(SUM(points),0) FROM $t WHERE status = 'confirmed'" ); // phpcs:ignore
		$pending  = (int) $wpdb->get_var( "SELECT COALESCE(SUM(points),0) FROM $t WHERE status = 'pending' AND points > 0" ); // phpcs:ignore
		$eff      = PointsMath::effective_cents_per_point( (float) Settings::get( 'cents_per_point' ), Campaigns::all_for_math(), time() );
		$by       = $wpdb->get_results( $wpdb->prepare( "SELECT reason, COUNT(*) n, SUM(points) p FROM $t WHERE created_at >= %s AND status <> 'void' GROUP BY reason ORDER BY p DESC", gmdate( 'Y-m-d H:i:s', time() - 30 * DAY_IN_SECONDS ) ) );
		$labels   = self::reason_labels();
		echo '<h2>Stand</h2><table class="widefat striped" style="max-width:640px"><tbody>';
		printf( '<tr><td>Offene Punkte aller Kund*innen</td><td><strong>%s</strong> (Gegenwert aktuell %s €)</td></tr>', esc_html( number_format_i18n( $open ) ), esc_html( number_format_i18n( $open * $eff / 100, 2 ) ) );
		printf( '<tr><td>Vorgemerkt (Widerrufsfrist läuft)</td><td>%s</td></tr>', esc_html( number_format_i18n( $pending ) ) );
		printf( '<tr><td>Aktueller Wert je Punkt</td><td>%s Cent%s</td></tr>', esc_html( number_format_i18n( $eff, 2 ) ), $eff > (float) Settings::get( 'cents_per_point' ) ? ' (Einlöse-Aktion läuft)' : '' );
		if ( Streak::enabled() ) {
			$st     = Streak::stats();
			$levels = Streak::levels();
			$parts  = array();
			foreach ( $levels as $i => $l ) {
				$parts[] = sprintf( 'ab Tag %d: %d', $l['from_day'], $st['by_stage'][ $i ] ?? 0 );
			}
			printf( '<tr><td>Laufende Serien (App täglich öffnen)</td><td>%s, längste %s Tage<br><small>%s</small></td></tr>', esc_html( number_format_i18n( $st['active'] ) . ( 1 === $st['active'] ? ' Person' : ' Personen' ) ), esc_html( number_format_i18n( $st['longest'] ) ), esc_html( implode( ' · ', $parts ) ) );
		}
		echo '</tbody></table><h2>Letzte 30 Tage</h2><table class="widefat striped" style="max-width:640px"><thead><tr><th>Grund</th><th>Buchungen</th><th>Punkte</th></tr></thead><tbody>';
		foreach ( $by as $row ) {
			printf( '<tr><td>%s</td><td>%d</td><td>%s</td></tr>', esc_html( $labels[ $row->reason ] ?? $row->reason ), (int) $row->n, esc_html( number_format_i18n( (int) $row->p ) ) );
		}
		echo '</tbody></table>';
	}

	public static function reason_labels(): array {
		return array(
			'app_open'        => 'App geöffnet',
			'article_read'    => 'Artikel gelesen',
			'referral'        => 'Kund*in geworben',
			'referral_friend' => 'Willkommensbonus Geworbene',
			'purchase'        => 'Einkauf',
			'redeem'          => 'Eingelöst',
			'redeem_refund'   => 'Einlösung zurückgebucht',
			'admin'           => 'Manuelle Buchung',
			'migration'       => 'Übernahme Refer-a-friend',
			'expire'          => 'Verfallen',
		);
	}

	// ------------------------------------------------------- Kurs & Regeln

	private static function field( string $key, string $label, string $type = 'number', string $help = '', array $attrs = array() ): void {
		$v = Settings::get( $key );
		echo '<tr><th scope="row"><label for="' . esc_attr( $key ) . '">' . esc_html( $label ) . '</label></th><td>';
		if ( 'checkbox' === $type ) {
			printf( '<input type="hidden" name="s[%1$s]" value="0"><input type="checkbox" id="%1$s" name="s[%1$s]" value="1" %2$s>', esc_attr( $key ), checked( (bool) $v, true, false ) );
		} elseif ( 'select' === $type ) {
			printf( '<select id="%1$s" name="s[%1$s]">', esc_attr( $key ) );
			foreach ( $attrs['options'] as $ov => $ol ) {
				printf( '<option value="%s" %s>%s</option>', esc_attr( $ov ), selected( $v, $ov, false ), esc_html( $ol ) );
			}
			echo '</select>';
		} elseif ( 'list' === $type ) {
			printf( '<input type="text" class="regular-text" id="%1$s" name="s[%1$s]" value="%2$s">', esc_attr( $key ), esc_attr( implode( ', ', (array) $v ) ) );
		} else {
			printf( '<input type="%3$s" class="%4$s" id="%1$s" name="s[%1$s]" value="%2$s" step="%5$s">', esc_attr( $key ), esc_attr( (string) $v ), esc_attr( $type ), 'number' === $type ? 'small-text' : 'regular-text', esc_attr( $attrs['step'] ?? 'any' ) );
		}
		if ( $help ) {
			echo '<p class="description">' . esc_html( $help ) . '</p>';
		}
		echo '</td></tr>';
	}

	private static function form_start( string $section ): void {
		echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '">';
		echo '<input type="hidden" name="action" value="vibono_save_settings"><input type="hidden" name="section" value="' . esc_attr( $section ) . '">';
		wp_nonce_field( 'vibono_save_settings' );
		echo '<table class="form-table" role="presentation">';
	}

	private static function form_end(): void {
		echo '</table>';
		submit_button( 'Speichern' );
		echo '</form>';
	}

	private static function tab_rules(): void {
		self::form_start( 'rules' );
		self::field( 'cents_per_point', 'Wert eines Punktes (Cent)', 'number', 'Umrechnungskurs. Start: 1 Punkt = 1 Cent. Gilt sofort für alle neuen Einlösungen.' );
		echo '<tr><th colspan="2"><h2>Punkte verdienen</h2></th></tr>';
		self::field( 'earn_app_open', 'App täglich öffnen', 'number', 'Punkte einmal pro Kalendertag. Mit Serie: Punkte für Tag 1.' );
		self::field( 'earn_article_read', 'Artikel gelesen', 'number', 'Nur mit Lese-Nachweis, einmal je Artikel.' );
		self::field( 'article_read_daily_cap', 'Max. belohnte Artikel pro Tag' );
		self::field( 'earn_referral', 'Kund*in geworben', 'number', 'Für die werbende Person, nach der ersten bezahlten Bestellung der geworbenen Person.' );
		self::field( 'earn_referral_friend', 'Willkommensbonus für Geworbene' );
		self::field( 'referral_min_order_cents', 'Mindestbestellwert für Werbeprämie (Cent)' );
		self::field( 'earn_purchase_per_euro', 'Punkte je Euro Einkauf', 'number', 'Warenwert ohne Versand, nach Rabatten und Punkte-Einlösung. 5 = 5 % zurück bei 1 Cent/Punkt.' );
		self::field( 'pending_days', 'Vormerkzeit (Tage)', 'number', 'Kauf- und Empfehlungspunkte werden erst nach dieser Frist ab "Abgeschlossen" gutgeschrieben (Widerruf).' );
		self::streak_fields();
		echo '<tr><th colspan="2"><h2>Einlösen im Shop</h2></th></tr>';
		self::field( 'max_redeem_percent', 'Max. Anteil am Warenwert (%)' );
		self::field( 'min_redeem_points', 'Mindestens einzulösende Punkte' );
		echo '<tr><th colspan="2"><h2>Lese-Nachweis</h2></th></tr>';
		self::field( 'reading_wpm', 'Lesegeschwindigkeit (Wörter/Minute)' );
		self::field( 'reading_min_factor', 'Mindestanteil der Lesezeit', 'number', '0,4 = mindestens 40 % der erwarteten Lesezeit aktiv lesen.' );
		self::field( 'reading_min_seconds', 'Mindestens Sekunden' );
		self::field( 'reading_max_seconds', 'Höchstens Sekunden (Deckel)' );
		self::field( 'reading_min_scroll', 'Mindest-Scrolltiefe', 'number', '0,9 = bis 90 % des Artikels gescrollt.' );
		self::field( 'reading_quiz_mode', 'Quizfrage', 'select', 'Quizfragen pflegst du im Beitrag (Box "Vibono-Punkte: Quizfrage").', array( 'options' => array( 'off' => 'Aus', 'if_available' => 'Wenn im Beitrag hinterlegt', 'required' => 'Nur Beiträge mit Quizfrage belohnen' ) ) );
		self::field( 'reading_eligible_types', 'Belohnte Inhaltstypen', 'list', 'Kommagetrennt, z. B. post, my_coaching, rezepte' );
		self::form_end();
	}

	/** Serie (Streak) fürs tägliche Öffnen: Stufen-Tabelle, Schutztage, Verhalten beim Abreißen. */
	private static function streak_fields(): void {
		echo '<tr><th colspan="2"><h2>Serie fürs tägliche Öffnen</h2><p style="font-weight:normal;max-width:760px">Wer die App mehrere Tage in Folge öffnet, bekommt pro Tag mehr Punkte. Tag 1 bekommt den Wert von „App täglich öffnen“, ab den Tagen unten gilt der jeweils höhere Wert. Aktionen für „App geöffnet“ multiplizieren zusätzlich.</p></th></tr>';
		self::field( 'streak_enabled', 'Serie einschalten', 'checkbox', 'Aus = jeden Tag gleich viele Punkte (Wert von „App täglich öffnen“).' );
		$levels = StreakMath::levels( (int) Settings::get( 'earn_app_open' ), (array) Settings::get( 'streak_levels' ) );
		echo '<tr><th scope="row">Stufen</th><td><table class="widefat striped" style="max-width:420px"><thead><tr><th>ab Tag in Folge</th><th>Punkte pro Tag</th></tr></thead><tbody>';
		printf( '<tr><td>1</td><td>%d <small>(App täglich öffnen)</small></td></tr>', (int) $levels[0]['points'] );
		$rows = array_slice( $levels, 1 );
		$rows = array_pad( $rows, max( 6, count( $rows ) + 2 ), array( 'from_day' => '', 'points' => '' ) );
		foreach ( $rows as $l ) {
			printf(
				'<tr><td><input type="number" min="2" step="1" class="small-text" name="streak_levels[from_day][]" value="%s"></td><td><input type="number" min="0" step="1" class="small-text" name="streak_levels[points][]" value="%s"></td></tr>',
				esc_attr( (string) $l['from_day'] ),
				esc_attr( (string) $l['points'] )
			);
		}
		echo '</tbody></table><p class="description">Leere Zeilen werden ignoriert. Eine Stufe entfernen: beide Felder leeren. Weitere Zeilen erscheinen nach dem Speichern.</p></td></tr>';
		self::field( 'streak_grace_per_month', 'Schutztage pro Monat', 'number', 'So viele verpasste Tage pro Kalendermonat überbrückt die Serie automatisch. Verpasste Tage zählen nicht mit und bringen keine Punkte. 0 = kein Schutz.' );
		self::field(
			'streak_on_break',
			'Wenn die Serie reißt',
			'select',
			'Gilt, wenn mehr Tage fehlen, als Schutztage übrig sind.',
			array(
				'options' => array(
					'drop_level' => 'Eine Stufe zurückfallen (z. B. von Tag 20 auf Tag 7)',
					'reset'      => 'Neu bei Tag 1 beginnen',
				),
			)
		);
	}

	private static function tab_app(): void {
		self::form_start( 'app' );
		echo '<tr><th colspan="2"><p>Werte mit ANNAHME müssen nach Sichtung des Theme-Codes bestätigt werden.</p><h2>Inhalte</h2></th></tr>';
		self::field( 'lesson_post_type', 'Inhaltstyp Lektionen', 'text' );
		self::field( 'lesson_taxonomy', 'Taxonomie Kurse', 'text', 'Leer = automatisch die erste Taxonomie des Lektionstyps.' );
		self::field( 'lesson_kind_meta_key', 'Meta-Feld Lektionsart', 'text', 'ANNAHME: Feld mit wichtig|lesen|aufgaben|motivation|rezepte|hinweise|probleme|freiwillig.' );
		self::field( 'recipe_post_type', 'Inhaltstyp Rezepte', 'text' );
		self::field( 'tip_post_type', 'Inhaltstyp Vibono-Tipps', 'text' );
		self::field( 'tip_of_day_post_type', 'Inhaltstyp Tipp des Tages', 'text' );
		self::field( 'food_post_type', 'Inhaltstyp Lebensmittel (Energiedichte)', 'text' );
		self::field( 'food_kcal_meta_key', 'Meta-Feld kcal/100 g', 'text', 'ANNAHME' );
		self::field( 'recipe_ed_meta_key', 'Meta-Feld Energiedichte Rezept', 'text', 'ANNAHME' );
		self::field( 'recipe_ingredients_meta_key', 'Feld Rezept-Zutaten', 'text', 'Für die Einkaufsliste der App. Leer = automatisch: WP Recipe Maker, sonst Felder „zutaten“ oder „ingredients“ (ACF-Wiederholer oder Text, eine Zutat je Zeile).' );
		self::field( 'recipe_servings_meta_key', 'Feld Portionen', 'text', 'Leer = automatisch: „portionen“ oder „servings“.' );
		$phases = (array) Settings::get( 'phase_terms' );
		foreach ( array( 'vorbereitung' => 'Vorbereitung', 'phase1' => 'Phase 1 (Umstellungstage)', 'phase2' => 'Phase 2', 'phase3' => 'Phase 3' ) as $k => $l ) {
			printf( '<tr><th>Kurse %s</th><td><input type="text" class="regular-text" name="phase_terms[%s]" value="%s"><p class="description">Kurs-IDs (Begriff-IDs), kommagetrennt, z. B. 247, 248</p></td></tr>', esc_html( $l ), esc_attr( $k ), esc_attr( implode( ', ', (array) ( $phases[ $k ] ?? array() ) ) ) );
		}
		self::field( 'phase1_days', 'Tage Phase 1' );
		self::field( 'phase2_days', 'Tage Phase 2' );
		self::field( 'coaching_membership_plans', 'Mitgliedschaften mit Coaching-Zugang', 'list', 'Slugs, kommagetrennt. Leer = jede aktive Mitgliedschaft.' );
		echo '<tr><th colspan="2"><h2>MyVibono-Speicherorte (Nutzer-Meta)</h2><p>Leer = Daten liegen nur im Plugin. Gesetzt = App-Änderungen werden in dieses Feld gespiegelt und Website-Änderungen übernommen.</p></th></tr>';
		foreach ( array( 'favorites' => 'Lieblingsrezepte', 'lessons_done' => 'Erledigte Lektionen', 'courses_done' => 'Erledigte Kurse', 'weight' => 'Mein Gewicht', 'sport' => 'Mein Sport', 'weekplan' => 'Mein Wochenplan' ) as $k => $l ) {
			self::field( 'store_' . $k . '_meta', $l, 'text' );
		}
		echo '<tr><th colspan="2"><h2>App-Store-Regeln</h2><p>Siehe docs/APP-STORE.md. Mitgliedschafts-Links in der App nur nach rechtlicher Prüfung einschalten.</p></th></tr>';
		foreach ( array( 'ios' => 'iOS', 'android' => 'Android' ) as $pf => $pl ) {
			$v = (array) Settings::get( 'shop_links_' . $pf );
			echo '<tr><th>' . esc_html( $pl ) . ': Links in der App</th><td>';
			foreach ( array( 'physical_products' => 'Shop (physische Produkte)', 'points_redemption' => 'Punkte im Shop einlösen', 'memberships' => 'Mitgliedschaften' ) as $f => $fl ) {
				printf( '<label style="margin-right:16px"><input type="checkbox" name="links[%s][%s]" value="1" %s> %s</label>', esc_attr( $pf ), esc_attr( $f ), checked( ! empty( $v[ $f ] ), true, false ), esc_html( $fl ) );
			}
			echo '</td></tr>';
		}
		self::field( 'shop_url', 'Shop-URL', 'url' );
		self::field( 'min_app_version', 'Mindest-App-Version', 'text' );
		echo '<tr><th colspan="2"><h2>Energiedichte-Rechner (Bildauswertung)</h2></th></tr>';
		printf( '<tr><th>API-Schlüssel</th><td>%s<p class="description">Als Konstante VIBONO_ANTHROPIC_API_KEY in wp-config.php hinterlegen, nicht hier.</p></td></tr>', '' !== Settings::anthropic_key() ? '✅ hinterlegt' : '❌ fehlt' );
		printf( '<tr><th>SDK</th><td>%s</td></tr>', Vision::available() || is_readable( VIBONO_API_DIR . 'vendor/autoload.php' ) ? '✅ installiert' : '❌ fehlt (composer install --no-dev im Plugin-Ordner)' );
		self::field( 'vision_model', 'Modell', 'text' );
		self::field( 'vision_daily_limit', 'Bildauswertungen pro Nutzer*in und Tag' );
		self::form_end();
	}

	// ---------------------------------------------------- Module & Anbindung

	private static function tab_modules(): void {
		echo '<p style="max-width:760px">Jedes Modul lässt sich einzeln ein- und ausschalten. Ausgeschaltete Module ändern nichts an Website, Shop oder Theme. Empfohlene Reihenfolge und Rückbau: <code>docs/ANBINDUNG.md</code> im Plugin-Ordner.</p>';
		self::form_start( 'modules' );
		self::field( 'module_api', 'App-Schnittstelle', 'checkbox', 'Login, Synchronisation und Inhalte für die App unter /wp-json/vibono/v1. Auf der Website nicht sichtbar.' );
		self::field( 'points_enabled', 'Punkte vergeben', 'checkbox', 'Hauptschalter für alle Punkte (App, Lesen, Shop, Werben).' );
		self::field( 'module_shop', 'Punkte im Shop', 'checkbox', 'Punkte für Einkäufe, Einlösen im Warenkorb, Hinweis auf Produktseiten, Reiter „Vibono-Punkte“ in Mein Konto.' );
		self::field( 'module_referral', 'Freunde werben', 'checkbox', 'Empfehlungslinks (?vref=…) und Prämien für erste Bestellungen. Erst einschalten, wenn Refer a Friend abgeschaltet ist oder die Übernahme geplant ist.' );
		self::field( 'module_web_reading', 'Lesepunkte auf der Website', 'checkbox', 'Lädt ein kleines Skript auf belohnten Beitragsseiten für eingeloggte Nutzer*innen.' );
		self::field( 'myvibono_write', 'MyVibono-Daten auf die Website schreiben', 'checkbox', 'Aus = das Plugin liest die MyVibono-Felder des Themes nur. Erst einschalten, wenn die Speicherorte geprüft sind. Vor dem ersten Schreiben wird der alte Wert gesichert.' );
		self::field( 'delete_data_on_uninstall', 'Beim Löschen des Plugins alle Daten entfernen', 'checkbox', 'Aus = Tabellen und Punktestände bleiben beim Löschen erhalten. Vorher sichern: wp vibono export-points.' );
		self::form_end();

		echo '<h2>Systemprüfung</h2><table class="widefat striped" style="max-width:960px"><tbody>';
		$icons = array( 'ok' => '✅', 'warn' => '⚠️', 'error' => '❌', 'info' => 'ℹ️' );
		foreach ( Health::checks() as $c ) {
			printf( '<tr><td style="width:2em">%s</td><td style="width:16em"><strong>%s</strong></td><td>%s</td></tr>', esc_html( $icons[ $c['status'] ] ?? '' ), esc_html( $c['label'] ), esc_html( $c['detail'] ) );
		}
		echo '</tbody></table>';
	}

	public static function save_settings(): void {
		self::guard( 'vibono_save_settings' );
		$in       = (array) wp_unslash( $_POST['s'] ?? array() ); // phpcs:ignore
		$defaults = Settings::defaults();
		$out      = array();
		foreach ( $in as $k => $v ) {
			if ( ! array_key_exists( $k, $defaults ) ) {
				continue;
			}
			$d = $defaults[ $k ];
			if ( is_bool( $d ) ) {
				$out[ $k ] = (bool) $v;
			} elseif ( is_int( $d ) ) {
				$out[ $k ] = max( 0, (int) $v );
			} elseif ( is_float( $d ) ) {
				$out[ $k ] = max( 0.0, (float) str_replace( ',', '.', (string) $v ) );
			} elseif ( is_array( $d ) ) {
				$out[ $k ] = array_values( array_filter( array_map( 'trim', explode( ',', sanitize_text_field( (string) $v ) ) ) ) );
			} else {
				$out[ $k ] = sanitize_text_field( (string) $v );
			}
		}
		if ( 'rules' === ( $_POST['section'] ?? '' ) && isset( $_POST['streak_levels'] ) ) { // phpcs:ignore
			$sl     = (array) wp_unslash( $_POST['streak_levels'] ); // phpcs:ignore
			$days   = array_values( (array) ( $sl['from_day'] ?? array() ) );
			$points = array_values( (array) ( $sl['points'] ?? array() ) );
			$levels = array();
			foreach ( $days as $i => $d ) {
				if ( '' === trim( (string) $d ) || '' === trim( (string) ( $points[ $i ] ?? '' ) ) ) {
					continue;
				}
				$levels[] = array( 'from_day' => absint( $d ), 'points' => absint( $points[ $i ] ) );
			}
			// Sortieren, Dubletten und Tag < 2 entfernen; Tag 1 ist "App täglich öffnen".
			$out['streak_levels'] = array_slice( StreakMath::levels( 0, $levels ), 1 );
		}
		if ( isset( $out['streak_on_break'] ) && ! in_array( $out['streak_on_break'], StreakMath::MODES, true ) ) {
			$out['streak_on_break'] = 'drop_level';
		}
		if ( 'app' === ( $_POST['section'] ?? '' ) ) { // phpcs:ignore
			$pt = (array) wp_unslash( $_POST['phase_terms'] ?? array() ); // phpcs:ignore
			$out['phase_terms'] = array();
			foreach ( array( 'vorbereitung', 'phase1', 'phase2', 'phase3' ) as $k ) {
				$out['phase_terms'][ $k ] = array_values( array_filter( array_map( 'absint', explode( ',', (string) ( $pt[ $k ] ?? '' ) ) ) ) );
			}
			$links = (array) ( $_POST['links'] ?? array() ); // phpcs:ignore
			foreach ( array( 'ios', 'android' ) as $pf ) {
				$out[ 'shop_links_' . $pf ] = array(
					'physical_products' => ! empty( $links[ $pf ]['physical_products'] ),
					'memberships'       => ! empty( $links[ $pf ]['memberships'] ),
					'points_redemption' => ! empty( $links[ $pf ]['points_redemption'] ),
				);
			}
		}
		if ( isset( $out['cents_per_point'] ) && $out['cents_per_point'] <= 0 ) {
			wp_safe_redirect( self::url( 'rules', array( 'msg' => 'Der Wert eines Punktes muss größer als 0 sein.', 'err' => 1 ) ) );
			exit;
		}
		$old      = (float) Settings::get( 'cents_per_point' );
		$old_shop = Settings::on( 'module_shop' );
		Settings::update( $out );
		if ( isset( $out['module_shop'] ) && $out['module_shop'] !== $old_shop ) {
			// Reiter "Mein Konto → Vibono-Punkte" kommt oder geht: Permalink-Regeln neu aufbauen lassen.
			delete_option( 'rewrite_rules' );
		}
		if ( isset( $out['cents_per_point'] ) && $out['cents_per_point'] !== $old ) {
			// Kursänderungen nachvollziehbar protokollieren.
			$log   = (array) get_option( 'vibono_points_rate_log', array() );
			$log[] = array( 'at' => gmdate( 'c' ), 'by' => get_current_user_id(), 'from' => $old, 'to' => $out['cents_per_point'] );
			update_option( 'vibono_points_rate_log', array_slice( $log, -100 ), false );
		}
		wp_safe_redirect( self::url( sanitize_key( $_POST['section'] ?? 'rules' ), array( 'msg' => 'Gespeichert.' ) ) ); // phpcs:ignore
		exit;
	}

	// -------------------------------------------------------------- Aktionen

	private static function tab_campaigns(): void {
		$edit = isset( $_GET['edit'] ) ? absint( $_GET['edit'] ) : 0; // phpcs:ignore
		$cur  = null;
		foreach ( Campaigns::all_for_math() as $c ) {
			if ( $c['id'] === $edit ) {
				$cur = $c;
			}
		}
		$labels = self::reason_labels();
		echo '<h2>Aktionen</h2><p>Beispiele: „Doppelte Punkte fürs Werben, 2 Wochen“ = Art <em>Punkte verdienen</em>, Grund <em>Kund*in geworben</em>, Multiplikator 2. „Punkte eine Woche doppelt so viel wert“ = Art <em>Einlösewert</em>, Multiplikator 2. Überschneiden sich Aktionen, gilt die stärkste (kein Stapeln).</p>';
		echo '<table class="widefat striped"><thead><tr><th>Name</th><th>Art</th><th>Gilt für</th><th>×</th><th>Zeitraum</th><th>Status</th><th></th></tr></thead><tbody>';
		$now = time();
		foreach ( Campaigns::all_for_math() as $c ) {
			$status = ! $c['enabled'] ? 'deaktiviert' : ( $now < $c['starts_at'] ? 'geplant' : ( $now >= $c['ends_at'] ? 'beendet' : '<strong>läuft</strong>' ) );
			$del    = wp_nonce_url( admin_url( 'admin-post.php?action=vibono_delete_campaign&id=' . $c['id'] ), 'vibono_delete_campaign' );
			printf(
				'<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s – %s</td><td>%s</td><td><a href="%s">Bearbeiten</a> | <a href="%s" onclick="return confirm(\'Aktion löschen?\')">Löschen</a></td></tr>',
				esc_html( $c['name'] ),
				'earn' === $c['kind'] ? 'Punkte verdienen' : 'Einlösewert',
				esc_html( 'earn' === $c['kind'] ? ( $c['reasons'] ? implode( ', ', array_map( static fn( $r ) => $labels[ $r ] ?? $r, $c['reasons'] ) ) : 'alle' ) : 'Shop' ),
				esc_html( number_format_i18n( $c['multiplier'], 2 ) ),
				esc_html( wp_date( 'd.m.Y H:i', $c['starts_at'] ) ),
				esc_html( wp_date( 'd.m.Y H:i', $c['ends_at'] ) ),
				wp_kses_post( $status ),
				esc_url( self::url( 'campaigns', array( 'edit' => $c['id'] ) ) ),
				esc_url( $del )
			);
		}
		echo '</tbody></table>';

		$f = $cur ?: array( 'id' => 0, 'name' => '', 'description' => '', 'kind' => 'earn', 'reasons' => array(), 'multiplier' => 2, 'starts_at' => time(), 'ends_at' => time() + 14 * DAY_IN_SECONDS, 'enabled' => true );
		echo '<h2>' . ( $cur ? 'Aktion bearbeiten' : 'Neue Aktion' ) . '</h2>';
		echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '"><input type="hidden" name="action" value="vibono_save_campaign"><input type="hidden" name="id" value="' . (int) $f['id'] . '">';
		wp_nonce_field( 'vibono_save_campaign' );
		echo '<table class="form-table">';
		printf( '<tr><th>Name</th><td><input type="text" class="regular-text" name="name" required value="%s"></td></tr>', esc_attr( $f['name'] ) );
		printf( '<tr><th>Beschreibung (sichtbar in App und Shop)</th><td><textarea class="large-text" rows="2" name="description">%s</textarea></td></tr>', esc_textarea( $f['description'] ) );
		printf( '<tr><th>Art</th><td><label><input type="radio" name="kind" value="earn" %s> Punkte verdienen (Multiplikator auf neue Punkte)</label><br><label><input type="radio" name="kind" value="redeem" %s> Einlösewert (Punkte im Shop mehr wert)</label></td></tr>', checked( $f['kind'], 'earn', false ), checked( $f['kind'], 'redeem', false ) );
		echo '<tr><th>Gilt für (nur „verdienen“)</th><td>';
		foreach ( PointsMath::EARN_REASONS as $r ) {
			printf( '<label style="margin-right:16px"><input type="checkbox" name="reasons[]" value="%s" %s> %s</label>', esc_attr( $r ), checked( in_array( $r, $f['reasons'], true ), true, false ), esc_html( $labels[ $r ] ?? $r ) );
		}
		echo '<p class="description">Nichts angehakt = gilt für alle.</p></td></tr>';
		printf( '<tr><th>Multiplikator</th><td><input type="number" step="0.1" min="0.1" max="20" name="multiplier" value="%s"> <span class="description">2 = doppelt</span></td></tr>', esc_attr( (string) $f['multiplier'] ) );
		printf( '<tr><th>Beginn</th><td><input type="datetime-local" name="starts_at" required value="%s"></td></tr>', esc_attr( wp_date( 'Y-m-d\TH:i', $f['starts_at'] ) ) );
		printf( '<tr><th>Ende</th><td><input type="datetime-local" name="ends_at" required value="%s"> <span class="description">Ortszeit (%s)</span></td></tr>', esc_attr( wp_date( 'Y-m-d\TH:i', $f['ends_at'] ) ), esc_html( wp_timezone_string() ) );
		printf( '<tr><th>Aktiv</th><td><input type="checkbox" name="enabled" value="1" %s></td></tr>', checked( (bool) $f['enabled'], true, false ) );
		echo '</table>';
		submit_button( $cur ? 'Aktion speichern' : 'Aktion anlegen' );
		echo '</form>';
	}

	public static function save_campaign(): void {
		self::guard( 'vibono_save_campaign' );
		$tz  = wp_timezone();
		$p   = wp_unslash( $_POST ); // phpcs:ignore
		$to_utc = static function ( $local ) use ( $tz ) {
			try {
				return ( new \DateTimeImmutable( (string) $local, $tz ) )->format( 'c' );
			} catch ( \Exception $e ) {
				return '';
			}
		};
		$res = Campaigns::save(
			array(
				'name'        => $p['name'] ?? '',
				'description' => $p['description'] ?? '',
				'kind'        => $p['kind'] ?? '',
				'reasons'     => (array) ( $p['reasons'] ?? array() ),
				'multiplier'  => str_replace( ',', '.', (string) ( $p['multiplier'] ?? '' ) ),
				'starts_at'   => $to_utc( $p['starts_at'] ?? '' ),
				'ends_at'     => $to_utc( $p['ends_at'] ?? '' ),
				'enabled'     => ! empty( $p['enabled'] ),
			),
			absint( $p['id'] ?? 0 )
		);
		if ( is_wp_error( $res ) ) {
			wp_safe_redirect( self::url( 'campaigns', array( 'msg' => $res->get_error_message(), 'err' => 1 ) ) );
		} else {
			wp_safe_redirect( self::url( 'campaigns', array( 'msg' => 'Aktion gespeichert.' ) ) );
		}
		exit;
	}

	public static function delete_campaign(): void {
		self::guard( 'vibono_delete_campaign' );
		Campaigns::delete( absint( $_GET['id'] ?? 0 ) ); // phpcs:ignore
		wp_safe_redirect( self::url( 'campaigns', array( 'msg' => 'Aktion gelöscht.' ) ) );
		exit;
	}

	// ------------------------------------------------------- Punkte buchen

	private static function tab_adjust(): void {
		$email = sanitize_email( wp_unslash( $_GET['email'] ?? '' ) ); // phpcs:ignore
		echo '<h2>Kund*in suchen</h2><form method="get"><input type="hidden" name="page" value="' . esc_attr( self::SLUG ) . '"><input type="hidden" name="tab" value="adjust">';
		printf( '<input type="email" name="email" class="regular-text" placeholder="E-Mail" value="%s"> ', esc_attr( $email ) );
		submit_button( 'Suchen', 'secondary', '', false );
		echo '</form>';
		if ( ! $email ) {
			return;
		}
		$user = get_user_by( 'email', $email );
		if ( ! $user ) {
			echo '<p>Kein Konto mit dieser E-Mail.</p>';
			return;
		}
		$labels = self::reason_labels();
		printf( '<h2>%s</h2><p>Kontostand: <strong>%s Punkte</strong> · vorgemerkt %s · Empfehlungscode %s</p>', esc_html( $user->display_name ), esc_html( number_format_i18n( Points::balance( $user->ID ) ) ), esc_html( number_format_i18n( Points::pending( $user->ID ) ) ), esc_html( Referral::code_for( $user->ID ) ) );
		echo '<form method="post" action="' . esc_url( admin_url( 'admin-post.php' ) ) . '"><input type="hidden" name="action" value="vibono_adjust_points"><input type="hidden" name="user_id" value="' . (int) $user->ID . '">';
		wp_nonce_field( 'vibono_adjust_points' );
		echo '<table class="form-table"><tr><th>Punkte (+/−)</th><td><input type="number" name="points" required></td></tr><tr><th>Begründung (sieht die Kundin/der Kunde)</th><td><input type="text" class="regular-text" name="label" required></td></tr></table>';
		submit_button( 'Buchen' );
		echo '</form><h3>Verlauf</h3><table class="widefat striped"><thead><tr><th>Datum</th><th>Grund</th><th>Text</th><th>Punkte</th><th>×</th><th>Status</th></tr></thead><tbody>';
		foreach ( Points::ledger( $user->ID, 1, 100 )['items'] as $e ) {
			printf( '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', esc_html( wp_date( 'd.m.Y H:i', strtotime( $e['created_at'] ) ) ), esc_html( $labels[ $e['reason'] ] ?? $e['reason'] ), esc_html( $e['label'] ), esc_html( (string) $e['points'] ), esc_html( (string) $e['multiplier'] ), esc_html( $e['status'] ) );
		}
		echo '</tbody></table>';
	}

	public static function adjust_points(): void {
		self::guard( 'vibono_adjust_points' );
		$uid    = absint( $_POST['user_id'] ?? 0 ); // phpcs:ignore
		$points = (int) ( $_POST['points'] ?? 0 ); // phpcs:ignore
		$label  = sanitize_text_field( wp_unslash( $_POST['label'] ?? '' ) ); // phpcs:ignore
		$user   = get_userdata( $uid );
		if ( ! $user || ! $points || '' === $label ) {
			wp_safe_redirect( self::url( 'adjust', array( 'msg' => 'Bitte Punkte und Begründung angeben.', 'err' => 1 ) ) );
			exit;
		}
		if ( $points < 0 && Points::balance( $uid ) + $points < 0 ) {
			wp_safe_redirect( self::url( 'adjust', array( 'email' => $user->user_email, 'msg' => 'Der Kontostand darf nicht negativ werden.', 'err' => 1 ) ) );
			exit;
		}
		Points::book( $uid, $points, 'admin', $label );
		wp_safe_redirect( self::url( 'adjust', array( 'email' => $user->user_email, 'msg' => 'Gebucht.' ) ) );
		exit;
	}
}
