<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

class Plugin {

	public static function boot(): void {
		Install::maybe_upgrade();

		Auth::init();
		WebSession::init();
		Referral::init();
		Points::init();
		Reading::init_web();
		Content::init();

		if ( class_exists( 'WooCommerce' ) ) {
			WooCommerce::init();
		}
		if ( is_admin() ) {
			Admin::init();
		}
		if ( defined( 'WP_CLI' ) && WP_CLI ) {
			\WP_CLI::add_command( 'vibono', Cli::class );
		}

		add_action( 'rest_api_init', array( self::class, 'routes' ) );
	}

	public static function routes(): void {
		( new Rest\ConfigController() )->register();
		( new Rest\AuthController() )->register();
		( new Rest\MeController() )->register();
		( new Rest\SyncController() )->register();
		( new Rest\ContentController() )->register();
		( new Rest\PointsController() )->register();
		( new Rest\ReadingController() )->register();
		( new Rest\ReferralController() )->register();
		( new Rest\EnergyController() )->register();
	}

	/** Heute als Kalendertag in Europe/Berlin (bzw. Zeitzone der Website). */
	public static function today(): string {
		return wp_date( 'Y-m-d' );
	}

	public static function now_ms(): int {
		return (int) floor( microtime( true ) * 1000 );
	}

	public static function iso( $ts ): ?string {
		if ( null === $ts || '' === $ts ) {
			return null;
		}
		if ( ! is_numeric( $ts ) ) {
			$ts = strtotime( $ts . ' UTC' );
		}
		return gmdate( 'Y-m-d\TH:i:s\Z', (int) $ts );
	}

	public static function error( string $code, string $message, int $status, array $data = array() ): \WP_Error {
		return new \WP_Error( $code, $message, array_merge( array( 'status' => $status ), $data ) );
	}
}
