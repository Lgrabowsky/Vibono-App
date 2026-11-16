<?php
namespace Vibono\AppApi\Core;

/**
 * Entfernt den Zutatenblock aus dem HTML eines Rezepts, wenn die App die Zutaten strukturiert
 * bekommt (eigene Liste mit Portionsregler). Sonst stünden sie doppelt da.
 *
 * Vorsichtig: Entfernt wird nur, was eindeutig Zutaten sind:
 *  1. der Zutatenbereich der Rezeptkarte von WP Recipe Maker (Klasse "wprm-recipe-ingredients-container"),
 *  2. sonst eine Überschrift "Zutaten …" (h2–h6 oder ein Absatz nur aus fettem Text) und die direkt
 *     folgenden Listen samt kurzer Zwischenzeilen wie "Für das Dressing:". Beim ersten anderen
 *     Element (z. B. Text der Zubereitung) wird aufgehört.
 */
class RecipeHtml {

	const WPRM_CLASSES = array( 'wprm-recipe-ingredients-container' );

	/** @return array{0: string, 1: bool} [HTML, ob etwas entfernt wurde] */
	public static function strip_ingredients( string $html ): array {
		if ( '' === trim( $html ) || ! class_exists( '\DOMDocument' ) ) {
			return array( $html, false );
		}
		$prev = libxml_use_internal_errors( true );
		$doc  = new \DOMDocument();
		$ok   = $doc->loadHTML( '<?xml encoding="UTF-8"><div id="vibono-root">' . $html . '</div>', LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD );
		libxml_clear_errors();
		libxml_use_internal_errors( $prev );
		$root = $ok ? $doc->getElementById( 'vibono-root' ) : null;
		if ( ! $root ) {
			return array( $html, false );
		}
		$xpath   = new \DOMXPath( $doc );
		$removed = false;

		foreach ( self::WPRM_CLASSES as $class ) {
			$nodes = $xpath->query( '//*[contains(concat(" ", normalize-space(@class), " "), " ' . $class . ' ")]' );
			foreach ( iterator_to_array( $nodes ) as $node ) {
				$node->parentNode->removeChild( $node );
				$removed = true;
			}
		}

		if ( ! $removed ) {
			foreach ( iterator_to_array( $xpath->query( '//h2|//h3|//h4|//h5|//h6|//p' ) ) as $heading ) {
				if ( ! self::is_ingredients_heading( $heading ) ) {
					continue;
				}
				$drop = array( $heading );
				$list = false;
				for ( $n = $heading->nextSibling; $n; $n = $n->nextSibling ) {
					if ( XML_TEXT_NODE === $n->nodeType && '' === trim( $n->textContent ) ) {
						$drop[] = $n;
						continue;
					}
					if ( XML_ELEMENT_NODE !== $n->nodeType ) {
						break;
					}
					$tag = strtolower( $n->nodeName );
					if ( 'ul' === $tag || 'ol' === $tag ) {
						$drop[] = $n;
						$list   = true;
						continue;
					}
					// Zwischenzeile vor der nächsten Liste ("Für das Dressing:").
					if ( in_array( $tag, array( 'p', 'h3', 'h4', 'h5', 'h6' ), true ) && preg_match( '/^.{1,60}:$/u', trim( $n->textContent ) ) ) {
						$drop[] = $n;
						continue;
					}
					break;
				}
				if ( ! $list ) {
					continue; // Überschrift ohne Liste: nichts anfassen.
				}
				// Zwischenzeilen am Ende (ohne folgende Liste) wieder behalten.
				while ( $drop && ! in_array( strtolower( end( $drop )->nodeName ), array( 'ul', 'ol' ), true ) ) {
					array_pop( $drop );
				}
				foreach ( $drop as $d ) {
					$d->parentNode->removeChild( $d );
				}
				$removed = true;
				break;
			}
		}

		if ( ! $removed ) {
			return array( $html, false );
		}
		$out = '';
		foreach ( $root->childNodes as $child ) {
			$out .= $doc->saveHTML( $child );
		}
		return array( $out, true );
	}

	private static function is_ingredients_heading( \DOMNode $n ): bool {
		$text = trim( preg_replace( '/\s+/u', ' ', $n->textContent ) );
		if ( ! preg_match( '/^(zutaten|ingredients)\b/iu', $text ) || mb_strlen( $text ) > 60 ) {
			return false;
		}
		if ( 'p' !== strtolower( $n->nodeName ) ) {
			return true;
		}
		// Absatz zählt nur als Überschrift, wenn er ausschließlich fetten Text enthält.
		foreach ( $n->childNodes as $c ) {
			if ( XML_TEXT_NODE === $c->nodeType && '' !== trim( $c->textContent ) ) {
				return false;
			}
			if ( XML_ELEMENT_NODE === $c->nodeType && ! in_array( strtolower( $c->nodeName ), array( 'strong', 'b' ), true ) ) {
				return false;
			}
		}
		return true;
	}
}
