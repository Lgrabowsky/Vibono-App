<?php
namespace Vibono\AppApi\Core;

/**
 * Regeln für die Startseite „Heute“ der App. Reine Logik, ohne WordPress testbar.
 *
 * - Challenges: Felder aus dem Backend normalisieren, laufende Challenges erkennen.
 * - Meldungen (News): sortieren, abgelaufene und für die Plattform gesperrte entfernen.
 * - Quiz des Tages: aus einem Fragenpool tageweise wechselnd wählen.
 * - Teilnahme an Challenges (Sync-Sammlung "challenges") prüfen.
 */
class HomeRules {

	const CHALLENGE_KINDS = array( 'weight_loss', 'daily_goal', 'collect' );

	const NEWS_KINDS = array( 'blog', 'offer', 'club', 'coaching_letter', 'ebook', 'info' );

	/** Meldungen, die auf den Shop verlinken: Art => Schalter in shop_links_<plattform>. */
	const NEWS_SHOP_FLAGS = array(
		'offer' => 'physical_products',
		'ebook' => 'digital_products',
	);

	/**
	 * Challenge aus Rohdaten (Beitrag + Meta) normalisieren. null = unvollständig.
	 *
	 * @param array $raw id, title, description, thumbnail_url, kind, target, unit, daily_target,
	 *                   starts_on, ends_on, recipe_tags (Liste oder Komma-Text), recipe_max_ed, suggestions.
	 */
	public static function challenge( array $raw ): ?array {
		$kind  = (string) ( $raw['kind'] ?? '' );
		$title = trim( (string) ( $raw['title'] ?? '' ) );
		if ( ! in_array( $kind, self::CHALLENGE_KINDS, true ) || '' === $title ) {
			return null;
		}
		$target = self::num( $raw['target'] ?? null );
		if ( null === $target || $target <= 0 ) {
			return null;
		}
		$daily = null;
		if ( 'daily_goal' === $kind ) {
			$daily = (int) ( self::num( $raw['daily_target'] ?? null ) ?? 1 );
			$daily = max( 1, min( 50, $daily ) );
		}
		$starts = (string) ( $raw['starts_on'] ?? '' );
		$ends   = (string) ( $raw['ends_on'] ?? '' );
		$max_ed = self::num( $raw['recipe_max_ed'] ?? null );
		$unit   = trim( (string) ( $raw['unit'] ?? '' ) );
		if ( '' === $unit ) {
			$unit = array( 'weight_loss' => 'kg', 'daily_goal' => 'Tage', 'collect' => 'Lebensmittel' )[ $kind ];
		}
		return array(
			'id'            => (int) ( $raw['id'] ?? 0 ),
			'kind'          => $kind,
			'title'         => $title,
			'description'   => trim( (string) ( $raw['description'] ?? '' ) ),
			'thumbnail_url' => ( $raw['thumbnail_url'] ?? null ) ?: null,
			'target'        => 'weight_loss' === $kind ? round( $target, 1 ) : (int) round( $target ),
			'unit'          => $unit,
			'daily_target'  => $daily,
			'starts_on'     => SyncRules::is_date( $starts ) ? $starts : null,
			'ends_on'       => SyncRules::is_date( $ends ) ? $ends : null,
			'recipe_tags'   => self::list( $raw['recipe_tags'] ?? array() ),
			'recipe_max_ed' => null !== $max_ed && $max_ed > 0 ? round( $max_ed, 2 ) : null,
			'suggestions'   => self::list( $raw['suggestions'] ?? array() ),
		);
	}

	/** Läuft die Challenge an diesem Tag (inkl. erstem und letztem Tag)? Offene Grenzen gelten als erfüllt. */
	public static function challenge_active( array $c, string $date ): bool {
		if ( ! empty( $c['starts_on'] ) && $date < $c['starts_on'] ) {
			return false;
		}
		return empty( $c['ends_on'] ) || $date <= $c['ends_on'];
	}

	/**
	 * Laufende Challenges, bei denen die Person mitmacht, zuerst; dann nach Ende (früheste zuerst).
	 *
	 * @param array $challenges normalisierte Challenges
	 * @param array $joined_ids IDs mit Teilnahme
	 */
	public static function active_challenges( array $challenges, string $date, array $joined_ids ): array {
		$joined = array_flip( array_map( 'intval', $joined_ids ) );
		$out    = array();
		foreach ( $challenges as $c ) {
			// Mitmachende sehen ihre Challenge auch nach dem Ende noch eine Woche (Ergebnis).
			$grace = isset( $joined[ $c['id'] ] ) && ! empty( $c['ends_on'] ) && $date > $c['ends_on'] && $date <= self::add_days( $c['ends_on'], 7 );
			if ( self::challenge_active( $c, $date ) || $grace ) {
				$c['joined'] = isset( $joined[ $c['id'] ] );
				$out[]       = $c;
			}
		}
		usort(
			$out,
			static function ( $a, $b ) {
				if ( $a['joined'] !== $b['joined'] ) {
					return $a['joined'] ? -1 : 1;
				}
				return strcmp( $a['ends_on'] ?? '9999-12-31', $b['ends_on'] ?? '9999-12-31' ) ?: $a['id'] <=> $b['id'];
			}
		);
		return $out;
	}

