<?php
/**
 * Demodaten der Testumgebung: Lektionen, Rezepte, Tipps, Lebensmittel, Shop, Testkonten, Punkte, Aktionen.
 * Wird von einrichten.php beim Bauen einmal ausgeführt. Alle Punkte bucht das Plugin selbst
 * (Bestellungen, Empfehlung, Lesen) bzw. über seine Funktion für manuelle Buchungen.
 */

use Vibono\AppApi\Campaigns;
use Vibono\AppApi\Install;
use Vibono\AppApi\Points;
use Vibono\AppApi\Profile;
use Vibono\AppApi\Referral;
use Vibono\AppApi\Settings;
use Vibono\AppApi\SyncStore;

function vt_absaetze( array $absaetze ): string {
	return implode( "\n\n", array_map( static fn( $p ) => str_starts_with( $p, '<' ) ? $p : '<!-- wp:paragraph --><p>' . $p . '</p><!-- /wp:paragraph -->', $absaetze ) );
}

function vt_beitrag( string $typ, string $titel, string $inhalt, array $meta = array(), array $terms = array(), int $order = 0, string $auszug = '' ): int {
	$id = wp_insert_post(
		array(
			'post_type'    => $typ,
			'post_status'  => 'publish',
			'post_title'   => $titel,
			'post_content' => $inhalt,
			'post_excerpt' => $auszug,
			'menu_order'   => $order,
			'post_author'  => 1,
		),
		true
	);
	if ( is_wp_error( $id ) ) {
		throw new RuntimeException( $id->get_error_message() );
	}
	foreach ( $meta as $k => $v ) {
		update_post_meta( $id, $k, $v );
	}
	foreach ( $terms as $tax => $slugs ) {
		wp_set_object_terms( $id, $slugs, $tax );
	}
	return $id;
}

function vt_quiz( int $post_id, string $frage, array $antworten, int $richtig ): void {
	update_post_meta( $post_id, '_vibono_quiz', array( 'question' => $frage, 'answers' => $antworten, 'correct' => $richtig ) );
}

function vt_konto( string $email, string $vorname, string $nachname, string $beschreibung, array $adresse ): int {
	$uid = wc_create_new_customer( $email, strtolower( $vorname ), 'vibono-test', array( 'first_name' => $vorname, 'last_name' => $nachname ) );
	if ( is_wp_error( $uid ) ) {
		throw new RuntimeException( $uid->get_error_message() );
	}
	wp_update_user( array( 'ID' => $uid, 'display_name' => $vorname . ' ' . $nachname ) );
	$c = new WC_Customer( $uid );
	$c->set_billing_first_name( $vorname );
	$c->set_billing_last_name( $nachname );
	$c->set_billing_email( $email );
	$c->set_billing_address_1( $adresse[0] );
	$c->set_billing_postcode( $adresse[1] );
	$c->set_billing_city( $adresse[2] );
	$c->set_billing_country( 'DE' );
	$c->save();
	update_user_meta( $uid, '_vt_beschreibung', $beschreibung );
	update_user_meta( $uid, '_vt_testpasswort', 'vibono-test' );
	update_user_meta( $uid, '_vibono_privacy_consent', array( 'at' => gmdate( 'c' ), 'channel' => 'web', 'health_data' => true ) );
	return $uid;
}

function vt_sync( int $uid, string $collection, string $key, array $data = array() ): void {
	SyncStore::apply( $uid, array( 'collection' => $collection, 'key' => $key, 'op' => 'upsert', 'data' => $data, 'updated_at' => gmdate( 'c' ) ), (int) floor( microtime( true ) * 1000 ) );
}

