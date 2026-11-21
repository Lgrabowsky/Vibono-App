<?php
use PHPUnit\Framework\TestCase;
use Vibono\AppApi\Core\HomeRules;
use Vibono\AppApi\Core\SyncRules;

final class HomeRulesTest extends TestCase {

	private function weight(): array {
		return HomeRules::challenge(
			array(
				'id'            => 7,
				'title'         => '7 kg bis Weihnachten',
				'kind'          => 'weight_loss',
				'target'        => '7',
				'starts_on'     => '2026-11-01',
				'ends_on'       => '2026-12-24',
				'recipe_max_ed' => '1,0',
				'recipe_tags'   => 'suppe, gemuese, suppe',
			)
		);
	}

	public function test_challenge_is_normalized(): void {
		$c = $this->weight();
		$this->assertSame( 'kg', $c['unit'] );
		$this->assertSame( 7.0, $c['target'] );
		$this->assertSame( 1.0, $c['recipe_max_ed'] );
		$this->assertSame( array( 'suppe', 'gemuese' ), $c['recipe_tags'] );
		$this->assertNull( $c['daily_target'] );

		$d = HomeRules::challenge( array( 'id' => 8, 'title' => 'Obst und Gemüse', 'kind' => 'daily_goal', 'target' => 14, 'daily_target' => '5', 'unit' => 'Portionen', 'ends_on' => 'kaputt' ) );
		$this->assertSame( 14, $d['target'] );
		$this->assertSame( 5, $d['daily_target'] );
		$this->assertNull( $d['ends_on'] );

		$this->assertNull( HomeRules::challenge( array( 'title' => 'X', 'kind' => 'unbekannt', 'target' => 3 ) ) );
		$this->assertNull( HomeRules::challenge( array( 'title' => 'X', 'kind' => 'collect', 'target' => 0 ) ) );
		$this->assertNull( HomeRules::challenge( array( 'title' => ' ', 'kind' => 'collect', 'target' => 5 ) ) );
	}

	public function test_active_challenges_joined_first_and_short_grace_after_end(): void {
		$w = $this->weight();
		$o = HomeRules::challenge( array( 'id' => 9, 'title' => '5 Lebensmittel', 'kind' => 'collect', 'target' => 5, 'ends_on' => '2026-11-30' ) );
		$f = HomeRules::challenge( array( 'id' => 10, 'title' => 'Zukunft', 'kind' => 'collect', 'target' => 5, 'starts_on' => '2027-01-01' ) );

		$list = HomeRules::active_challenges( array( $w, $o, $f ), '2026-11-21', array( 7 ) );
		$this->assertSame( array( 7, 9 ), array_column( $list, 'id' ) );
		$this->assertTrue( $list[0]['joined'] );
		$this->assertFalse( $list[1]['joined'] );

		// Nach dem Ende: Mitmachende sehen ihr Ergebnis noch 7 Tage, andere nicht.
		$this->assertSame( array( 7 ), array_column( HomeRules::active_challenges( array( $w, $o ), '2026-12-31', array( 7, 9 ) ), 'id' ) );
		$this->assertSame( array(), HomeRules::active_challenges( array( $w ), '2026-12-31', array() ) );
		$this->assertSame( array(), HomeRules::active_challenges( array( $w ), '2027-01-01', array( 7 ) ) );
	}

