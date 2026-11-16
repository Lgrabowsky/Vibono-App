<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\Ingredients;

final class IngredientsTest extends TestCase {

	private function line( string $s ): array {
		$i = Ingredients::parse_line( $s );
		return array( $i['amount'], $i['unit'], $i['name'] );
	}

	public function test_lines(): void {
		$this->assertSame( array( 200.0, 'g', 'Magerquark' ), $this->line( '200 g Magerquark' ) );
		$this->assertSame( array( 200.0, 'g', 'Magerquark' ), $this->line( '200g Magerquark' ) );
		$this->assertSame( array( 1.5, 'tl', 'Salz' ), $this->line( '1 1/2 TL Salz' ) );
		$this->assertSame( array( 0.5, 'l', 'Milch (1,5 %)' ), $this->line( '½ Liter Milch (1,5 %)' ) );
		$this->assertSame( array( 3.0, 'el', 'Olivenöl' ), $this->line( '2-3 EL Olivenöl' ) );
		$this->assertSame( array( 1.0, 'prise', 'Salz' ), $this->line( '1 Prise Salz' ) );
		$this->assertSame( array( 2.0, null, 'große Zwiebeln' ), $this->line( '2 große Zwiebeln' ) );
		$this->assertSame( array( 1.0, null, 'Lauchstange' ), $this->line( '1 Lauchstange' ) );
		$this->assertSame( array( 1.0, 'pck', 'Backpulver' ), $this->line( '1 Päckchen Backpulver' ) );
		$this->assertSame( array( null, null, 'Salz und Pfeffer' ), $this->line( 'Salz und Pfeffer' ) );
		$this->assertSame( array( 1.5, 'kg', 'Kartoffeln' ), $this->line( '1,5 kg Kartoffeln' ) );
		$this->assertNull( Ingredients::parse_line( '  ' ) );
	}

	public function test_text_with_groups(): void {
		$items = Ingredients::from_text( "<p>Für den Salat:</p><ul><li>1 Kopf Salat</li><li>200 g Tomaten</li></ul>Dressing:<br>2 EL Essig<br>" );
		$this->assertCount( 3, $items );
		$this->assertSame( 'Für den Salat', $items[0]['group'] );
		$this->assertSame( array( 1.0, 'kopf', 'Salat' ), array( $items[0]['amount'], $items[0]['unit'], $items[0]['name'] ) );
		$this->assertSame( 'Dressing', $items[2]['group'] );
		$this->assertSame( 'el', $items[2]['unit'] );
	}

	public function test_rows_and_wprm(): void {
		$rows = Ingredients::from_rows(
			array(
				array( 'menge' => '250', 'einheit' => 'Gramm', 'zutat' => 'Hähnchenbrust' ),
				array( 'zutat' => '1 TL Paprika edelsüß' ),
				'3 Eier',
			)
		);
		$this->assertSame( array( 'name' => 'Hähnchenbrust', 'amount' => 250.0, 'unit' => 'g', 'group' => null ), $rows[0] );
		$this->assertSame( 'tl', $rows[1]['unit'] );
		$this->assertSame( 3.0, $rows[2]['amount'] );

		$wprm = Ingredients::from_wprm( array( array( 'name' => '', 'ingredients' => array( array( 'amount' => '1/2', 'unit' => 'Bund', 'name' => 'Petersilie', 'notes' => 'gehackt' ) ) ) ) );
		$this->assertSame( array( 'name' => 'Petersilie (gehackt)', 'amount' => 0.5, 'unit' => 'bund', 'group' => null ), $wprm[0] );
	}

	public function test_servings(): void {
		$this->assertSame( 4, Ingredients::servings( '4 Portionen' ) );
		$this->assertSame( 2, Ingredients::servings( 'für 2 Personen' ) );
		$this->assertNull( Ingredients::servings( '' ) );
		$this->assertNull( Ingredients::servings( 0 ) );
	}
}
