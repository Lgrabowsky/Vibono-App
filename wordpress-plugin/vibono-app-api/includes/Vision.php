<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

/**
 * Bildauswertung für den Energiedichte-Rechner über die Claude API (Anthropic PHP SDK).
 *
 * - API-Schlüssel nur auf dem Server: Konstante VIBONO_ANTHROPIC_API_KEY in wp-config.php
 *   (oder Umgebungsvariable gleichen Namens). Nie in der App.
 * - Das SDK wird per Composer in vendor/ mitgeliefert (composer install --no-dev im Plugin-Ordner).
 * - Strukturierte Ausgabe (JSON-Schema), damit die App feste Felder bekommt.
 * - Bilder werden nicht gespeichert.
 */
class Vision {

	const MAX_BYTES = 5242880; // 5 MB.
	const MIMES     = array( 'image/jpeg', 'image/png', 'image/webp' );

	public static function available(): bool {
		return '' !== Settings::anthropic_key() && self::load_sdk();
	}

	private static function load_sdk(): bool {
		if ( class_exists( '\Anthropic\Client' ) ) {
			return true;
		}
		$autoload = VIBONO_API_DIR . 'vendor/autoload.php';
		if ( is_readable( $autoload ) ) {
			require_once $autoload;
		}
		return class_exists( '\Anthropic\Client' );
	}

	/** @return array|\WP_Error [base64, mime] */
	public static function check_image( string $b64, string $mime ) {
		if ( ! in_array( $mime, self::MIMES, true ) ) {
			return Plugin::error( 'vibono_invalid_image', 'Bitte ein JPEG-, PNG- oder WebP-Bild senden.', 400 );
		}
		$b64 = preg_replace( '/^data:[^,]+,/', '', $b64 );
		$b64 = preg_replace( '/\s+/', '', (string) $b64 );
		$raw = base64_decode( $b64, true );
		if ( false === $raw || '' === $raw ) {
			return Plugin::error( 'vibono_invalid_image', 'Das Bild konnte nicht gelesen werden.', 400 );
		}
		if ( strlen( $raw ) > self::MAX_BYTES ) {
			return Plugin::error( 'vibono_image_too_large', 'Das Bild ist zu groß (max. 5 MB).', 413 );
		}
		return array( $b64, $mime );
	}

	public static function recipe_schema(): array {
		$num = array( 'type' => array( 'number', 'null' ) );
		return array(
			'type'                 => 'object',
			'additionalProperties' => false,
			'required'             => array( 'title', 'servings', 'ingredients' ),
			'properties'           => array(
				'title'       => array( 'type' => array( 'string', 'null' ) ),
				'servings'    => array( 'type' => array( 'integer', 'null' ) ),
				'ingredients' => array(
					'type'  => 'array',
					'items' => array(
						'type'                 => 'object',
						'additionalProperties' => false,
						'required'             => array( 'name', 'amount_g', 'kcal_per_100g', 'confidence', 'raw_text' ),
						'properties'           => array(
							'name'          => array( 'type' => 'string' ),
							'amount_g'      => $num,
							'kcal_per_100g' => $num,
							'confidence'    => array( 'type' => 'number' ),
							'raw_text'      => array( 'type' => 'string' ),
						),
					),
				),
			),
		);
	}

	public static function photo_schema(): array {
		return array(
			'type'                 => 'object',
			'additionalProperties' => false,
			'required'             => array( 'dish', 'portion_g', 'kcal_total', 'components', 'confidence', 'notes' ),
			'properties'           => array(
				'dish'       => array( 'type' => 'string' ),
				'portion_g'  => array( 'type' => 'number' ),
				'kcal_total' => array( 'type' => 'number' ),
				'components' => array(
					'type'  => 'array',
					'items' => array(
						'type'                 => 'object',
						'additionalProperties' => false,
						'required'             => array( 'name', 'share_pct' ),
						'properties'           => array(
							'name'      => array( 'type' => 'string' ),
							'share_pct' => array( 'type' => 'number' ),
						),
					),
				),
				'confidence' => array( 'type' => 'number' ),
				'notes'      => array( 'type' => 'string' ),
			),
		);
	}

	const RECIPE_PROMPT = 'Das Bild zeigt ein Rezept oder eine Zutatenliste (deutsch). Lies Titel, Portionen und jede Zutat aus. '
		. 'Rechne Mengen in Gramm um (z. B. 1 EL Öl ≈ 10 g, 1 mittelgroße Zwiebel ≈ 80 g, 1 Ei ≈ 55 g, Flüssigkeiten 1 ml ≈ 1 g). '
		. 'Schätze für jede Zutat typische kcal je 100 g nach deutschen Nährwerttabellen. raw_text ist die Originalzeile. '
		. 'confidence (0 bis 1) gibt an, wie sicher Menge und kcal sind. Unlesbares: null statt raten. Erfinde keine Zutaten.';