	public function test_news_filters_and_sorts(): void {
		$items = array(
			array( 'kind' => 'blog', 'title' => 'Alt', 'published_on' => '2026-10-01' ),
			array( 'kind' => 'blog', 'title' => 'Neu', 'published_on' => '2026-11-20' ),
			array( 'kind' => 'blog', 'title' => 'Neu 2', 'published_on' => '2026-11-19' ),
			array( 'kind' => 'blog', 'title' => 'Neu 3', 'published_on' => '2026-11-18' ),
			array( 'kind' => 'ebook', 'title' => 'eBook', 'published_on' => '2026-11-15' ),
			array( 'kind' => 'offer', 'title' => 'Angebot', 'published_on' => '2026-09-01', 'ends_on' => '2026-11-30' ),
			array( 'kind' => 'offer', 'title' => 'Vorbei', 'published_on' => '2026-11-01', 'ends_on' => '2026-11-10' ),
			array( 'kind' => 'club', 'title' => 'Später', 'published_on' => '2026-11-25', 'starts_on' => '2026-11-25' ),
			array( 'kind' => 'quatsch', 'title' => 'X', 'published_on' => '2026-11-21' ),
		);
		$android = HomeRules::news( $items, '2026-11-21', 21, 10, array( 'physical_products' => true, 'digital_products' => true ) );
		$this->assertSame( array( 'Neu', 'Neu 2', 'eBook', 'Angebot' ), array_column( $android, 'title' ) );

		// iOS: keine Kauf-Links für digitale Produkte.
		$ios = HomeRules::news( $items, '2026-11-21', 21, 10, array( 'physical_products' => true, 'digital_products' => false ) );
		$this->assertSame( array( 'Neu', 'Neu 2', 'Angebot' ), array_column( $ios, 'title' ) );

		$this->assertCount( 2, HomeRules::news( $items, '2026-11-21', 21, 2, array() ) );
	}

	public function test_quiz_changes_daily_and_skips_invalid_questions(): void {
		$pool = HomeRules::default_quiz();
		$a    = HomeRules::quiz_for( $pool, '2026-11-21' );
		$b    = HomeRules::quiz_for( $pool, '2026-11-22' );
		$this->assertNotSame( $a['id'], $b['id'] );
		$this->assertSame( $a, HomeRules::quiz_for( $pool, '2026-11-21' ) );
		$this->assertSame( $a, HomeRules::quiz_for( $pool, '2026-11-21' ) );
		foreach ( $pool as $q ) {
			$this->assertNotNull( HomeRules::quiz( $q ), $q['id'] );
		}
		$this->assertNull( HomeRules::quiz_for( array( array( 'question' => 'Nur eine Antwort?', 'answers' => array( 'Ja' ), 'correct' => 0 ) ), '2026-11-21' ) );
		$this->assertNull( HomeRules::quiz( array( 'question' => 'Falscher Index', 'answers' => array( 'A', 'B' ), 'correct' => 2 ) ) );
	}

	public function test_participation_is_validated_via_sync_rules(): void {
		list( $d, $err ) = SyncRules::validate(
			'challenges',
			'7',
			'upsert',
			array(
				'joined_on' => '2026-11-20',
				'start_kg'  => '84,0',
				'days'      => array( '2026-11-21' => 3, 'kein-datum' => 2, '2026-11-20' => 0 ),
				'items'     => array( ' Pastinake ', 'Pastinake', '' ),
			)
		);
		$this->assertNull( $err );
		$this->assertSame( 7, $d['challenge_id'] );
		$this->assertNull( $d['start_kg'] ); // "84,0" ist keine Zahl im JSON der App.
		$this->assertEquals( (object) array( '2026-11-21' => 3 ), $d['days'] );
		$this->assertSame( array( 'Pastinake' ), $d['items'] );

		$this->assertSame( 'invalid_key', SyncRules::validate( 'challenges', 'abc', 'upsert', array() )[1] );
		$this->assertSame( 'invalid_challenge', SyncRules::validate( 'challenges', '7', 'upsert', array( 'joined_on' => 'gestern' ) )[1] );
		$this->assertSame( 'invalid_challenge', SyncRules::validate( 'challenges', '7', 'upsert', array( 'joined_on' => '2026-11-20', 'start_kg' => 12 ) )[1] );
		$this->assertSame( array( 'challenge_id' => 7 ), SyncRules::validate( 'challenges', '7', 'delete', null )[0] );
	}

	public function test_add_days(): void {
		$this->assertSame( '2027-01-01', HomeRules::add_days( '2026-12-25', 7 ) );
		$this->assertSame( '2026-10-31', HomeRules::add_days( '2026-11-21', -21 ) );
	}
}