function vt_demodaten_anlegen(): void {
	global $wpdb;
	$heute = new DateTimeImmutable( 'today', wp_timezone() );
	$tag   = static fn( int $offset ) => $heute->modify( ( $offset >= 0 ? '+' : '' ) . $offset . ' days' )->format( 'Y-m-d' );

	// ------------------------------------------------------------ Lektionen
	$kurse = array();
	foreach ( array(
		'vorbereitung' => 'Vorbereitung',
		'phase1'       => 'Phase 1: Umstellungstage',
		'phase2'       => 'Phase 2: Gewohnheiten ändern',
		'phase3'       => 'Phase 3: Satt essen & genießen',
	) as $key => $name ) {
		$t              = wp_insert_term( $name, 'kurs', array( 'slug' => $key ) );
		$kurse[ $key ] = (int) $t['term_id'];
	}

	$lektionen = array(
		array( 'vorbereitung', 'Willkommen im Vibono Coaching', 'wichtig', array(
			'Schön, dass du da bist! In den nächsten Wochen begleiten wir dich Schritt für Schritt zu einer Ernährung, die dich satt macht und trotzdem beim Abnehmen hilft. Du musst dafür keine Kalorien zählen und auf nichts verzichten, was du gerne isst.',
			'Das Vibono-Konzept hat drei Phasen. In den zwei Umstellungstagen gewöhnst du deinen Körper an leichtere Mahlzeiten. In der zweiten Phase änderst du nach und nach deine Gewohnheiten. In der dritten Phase isst du dich dauerhaft satt und genießt dabei.',
			'Jeden Tag findest du in der App einen kleinen nächsten Schritt: eine Lektion zum Lesen, eine Aufgabe oder ein Rezept. Plane etwa zehn Minuten am Tag ein. Wenn du einmal keine Zeit hast, ist das kein Problem. Du machst einfach am nächsten Tag weiter.',
			'Für das Lesen von Lektionen und Tipps bekommst du Vibono-Punkte. Die Punkte kannst du im Vibono-Shop einlösen. Lies dafür den Text in Ruhe bis zum Ende, die App merkt sich, dass du ihn gelesen hast.',
		) ),
		array( 'vorbereitung', 'Dein Einkauf für die Umstellungstage', 'aufgaben', array(
			'Bevor es losgeht, lohnt sich ein kleiner Einkauf. Für die Umstellungstage brauchst du vor allem Gemüse, etwas Obst, Magerquark oder Joghurt, Eier und Kräuter. Schau in deinen Wochenplan, dort stehen die Rezepte für die ersten Tage.',
			'Die App erstellt dir aus dem Wochenplan eine Einkaufsliste. Du kannst die Portionen anpassen, wenn du für mehrere Personen kochst. Hake ab, was du schon zu Hause hast.',
			'Deine Aufgabe für heute: Lege fest, an welchem Tag du startest, und trage das Datum in der App ein. Ein Wochentag mit wenig Terminen eignet sich gut.',
		) ),
		array( 'phase1', 'Warum zwei Umstellungstage?', 'lesen', array(
			'Die Umstellungstage sind der Start in dein neues Essverhalten. Du isst an diesen Tagen leichte, gemüsereiche Mahlzeiten mit wenig Fett. Dein Magen gewöhnt sich daran, mit größeren Mengen an leichten Lebensmitteln satt zu werden.',
			'Viele Teilnehmerinnen und Teilnehmer berichten, dass sie sich nach diesen Tagen leichter und wacher fühlen. Gleichzeitig merkst du, wie gut Gemüse, Kräuter und Gewürze schmecken können, wenn man sie bewusst zubereitet.',
			'Wichtig ist: Hunger gehört nicht dazu. Wenn du hungrig bist, iss mehr von den leichten Lebensmitteln, zum Beispiel eine weitere Portion Gemüsesuppe. Trink außerdem ausreichend Wasser oder ungesüßten Tee.',
			'Nach den zwei Tagen geht es mit Phase 2 weiter. Dort lernst du, wie du deine Lieblingsgerichte so veränderst, dass sie dich satt machen und trotzdem leichter sind.',
		), array( 'Was gehört bei den Umstellungstagen nicht dazu?', array( 'Gemüse in großen Mengen', 'Hungern', 'Viel Wasser trinken' ), 1 ) ),
		array( 'phase1', 'Rezepte für die Umstellungstage', 'rezepte', array(
			'Für die Umstellungstage haben wir Rezepte ausgewählt, die schnell gehen und lange satt machen. Du findest sie in der App unter Rezepte mit dem Merkmal „UT geeignet“.',
			'Unsere Favoriten sind die Gemüsesuppe mit Kräutern, der Quark mit Beeren und das Ofengemüse mit Kräuterdip. Koche ruhig eine größere Menge und iss sie über den Tag verteilt.',
		) ),
		array( 'phase2', 'Energiedichte einfach erklärt', 'lesen', array(
			'Die Energiedichte gibt an, wie viele Kalorien ein Lebensmittel pro Gramm hat. Gurke hat zum Beispiel etwa 0,1 Kalorien pro Gramm, Schokolade über 5. Von Lebensmitteln mit niedriger Energiedichte kannst du also viel essen, ohne viele Kalorien aufzunehmen.',
			'Im Vibono-Konzept teilen wir Lebensmittel in drei Gruppen ein. Grün sind Lebensmittel unter 1,5 Kalorien pro Gramm, davon darfst du dich satt essen. Gelb sind Lebensmittel zwischen 1,5 und 2,4, die du bewusst einsetzt. Rot sind Lebensmittel über 2,4, die du genießt, aber in kleinen Mengen.',
			'Der Trick ist, Gerichte zu mischen. Ein Nudelgericht mit viel Gemüse hat eine niedrigere Energiedichte als Nudeln mit Sahnesoße, schmeckt aber genauso gut. Mit dem Energiedichte-Rechner in der App kannst du deine eigenen Rezepte prüfen.',
			'Probiere es heute aus: Nimm ein Lieblingsrezept und überlege, wo du Gemüse ergänzen oder Fett sparen kannst.',
		), array( 'Ab welchem Wert gilt ein Lebensmittel im Vibono-Konzept als rot?', array( 'über 2,4 Kalorien pro Gramm', 'über 0,5 Kalorien pro Gramm', 'über 10 Kalorien pro Gramm' ), 0 ) ),
		array( 'phase2', 'Satt werden mit wenig Kalorien', 'wichtig', array(
			'Satt wirst du vor allem durch das Volumen deiner Mahlzeit, durch Eiweiß und durch Ballaststoffe. Eine große Schüssel Salat mit Hähnchen oder Linsen macht satter als ein kleines Croissant, obwohl sie weniger Kalorien hat.',
			'Beginne jede Hauptmahlzeit mit Gemüse oder einer Suppe. Iss langsam und lege zwischendurch das Besteck ab. Das Sättigungsgefühl kommt erst nach etwa zwanzig Minuten.',
		) ),
		array( 'phase2', 'Bewegung im Alltag', 'aufgaben', array(
			'Bewegung hilft beim Abnehmen und tut gut. Du musst dafür nicht ins Fitnessstudio. Jeder Spaziergang, jede Treppe und jede Radtour zählt.',
			'Deine Aufgabe: Gehe heute 20 Minuten zu Fuß und trage es in der App unter Sport ein.',
		) ),
		array( 'phase3', 'Dein Gewicht halten', 'lesen', array(
			'In Phase 3 geht es darum, dein neues Essverhalten zur Gewohnheit zu machen. Du kennst jetzt die Grundregeln der Energiedichte und weißt, welche Rezepte dir schmecken.',
			'Wiege dich einmal pro Woche, am besten immer am gleichen Wochentag. Schwankungen von ein bis zwei Kilo sind normal. Erst wenn das Gewicht über mehrere Wochen steigt, lohnt es sich, wieder genauer hinzuschauen.',
			'Feiere deine Erfolge! Schau dir in der App an, was du schon erreicht hast, und setze dir ein neues Etappenziel.',
		) ),
		array( 'phase3', 'Ausrutscher gelassen nehmen', 'hinweise', array(
			'Ein Stück Torte auf dem Geburtstag oder ein Abend mit Pizza wirft dich nicht zurück. Wichtig ist, dass du am nächsten Tag einfach normal weitermachst.',
			'Plane Genussmomente bewusst ein, statt sie dir zu verbieten. So bleibt das Vibono-Konzept alltagstauglich.',
		) ),
	);
	$lektion_ids = array();
	foreach ( $lektionen as $i => $l ) {
		$id = vt_beitrag( 'my_coaching', $l[1], vt_absaetze( $l[3] ), array( 'lesson_kind' => $l[2] ), array( 'kurs' => array( $kurse[ $l[0] ] ) ), $i + 1 );
		if ( ! empty( $l[4] ) ) {
			vt_quiz( $id, $l[4][0], $l[4][1], $l[4][2] );
		}
		// Ab Phase 2 nur für Mitglieder (Paywall wie auf vibono.de).
		if ( in_array( $l[0], array( 'phase2', 'phase3' ), true ) ) {
			update_post_meta( $id, '_vt_nur_mitglieder', '1' );
		}
		$lektion_ids[] = $id;
	}

	// --------------------------------------------------------------- Rezepte
	foreach ( array( 'vegetarisch' => 'Vegetarisch', 'vegan' => 'Vegan', 'ut-geeignet' => 'UT geeignet', 'laktosefrei' => 'Laktosefrei', 'glutenfrei' => 'Glutenfrei', 'schnell' => 'Schnell' ) as $slug => $name ) {
		wp_insert_term( $name, 'rezeptmerkmal', array( 'slug' => $slug ) );
	}
	$rezepte = array(
		array( 'Gemüsesuppe mit Kräutern', 4, 0.3, array( 'vegetarisch', 'vegan', 'ut-geeignet', 'laktosefrei', 'glutenfrei' ), "2 Karotten\n1 Stange Lauch\n1/4 Knollensellerie\n2 Kartoffeln\n1,5 l Gemüsebrühe\n1 Bund Petersilie\nSalz, Pfeffer", 'Gemüse putzen und klein schneiden. In der Brühe 20 Minuten köcheln lassen. Mit Kräutern, Salz und Pfeffer abschmecken.' ),
		array( 'Magerquark mit Beeren', 1, 0.8, array( 'vegetarisch', 'ut-geeignet', 'glutenfrei', 'schnell' ), "250 g Magerquark\n150 g Beeren (frisch oder TK)\n1 TL Honig\n2 EL Mineralwasser", 'Quark mit Mineralwasser cremig rühren, Beeren unterheben, mit Honig süßen.' ),
		array( 'Ofengemüse mit Kräuterdip', 2, 0.7, array( 'vegetarisch', 'ut-geeignet', 'glutenfrei' ), "1 Zucchini\n1 rote Paprika\n200 g Champignons\n1 rote Zwiebel\n1 EL Olivenöl\n200 g Joghurt 1,5 %\n1 Bund Schnittlauch", 'Gemüse in Stücke schneiden, mit Öl mischen und bei 200 Grad 25 Minuten backen. Joghurt mit Schnittlauch verrühren.' ),
		array( 'Linsen-Bolognese', 4, 1.1, array( 'vegetarisch', 'vegan', 'laktosefrei' ), "200 g rote Linsen\n1 Dose stückige Tomaten (400 g)\n2 Karotten\n1 Zwiebel\n1 Knoblauchzehe\n250 g Vollkornspaghetti\n1 TL Oregano", 'Zwiebel, Knoblauch und Karotten andünsten, Linsen und Tomaten zugeben, 15 Minuten köcheln. Mit Spaghetti servieren.' ),
		array( 'Hähnchen-Gemüse-Pfanne', 2, 0.9, array( 'laktosefrei', 'glutenfrei', 'schnell' ), "300 g Hähnchenbrust\n1 Brokkoli\n1 rote Paprika\n2 EL Sojasoße\n1 TL Öl\n1 Stück Ingwer", 'Hähnchen in Streifen schneiden und anbraten. Gemüse zugeben, mit Sojasoße und Ingwer abschmecken.' ),
		array( 'Overnight Oats mit Apfel', 1, 1.2, array( 'vegetarisch', 'schnell' ), "40 g Haferflocken\n150 ml Milch 1,5 %\n1 Apfel\n1 Prise Zimt", 'Haferflocken mit Milch mischen und über Nacht in den Kühlschrank stellen. Morgens mit geriebenem Apfel und Zimt servieren.' ),
		array( 'Kichererbsen-Salat', 2, 1.0, array( 'vegetarisch', 'vegan', 'laktosefrei', 'glutenfrei' ), "1 Dose Kichererbsen (240 g)\n1 Gurke\n200 g Kirschtomaten\n1/2 Bund Petersilie\n1 EL Olivenöl\n1 Zitrone", 'Kichererbsen abspülen, Gemüse würfeln, alles mit Zitronensaft, Öl und Petersilie mischen.' ),
		array( 'Lachs mit Spinat (nur für Mitglieder)', 2, 1.3, array( 'laktosefrei', 'glutenfrei' ), "2 Lachsfilets (je 125 g)\n500 g Blattspinat\n1 Knoblauchzehe\n1 Zitrone", 'Lachs in der Pfanne garen, Spinat mit Knoblauch zusammenfallen lassen, mit Zitrone servieren.' ),
	);
	$rezept_ids = array();
	foreach ( $rezepte as $r ) {
		$zutaten = array_map( static fn( $z ) => '<li>' . esc_html( $z ) . '</li>', explode( "\n", $r[4] ) );
		$inhalt  = vt_absaetze(
			array(
				'Ein Rezept aus dem Vibono-Kochbuch, ideal für jeden Tag.',
				'<!-- wp:heading --><h2>Zutaten</h2><!-- /wp:heading -->',
				'<!-- wp:list --><ul>' . implode( '', $zutaten ) . '</ul><!-- /wp:list -->',
				'<!-- wp:heading --><h2>Zubereitung</h2><!-- /wp:heading -->',
				$r[5],
			)
		);
		$id = vt_beitrag( 'rezepte', $r[0], $inhalt, array( 'zutaten' => $r[4], 'portionen' => $r[1], 'energiedichte' => str_replace( '.', ',', (string) $r[2] ) ), array( 'rezeptmerkmal' => $r[3] ) );
		if ( str_contains( $r[0], 'nur für Mitglieder' ) ) {
			update_post_meta( $id, '_vt_nur_mitglieder', '1' );
		}
		$rezept_ids[] = $id;
	}

	// ---------------------------------------------------------- Vibono-Tipps
	$bewegung = wp_insert_term( 'Bewegung', 'category', array( 'slug' => 'bewegung' ) );
	$tipps    = wp_insert_term( 'Tipps', 'category', array( 'slug' => 'tipps' ) );
	$tipp_daten = array(
		array( 'Abnehmen in 3 Phasen', array( 'tipps' ), array(
			'Das Vibono-Konzept besteht aus drei Phasen: zwei Umstellungstage, eine Phase zum Ändern der Gewohnheiten und eine dauerhafte Phase, in der du dich satt isst und genießt.',
			'In jeder Phase gibt es eigene Lektionen, Aufgaben und Rezepte. Die App zeigt dir jeden Tag, was als Nächstes dran ist, damit du nicht selbst planen musst.',
			'Wer sich an die Grundregeln hält, nimmt in der Regel ohne Hunger ab. Das Wichtigste ist, dass du Lebensmittel mit niedriger Energiedichte bevorzugst und genug trinkst.',
		), array( 'Wie viele Phasen hat das Vibono-Konzept?', array( 'Zwei', 'Drei', 'Fünf' ), 1 ) ),
		array( 'Fünf Snacks unter 100 Kalorien', array( 'tipps' ), array(
			'Ein kleiner Snack zwischendurch ist erlaubt. Gut geeignet sind ein Apfel, eine Handvoll Kirschtomaten, ein Becher Joghurt, Gurkensticks mit Kräuterquark oder eine Tasse Gemüsebrühe.',
			'Alle diese Snacks haben eine niedrige Energiedichte. Du wirst satt, ohne viele Kalorien aufzunehmen. Stell dir am besten schon morgens eine Dose mit Gemüsesticks bereit.',
			'Weniger gut geeignet sind Nüsse, Müsliriegel und Trockenobst. Sie sind gesund, haben aber eine hohe Energiedichte. Genieße sie in kleinen Mengen.',
		) ),
		array( '10 Minuten Bewegung am Morgen', array( 'bewegung' ), array(
			'Mit zehn Minuten Bewegung am Morgen kommst du gut in den Tag. Beginne mit leichtem Marschieren auf der Stelle, kreise die Schultern und Arme und mache dann zehn Kniebeugen.',
			'Danach folgen zehn Ausfallschritte pro Seite und eine Minute im Unterarmstütz, wenn du magst auch auf den Knien. Zum Schluss dehnst du Beine und Rücken.',
			'Trage deine Bewegung in der App ein. So siehst du am Ende der Woche, wie aktiv du warst.',
		) ),
		array( 'Spazierengehen zählt', array( 'bewegung' ), array(
			'Du musst keinen Sport machen, um aktiver zu werden. Ein flotter Spaziergang von 30 Minuten verbraucht etwa 150 Kalorien und tut Kopf und Körper gut.',
			'Verabrede dich zum Spazierengehen statt zum Kaffee, nimm die Treppe statt des Aufzugs und steig eine Station früher aus dem Bus aus.',
		) ),
		array( 'Wasser trinken leicht gemacht (nur für Mitglieder)', array( 'tipps' ), array(
			'Ausreichend trinken hilft gegen Heißhunger. Stell dir eine Karaffe Wasser sichtbar auf den Tisch und gib Zitrone, Gurke oder Minze hinein.',
			'Ein Glas Wasser vor jeder Mahlzeit sorgt dafür, dass du schneller satt bist.',
		) ),
	);
	foreach ( $tipp_daten as $t ) {
		$cats = array_map( static fn( $s ) => 'bewegung' === $s ? (int) $bewegung['term_id'] : (int) $tipps['term_id'], $t[1] );
		$id   = vt_beitrag( 'post', $t[0], vt_absaetze( $t[2] ), array(), array( 'category' => $cats ) );
		if ( ! empty( $t[3] ) ) {
			vt_quiz( $id, $t[3][0], $t[3][1], $t[3][2] );
		}
		if ( str_contains( $t[0], 'nur für Mitglieder' ) ) {
			update_post_meta( $id, '_vt_nur_mitglieder', '1' );
		}
	}

	// -------------------------------------------------------- Tipps des Tages
	foreach ( array(
		'Iss dich satt – mit Genuss statt Verzicht.',
		'Starte jede Hauptmahlzeit mit Gemüse oder einer Suppe.',
		'Ein Glas Wasser vor dem Essen hilft beim Sattwerden.',
		'Gönn dir heute einen Spaziergang an der frischen Luft.',
		'Koch heute doppelt und nimm morgen den Rest mit.',
		'Kräuter und Gewürze machen leichte Gerichte richtig lecker.',
		'Wiege dich einmal pro Woche, immer am gleichen Tag.',
	) as $i => $text ) {
		vt_beitrag( 'apptipps', 'Tipp ' . ( $i + 1 ), $text );
	}

	// ------------------------------------------------------------ Lebensmittel
	foreach ( array(
		'Gurke' => 12, 'Tomate' => 18, 'Kopfsalat' => 11, 'Zucchini' => 19, 'Brokkoli' => 34, 'Karotte' => 36, 'Paprika rot' => 37,
		'Champignons' => 22, 'Apfel' => 54, 'Erdbeeren' => 32, 'Banane' => 93, 'Kartoffeln gekocht' => 72, 'Reis gekocht' => 130,
		'Vollkornnudeln gekocht' => 150, 'Vollkornbrot' => 210, 'Haferflocken' => 370, 'Magerquark' => 67, 'Joghurt 1,5 %' => 47,
		'Gouda' => 360, 'Ei' => 155, 'Hähnchenbrust' => 110, 'Lachs' => 200, 'Linsen gekocht' => 116, 'Kichererbsen gekocht' => 140,
		'Olivenöl' => 884, 'Butter' => 741, 'Walnüsse' => 654, 'Vollmilchschokolade' => 535, 'Gummibärchen' => 343, 'Pizza Margherita' => 250,
	) as $name => $kcal ) {
		vt_beitrag( 'energiedichte', $name, '', array( 'kcal' => (string) $kcal ) );
	}

	// ----------------------------------------------------------------- Shop
	update_option( 'woocommerce_default_country', 'DE' );
	update_option( 'woocommerce_currency', 'EUR' );
	update_option( 'woocommerce_currency_pos', 'right_space' );
	update_option( 'woocommerce_price_thousand_sep', '.' );
	update_option( 'woocommerce_price_decimal_sep', ',' );
	update_option( 'woocommerce_calc_taxes', 'no' );
	update_option( 'woocommerce_calc_shipping', 'no' );
	update_option( 'woocommerce_ship_to_countries', 'disabled' );
	update_option( 'woocommerce_enable_coupons', 'yes' );
	update_option( 'woocommerce_enable_guest_checkout', 'yes' );
	update_option( 'woocommerce_enable_checkout_login_reminder', 'yes' );
	update_option( 'woocommerce_enable_signup_and_login_from_checkout', 'yes' );
	update_option( 'woocommerce_enable_myaccount_registration', 'yes' );
	update_option( 'woocommerce_registration_generate_password', 'no' );
	update_option( 'woocommerce_coming_soon', 'no' );
	update_option( 'woocommerce_store_pages_only', 'no' );
	update_option( 'woocommerce_onboarding_profile', array( 'skipped' => true ) );
	update_option( 'woocommerce_task_list_hidden', 'yes' );
	update_option( 'woocommerce_show_marketplace_suggestions', 'no' );
	update_option( 'woocommerce_allow_tracking', 'no' );
	update_option( 'woocommerce_feature_order_attribution_enabled', 'no' );
	update_option( 'woocommerce_cod_settings', array( 'enabled' => 'yes', 'title' => 'Nachnahme (Test, es fließt kein Geld)', 'description' => 'Testumgebung: Die Bestellung wird sofort als „In Bearbeitung“ angelegt.', 'instructions' => '', 'enable_for_methods' => array(), 'enable_for_virtual' => 'yes' ) );
	update_option( 'woocommerce_bacs_settings', array( 'enabled' => 'no' ) );
	update_option( 'woocommerce_cheque_settings', array( 'enabled' => 'no' ) );

	// Warenkorb und Kasse klassisch (Shortcode), denn dort zeigt das Plugin das Feld zum Punkte-Einlösen.
	$seiten = array(
		'cart'      => array( 'Warenkorb', 'warenkorb', '<!-- wp:shortcode -->[woocommerce_cart]<!-- /wp:shortcode -->' ),
		'checkout'  => array( 'Kasse', 'kasse', '<!-- wp:shortcode -->[woocommerce_checkout]<!-- /wp:shortcode -->' ),
		'myaccount' => array( 'Mein Konto', 'mein-konto', '<!-- wp:shortcode -->[woocommerce_my_account]<!-- /wp:shortcode -->' ),
		'shop'      => array( 'Shop', 'shop', '' ),
	);
	foreach ( $seiten as $key => $s ) {
		$id = (int) get_option( 'woocommerce_' . $key . '_page_id' );
		$data = array( 'post_title' => $s[0], 'post_name' => $s[1], 'post_type' => 'page', 'post_status' => 'publish' );
		if ( '' !== $s[2] ) {
			$data['post_content'] = $s[2];
		}
		if ( $id && get_post( $id ) ) {
			$data['ID'] = $id;
			wp_update_post( $data );
		} else {
			$id = wp_insert_post( $data + array( 'post_content' => $s[2] ) );
			update_option( 'woocommerce_' . $key . '_page_id', $id );
		}
	}

	$produkte = array(
		array( 'Vibono Kochbuch „Satt & schlank“', '24.90', 'Über 100 Rezepte mit niedriger Energiedichte.' ),
		array( 'Eiweiß-Shake Vanille (500 g)', '29.90', 'Für den kleinen Hunger zwischendurch.' ),
		array( 'Gewürzset „Mediterran“', '12.90', 'Fünf Gewürzmischungen für leichte Gerichte.' ),
		array( 'Vibono Trinkflasche', '9.90', 'Damit du genug trinkst.' ),
	);
	foreach ( $produkte as $i => $p ) {
		$prod = new WC_Product_Simple();
		$prod->set_name( $p[0] );
		$prod->set_regular_price( $p[1] );
		$prod->set_short_description( $p[2] );
		$prod->set_description( $p[2] );
		$prod->set_menu_order( $i );
		$prod->set_status( 'publish' );
		$prod->save();
	}
	// Unsichtbarer Testartikel für simulierte Bestellungen mit frei gewähltem Betrag.
	$test = new WC_Product_Simple();
	$test->set_name( 'Testeinkauf (frei wählbarer Betrag)' );
	$test->set_regular_price( '1' );
	$test->set_catalog_visibility( 'hidden' );
	$test->set_virtual( true );
	$test->set_status( 'private' );
	$test->save();
	update_option( 'vt_testartikel_id', $test->get_id() );

	// ---------------------------------------------------------- Startseite
	$start = wp_insert_post(
		array(
			'post_type'    => 'page',
			'post_status'  => 'publish',
			'post_title'   => 'Vibono-Testumgebung',
			'post_name'    => 'start',
			'post_content' => vt_absaetze(
				array(
					'Diese Website läuft nur auf deinem Rechner. Sie hat keine Verbindung zu vibono.de und enthält nur Testdaten.',
					'<!-- wp:list --><ul><li><a href="/testzentrale/">Testzentrale</a>: alle Funktionen des Plugins so ausprobieren, wie die App sie nutzt</li><li><a href="/shop/">Shop</a>: einkaufen und Punkte einlösen</li><li><a href="/tipps/">Vibono-Tipps</a>: Artikel auf der Website lesen und Lesepunkte sammeln</li><li><a href="/wp-admin/admin.php?page=vibono-points">Backend → Vibono-Punkte</a>: Punktwerte, Aktionen, Buchungen</li></ul><!-- /wp:list -->',
					'Anmelden: Benutzer <strong>admin</strong>, Passwort <strong>vibono-test</strong>. Testkonten: anna@vibono-test.local, ben@vibono-test.local, clara@vibono-test.local, jeweils Passwort <strong>vibono-test</strong>.',
				)
			),
		)
	);
	$blog = wp_insert_post( array( 'post_type' => 'page', 'post_status' => 'publish', 'post_title' => 'Vibono-Tipps', 'post_name' => 'tipps' ) );
	update_option( 'show_on_front', 'page' );
	update_option( 'page_on_front', $start );
	update_option( 'page_for_posts', $blog );

	// ----------------------------------------------------- Plugin-Einstellungen
	// Module schaltet einrichten.php (Schritt „aktivieren“) ein.
	Settings::update(
		array(
			'lesson_taxonomy'      => 'kurs',
			'lesson_kind_meta_key' => 'lesson_kind',
			'phase_terms'          => array(
				'vorbereitung' => array( $kurse['vorbereitung'] ),
				'phase1'       => array( $kurse['phase1'] ),
				'phase2'       => array( $kurse['phase2'] ),
				'phase3'       => array( $kurse['phase3'] ),
			),
			'coaching_membership_plans' => array( 'coaching' ),
		)
	);

	// ------------------------------------------------------------- Testkonten
	$anna  = vt_konto( 'anna@vibono-test.local', 'Anna', 'Beispiel', 'Coaching-Mitglied, Tag 5 im Coaching, vegetarisch, hat schon Punkte gesammelt', array( 'Lindenweg 3', '50667', 'Köln' ) );
	$ben   = vt_konto( 'ben@vibono-test.local', 'Ben', 'Muster', 'Ohne Mitgliedschaft, von Anna geworben, startet morgen', array( 'Hauptstraße 12', '80331', 'München' ) );
	$clara = vt_konto( 'clara@vibono-test.local', 'Clara', 'Neu', 'Ganz neues Konto ohne Angaben und Punkte', array( 'Am Markt 1', '20095', 'Hamburg' ) );
	update_user_meta( $anna, Referral::CODE_META, 'ANNA7K' );
	update_user_meta( $ben, Referral::CODE_META, 'BEN4X2' );
	update_user_meta( $clara, Referral::CODE_META, 'CLARA9' );
	vt_mitglied_setzen( $anna, true );

	Profile::update(
		$anna,
		array(
			'onboarding' => array(
				'nutrition'      => array( 'diet' => 'vegetarisch', 'meat_amount' => 'keins', 'intolerances' => array(), 'dislikes' => array( 'Rosenkohl' ) ),
				'activity_level' => 'moderat_aktiv',
				'social'         => array( 'gender' => 'weiblich', 'age_group' => '40-49', 'household_size' => 2, 'children' => 0 ),
				'communication'  => array( 'notifications_per_day' => 2, 'topics' => array( 'rezepte', 'motivation', 'bewegung' ), 'quiet_hours' => array( 'start' => '21:00', 'end' => '07:00' ) ),
				'completed'      => true,
			),
			'goals'      => array( 'height_cm' => 168, 'start_weight_kg' => 82, 'target_weight_3m_kg' => 77, 'target_weight_6m_kg' => 73, 'target_weight_12m_kg' => 70, 'coaching_start_date' => $tag( -4 ) ),
		)
	);
	Profile::update(
		$ben,
		array(
			'onboarding' => array(
				'nutrition'      => array( 'diet' => 'alles', 'meat_amount' => 'wenig', 'intolerances' => array( 'laktose' ) ),
				'activity_level' => 'eingerostet',
				'completed'      => true,
			),
			'goals'      => array( 'height_cm' => 182, 'start_weight_kg' => 96, 'target_weight_3m_kg' => 91, 'target_weight_6m_kg' => 87, 'target_weight_12m_kg' => 84, 'coaching_start_date' => $tag( 1 ) ),
		)
	);

	// MyVibono-Daten von Anna (Gewicht, Sport, Favoriten, Wochenplan, erledigte Lektionen).
	foreach ( array( -4 => 82.0, -3 => 81.4, -2 => 81.1, -1 => 80.6 ) as $d => $kg ) {
		vt_sync( $anna, 'weight', $tag( $d ), array( 'kg' => $kg ) );
	}
	vt_sync( $anna, 'sport', 'demo-sport-0001', array( 'date' => $tag( -2 ), 'activity' => 'Spaziergang', 'minutes' => 30, 'note' => 'Mit dem Hund' ) );
	vt_sync( $anna, 'sport', 'demo-sport-0002', array( 'date' => $tag( -1 ), 'activity' => 'Radfahren', 'minutes' => 45, 'note' => '' ) );
	vt_sync( $anna, 'favorites', 'recipe:' . $rezept_ids[0] );
	vt_sync( $anna, 'favorites', 'recipe:' . $rezept_ids[3] );
	vt_sync( $anna, 'lessons_done', (string) $lektion_ids[0] );
	vt_sync( $anna, 'lessons_done', (string) $lektion_ids[1] );
	vt_sync( $anna, 'lessons_done', (string) $lektion_ids[2] );
	vt_sync( $anna, 'lessons_done', (string) $lektion_ids[3] );
	vt_sync( $anna, 'weekplan', $tag( 0 ) . ':fruehstueck', array( 'recipe_id' => $rezept_ids[1], 'portions' => 1 ) );
	vt_sync( $anna, 'weekplan', $tag( 0 ) . ':mittag', array( 'recipe_id' => $rezept_ids[6], 'portions' => 2 ) );
	vt_sync( $anna, 'weekplan', $tag( 0 ) . ':abend', array( 'recipe_id' => $rezept_ids[3], 'portions' => 2 ) );
	vt_sync( $anna, 'weekplan', $tag( 1 ) . ':abend', array( 'recipe_id' => $rezept_ids[2], 'portions' => 2 ) );

	// -------------------------------------------------------------- Punkte
	// Annas Vorgeschichte: Startguthaben (manuelle Buchung), ein abgeschlossener Einkauf mit abgelaufener Frist.
	Points::book( $anna, 1200, 'admin', 'Startguthaben der Testumgebung' );
	$order = vt_bestellung_anlegen( $anna, array( array( 'product_id' => wc_get_products( array( 'limit' => 1, 'orderby' => 'menu_order', 'order' => 'ASC', 'return' => 'ids' ) )[0], 'menge' => 2 ) ), 0, 'completed' );
	vt_frist_ueberspringen( $anna );

	// Ben wurde von Anna geworben und hat seine erste Bestellung bezahlt: Empfehlungspunkte für beide sind vorgemerkt.
	Referral::attach( $ben, $anna );
	vt_bestellung_anlegen( $ben, array(), 3490, 'processing' );

	// Ältere Buchungen etwas in die Vergangenheit legen, damit der Verlauf realistisch aussieht.
	$t = Install::table( 'points_ledger' );
	$wpdb->query( $wpdb->prepare( "UPDATE $t SET created_at = DATE_SUB(created_at, INTERVAL 20 DAY) WHERE user_id = %d AND reason IN ('admin','purchase')", $anna ) ); // phpcs:ignore

	// ------------------------------------------------------------- Aktionen
	$jetzt = time();
	Campaigns::save(
		array(
			'name'        => 'Lesewoche: doppelte Lesepunkte',
			'description' => 'Diese Woche gibt es für jeden gelesenen Artikel doppelte Punkte.',
			'kind'        => 'earn',
			'reasons'     => array( 'article_read' ),
			'multiplier'  => 2,
			'starts_at'   => gmdate( 'c', $jetzt - DAY_IN_SECONDS ),
			'ends_at'     => gmdate( 'c', $jetzt + 6 * DAY_IN_SECONDS ),
			'enabled'     => true,
		)
	);
	Campaigns::save(
		array(
			'name'        => 'Punktewoche: 1 Punkt = 2 Cent',
			'description' => 'Eine Woche lang sind deine Punkte im Shop doppelt so viel wert.',
			'kind'        => 'redeem',
			'multiplier'  => 2,
			'starts_at'   => gmdate( 'c', $jetzt + 3 * DAY_IN_SECONDS ),
			'ends_at'     => gmdate( 'c', $jetzt + 10 * DAY_IN_SECONDS ),
			'enabled'     => true,
		)
	);

	// Freigegebene Download-Ordner enthalten den Pfad des Build-Rechners; in der Testumgebung nicht gebraucht.
	$wpdb->query( "DELETE FROM {$wpdb->prefix}wc_product_download_directories WHERE url LIKE 'file://%'" ); // phpcs:ignore
	delete_option( 'vt_mails' );
	flush_rewrite_rules( false );

	printf( "  Demodaten: %d Lektionen, %d Rezepte, %d Tipps, Konten Anna (%d), Ben (%d), Clara (%d)\n", count( $lektion_ids ), count( $rezept_ids ), count( $tipp_daten ), $anna, $ben, $clara );
	printf( "  Punkte Anna: %d bestätigt, %d vorgemerkt · Ben: %d bestätigt, %d vorgemerkt\n", Points::balance( $anna ), Points::pending( $anna ), Points::balance( $ben ), Points::pending( $ben ) );
}