	const PHOTO_PROMPT = 'Das Foto zeigt ein Gericht. Schätze Portionsgröße in Gramm, Kalorien gesamt und die Hauptbestandteile mit Anteil am Gewicht in Prozent (Summe 100). '
		. 'Die Werte dienen der groben Einordnung der Energiedichte (kcal pro Gramm) im Vibono-Konzept, nicht der exakten Kalorienzählung. '
		. 'confidence (0 bis 1) drückt deine Sicherheit aus. notes: ein kurzer, freundlicher Hinweis auf Deutsch in Du-Form, z. B. was die Schätzung unsicher macht.';

	/** @return array|\WP_Error */
	public static function analyze( string $b64, string $mime, string $prompt, array $schema, string $hint = '' ) {
		if ( ! self::available() ) {
			return Plugin::error( 'vibono_vision_unavailable', 'Die Bildauswertung ist gerade nicht verfügbar.', 503 );
		}
		$client = new \Anthropic\Client( apiKey: Settings::anthropic_key() );
		$text   = $prompt . ( '' !== $hint ? "\n\nHinweis der Nutzerin bzw. des Nutzers: " . mb_substr( $hint, 0, 300 ) : '' );
		try {
			$message = $client->beta->messages->create(
				model: (string) Settings::get( 'vision_model' ),
				maxTokens: 4000,
				messages: array(
					array(
						'role'    => 'user',
						'content' => array(
							array(
								'type'   => 'image',
								'source' => array( 'type' => 'base64', 'mediaType' => $mime, 'data' => $b64 ),
							),
							array( 'type' => 'text', 'text' => $text ),
						),
					),
				),
				outputConfig: array(
					'effort' => 'low',
					'format' => array( 'type' => 'json_schema', 'schema' => $schema ),
				),
				fallbacks: 'default',
				betas: array( 'server-side-fallback-2026-07-01' ),
				requestOptions: array( 'timeout' => 60.0, 'maxRetries' => 1 ),
			);
		} catch ( \Anthropic\Core\Exceptions\RateLimitException $e ) {
			return Plugin::error( 'vibono_rate_limited', 'Gerade sind zu viele Anfragen unterwegs. Versuch es gleich noch einmal.', 429 );
		} catch ( \Anthropic\Core\Exceptions\APIStatusException $e ) {
			error_log( 'Vibono Vision API-Fehler: ' . $e->getMessage() ); // phpcs:ignore
			return Plugin::error( 'vibono_vision_unavailable', 'Die Bildauswertung ist gerade nicht verfügbar.', 503 );
		} catch ( \Anthropic\Core\Exceptions\APIConnectionException $e ) {
			return Plugin::error( 'vibono_vision_unavailable', 'Die Bildauswertung ist gerade nicht erreichbar.', 503 );
		}

		if ( 'refusal' === $message->stopReason ) {
			return Plugin::error( 'vibono_vision_declined', 'Dieses Bild können wir leider nicht auswerten.', 422 );
		}
		foreach ( $message->content as $block ) {
			if ( 'text' === $block->type ) {
				$data = json_decode( $block->text, true );
				if ( is_array( $data ) ) {
					return $data;
				}
			}
		}
		return Plugin::error( 'vibono_vision_unavailable', 'Die Bildauswertung hat kein Ergebnis geliefert.', 503 );
	}

	/** Summen ergänzen: Gesamtgewicht, kcal gesamt, kcal je Gramm. */
	public static function finish_recipe( array $d ): array {
		$g = 0.0;
		$k = 0.0;
		foreach ( (array) ( $d['ingredients'] ?? array() ) as $i ) {
			if ( null === $i['amount_g'] || null === $i['kcal_per_100g'] ) {
				continue; // Unvollständige Zeilen fließen nicht in die Summe ein; die App zeigt sie zum Ergänzen.
			}
			$g += (float) $i['amount_g'];
			$k += (float) $i['amount_g'] * (float) $i['kcal_per_100g'] / 100;
		}
		$d['total_g']    = $g > 0 ? round( $g ) : null;
		$d['kcal_total'] = $g > 0 ? round( $k ) : null;
		$d['kcal_per_g'] = $g > 0 ? round( $k / $g, 2 ) : null;
		return $d;
	}

	public static function finish_photo( array $d ): array {
		$d['kcal_per_g'] = ! empty( $d['portion_g'] ) ? round( (float) $d['kcal_total'] / (float) $d['portion_g'], 2 ) : 0;
		return $d;
	}
}