	/**
	 * Meldungen filtern und sortieren: abgelaufene, zu alte und für die Plattform gesperrte Einträge
	 * fallen weg; Neueste zuerst, je Art höchstens zwei, insgesamt höchstens $limit.
	 *
	 * @param array $items      Einträge mit kind, published_on, ends_on?, starts_on?
	 * @param array $shop_links Schalter der Plattform, z. B. array( 'physical_products' => true )
	 */
	public static function news( array $items, string $date, int $max_age_days, int $limit, array $shop_links ): array {
		$oldest = self::add_days( $date, -max( 1, $max_age_days ) );
		$out    = array();
		foreach ( $items as $n ) {
			$kind = (string) ( $n['kind'] ?? '' );
			if ( ! in_array( $kind, self::NEWS_KINDS, true ) || '' === trim( (string) ( $n['title'] ?? '' ) ) ) {
				continue;
			}
			if ( isset( self::NEWS_SHOP_FLAGS[ $kind ] ) && empty( $shop_links[ self::NEWS_SHOP_FLAGS[ $kind ] ] ) ) {
				continue;
			}
			if ( ! empty( $n['starts_on'] ) && $date < $n['starts_on'] ) {
				continue;
			}
			if ( ! empty( $n['ends_on'] ) && $date > $n['ends_on'] ) {
				continue;
			}
			// Meldungen mit Enddatum (Aktionen) gelten bis dahin, alle anderen nur eine Zeit lang als neu.
			if ( empty( $n['ends_on'] ) && ( $n['published_on'] ?? '' ) < $oldest ) {
				continue;
			}
			$out[] = $n;
		}
		usort( $out, static fn( $a, $b ) => strcmp( (string) ( $b['published_on'] ?? '' ), (string) ( $a['published_on'] ?? '' ) ) );
		$per_kind = array();
		$result   = array();
		foreach ( $out as $n ) {
			$per_kind[ $n['kind'] ] = ( $per_kind[ $n['kind'] ] ?? 0 ) + 1;
			if ( $per_kind[ $n['kind'] ] <= 2 ) {
				$result[] = $n;
			}
		}
		return array_slice( $result, 0, max( 1, $limit ) );
	}

	/** Quizfrage des Tages: wechselt täglich, für alle gleich. Ungültige Fragen werden übersprungen. */
	public static function quiz_for( array $pool, string $date ): ?array {
		$valid = array_values( array_filter( array_map( array( self::class, 'quiz' ), $pool ) ) );
		if ( ! $valid ) {
			return null;
		}
		$day = (int) ( ( strtotime( $date . ' 00:00:00 UTC' ) ?: 0 ) / 86400 );
		return $valid[ $day % count( $valid ) ];
	}

	public static function quiz( $q ): ?array {
		if ( ! is_array( $q ) ) {
			return null;
		}
		$answers = array_values( array_filter( array_map( static fn( $a ) => trim( (string) $a ), (array) ( $q['answers'] ?? array() ) ), 'strlen' ) );
		$correct = isset( $q['correct'] ) ? (int) $q['correct'] : -1;
		$text    = trim( (string) ( $q['question'] ?? '' ) );
		if ( '' === $text || count( $answers ) < 2 || count( $answers ) > 4 || $correct < 0 || $correct >= count( $answers ) ) {
			return null;
		}
		return array(
			'id'          => (string) ( $q['id'] ?? substr( md5( $text ), 0, 8 ) ),
			'question'    => $text,
			'answers'     => $answers,
			'correct'     => $correct,
			'explanation' => trim( (string) ( $q['explanation'] ?? '' ) ),
		);
	}

