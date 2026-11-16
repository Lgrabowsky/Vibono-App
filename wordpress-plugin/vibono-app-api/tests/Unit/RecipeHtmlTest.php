<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\RecipeHtml;

final class RecipeHtmlTest extends TestCase {

	public function test_wprm_container_removed(): void {
		$html = '<p>Einleitung mit Größe</p><div class="wprm-recipe"><div class="wprm-recipe-ingredients-container wprm-block"><h3>Zutaten</h3><ul><li>200 g Quark</li></ul></div><div class="wprm-recipe-instructions-container"><h3>Zubereitung</h3><ol><li>Rühren</li></ol></div></div>';
		list( $out, $removed ) = RecipeHtml::strip_ingredients( $html );
		$this->assertTrue( $removed );
		$this->assertStringNotContainsString( 'Quark', $out );
		$this->assertStringContainsString( 'Zubereitung', $out );
		$this->assertStringContainsString( 'Größe', $out );
	}

	public function test_heading_lists_and_group_lines_removed(): void {
		$html = "<p>Ein schneller Salat.</p>\n<h2>Zutaten für 2 Portionen</h2>\n<ul><li>1 Kopf Salat</li></ul>\n<p>Für das Dressing:</p>\n<ul><li>2 EL Essig</li></ul>\n<h2>Zubereitung</h2>\n<ol><li>Waschen</li></ol>";
		list( $out, $removed ) = RecipeHtml::strip_ingredients( $html );
		$this->assertTrue( $removed );
		$this->assertStringNotContainsString( 'Kopf Salat', $out );
		$this->assertStringNotContainsString( 'Essig', $out );
		$this->assertStringNotContainsString( 'Dressing', $out );
		$this->assertStringContainsString( '<h2>Zubereitung</h2>', $out );
		$this->assertStringContainsString( 'Ein schneller Salat.', $out );
	}

	public function test_bold_paragraph_heading(): void {
		list( $out, $removed ) = RecipeHtml::strip_ingredients( '<p><strong>Zutaten:</strong></p><ul><li>3 Eier</li></ul><p>Tipp: Eier vorher abschrecken.</p>' );
		$this->assertTrue( $removed );
		$this->assertStringNotContainsString( '3 Eier', $out );
		$this->assertStringContainsString( 'Tipp: Eier vorher abschrecken.', $out );
	}

	public function test_untouched_without_list_or_heading(): void {
		$html = '<h2>Zutaten</h2><p>Alles, was der Kühlschrank hergibt.</p>';
		$this->assertSame( array( $html, false ), RecipeHtml::strip_ingredients( $html ) );
		$html2 = '<p>Zutaten wie Quark machen satt.</p><ul><li>Punkt</li></ul>';
		$this->assertSame( array( $html2, false ), RecipeHtml::strip_ingredients( $html2 ) );
		$this->assertSame( array( '', false ), RecipeHtml::strip_ingredients( '' ) );
	}

	public function test_trailing_group_line_kept(): void {
		list( $out ) = RecipeHtml::strip_ingredients( '<h3>Zutaten</h3><ul><li>1 Apfel</li></ul><p>Hinweis:</p><p>Schmeckt auch kalt.</p>' );
		$this->assertStringNotContainsString( 'Apfel', $out );
		$this->assertStringContainsString( 'Hinweis:', $out );
	}
}