	/** Standard-Fragenpool, bis eigene Fragen hinterlegt sind (Filter "vibono_api_quiz_questions"). */
	public static function default_quiz(): array {
		return array(
			array(
				'id'          => 'ed-gurke',
				'question'    => 'Welches Lebensmittel hat die niedrigste Energiedichte?',
				'answers'     => array( 'Gurke', 'Banane', 'Vollkornbrot' ),
				'correct'     => 0,
				'explanation' => 'Gurke hat nur rund 0,1 kcal pro Gramm. Davon kannst du dich richtig satt essen.',
			),
			array(
				'id'          => 'ed-ampel',
				'question'    => 'Ab welcher Energiedichte ist ein Lebensmittel bei Vibono „grün“?',
				'answers'     => array( 'bis 1,5 kcal/g', 'bis 2,5 kcal/g', 'bis 4 kcal/g' ),
				'correct'     => 0,
				'explanation' => 'Grün heißt: bis 1,5 kcal pro Gramm. Davon darfst du essen, bis du satt bist.',
			),
			array(
				'id'          => 'satt-zeit',
				'question'    => 'Wie lange braucht das Sattgefühl ungefähr, bis es ankommt?',
				'answers'     => array( '5 Minuten', '20 Minuten', '1 Stunde' ),
				'correct'     => 1,
				'explanation' => 'Rund 20 Minuten. Wer langsam isst, merkt rechtzeitig, dass er satt ist.',
			),
			array(
				'id'          => 'suppe',
				'question'    => 'Warum ist eine Suppe als Vorspeise eine gute Idee?',
				'answers'     => array( 'Sie füllt den Magen mit wenig Kalorien', 'Sie beschleunigt den Stoffwechsel', 'Sie ersetzt das Trinken' ),
				'correct'     => 0,
				'explanation' => 'Viel Volumen, wenig Kalorien: Eine klare Gemüsesuppe vorweg macht schon halb satt.',
			),
			array(
				'id'          => 'mahlzeiten',
				'question'    => 'Wie oft am Tag solltest du dich bei Vibono richtig satt essen?',
				'answers'     => array( 'Einmal', 'Dreimal', 'So selten wie möglich' ),
				'correct'     => 1,
				'explanation' => 'Dreimal satt essen. Wer zwischendurch hungrig ist, greift schneller zu Snacks.',
			),
			array(
				'id'          => 'kaese',
				'question'    => 'Welche Energiedichte-Farbe hat Gouda?',
				'answers'     => array( 'Grün', 'Gelb', 'Rot' ),
				'correct'     => 2,
				'explanation' => 'Mit rund 3,6 kcal/g ist Gouda rot. Genießen ist erlaubt, nur eben in kleinen Mengen.',
			),
			array(
				'id'          => 'wasser',
				'question'    => 'Was hilft vor dem Essen gegen zu großen Hunger?',
				'answers'     => array( 'Ein großes Glas Wasser', 'Ein Schokoriegel', 'Nichts trinken' ),
				'correct'     => 0,
				'explanation' => 'Ein großes Glas Wasser vor dem Essen füllt den Magen ganz ohne Kalorien.',
			),
		);
	}

	/**
	 * Teilnahme an einer Challenge (Sync-Sammlung "challenges") prüfen und normalisieren.
	 *
	 * @return array{0: ?array, 1: ?string} [Daten, Fehlercode]
	 */
	public static function validate_participation( string $key, string $op, $data ): array {
		if ( ! ctype_digit( $key ) || strlen( $key ) > 12 ) {
			return array( null, 'invalid_key' );
		}
		if ( 'delete' === $op ) {
			return array( array( 'challenge_id' => (int) $key ), null );
		}
		$data   = is_array( $data ) ? $data : array();
		$joined = (string) ( $data['joined_on'] ?? '' );
		if ( ! SyncRules::is_date( $joined ) ) {
			return array( null, 'invalid_challenge' );
		}
		$start_kg = isset( $data['start_kg'] ) && is_numeric( $data['start_kg'] ) ? round( (float) $data['start_kg'], 1 ) : null;
		if ( null !== $start_kg && ( $start_kg < 30 || $start_kg > 400 ) ) {
			return array( null, 'invalid_challenge' );
		}
		$days = array();
		foreach ( (array) ( $data['days'] ?? array() ) as $d => $n ) {
			if ( SyncRules::is_date( (string) $d ) && is_numeric( $n ) && (int) $n > 0 ) {
				$days[ (string) $d ] = min( 50, (int) $n );
			}
		}
		if ( count( $days ) > 400 ) {
			return array( null, 'invalid_challenge' );
		}
		ksort( $days );
		$items = array();
		foreach ( (array) ( $data['items'] ?? array() ) as $i ) {
			$i = mb_substr( trim( (string) $i ), 0, 80 );
			if ( '' !== $i && ! in_array( $i, $items, true ) ) {
				$items[] = $i;
			}
		}
		if ( count( $items ) > 50 ) {
			return array( null, 'invalid_challenge' );
		}
		return array(
			array(
				'challenge_id' => (int) $key,
				'joined_on'    => $joined,
				'start_kg'     => $start_kg,
				'days'         => (object) $days,
				'items'        => $items,
			),
			null,
		);
	}

	public static function add_days( string $date, int $days ): string {
		$d = \DateTimeImmutable::createFromFormat( '!Y-m-d', $date, new \DateTimeZone( 'UTC' ) );
		if ( ! $d ) {
			return $date;
		}
		return $d->modify( ( $days >= 0 ? '+' : '' ) . $days . ' days' )->format( 'Y-m-d' );
	}

	/** Liste aus Array oder Komma-Text, ohne Leereinträge und Dubletten. */
	public static function list( $v ): array {
		$parts = is_array( $v ) ? $v : explode( ',', (string) $v );
		$out   = array();
		foreach ( $parts as $p ) {
			$p = trim( (string) $p );
			if ( '' !== $p && ! in_array( $p, $out, true ) ) {
				$out[] = $p;
			}
		}
		return $out;
	}

	private static function num( $v ): ?float {
		if ( null === $v || '' === $v ) {
			return null;
		}
		$v = str_replace( ',', '.', (string) $v );
		return is_numeric( $v ) ? (float) $v : null;
	}
}
