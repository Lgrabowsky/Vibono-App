<?php
namespace Vibono\AppApi;

defined( 'ABSPATH' ) || exit;

class Plugin {

	const LAST_ERROR = 'vibono_api_last_error';

	public static function boot(): void {
		// Notabschaltung ohne Backend: define( 'VIBONO_API_DISABLE', true ); in wp-config.php.
		if ( defined( 'VIBONO_API_DISABLE' ) && VIBONO_API_DISABLE ) {
			return;
		}
		try {
			self::boot_modules();
		} catch ( \Throwable $e ) {
			self::report( $e, 'Start' );
		}
	}

	private static function boot_modules(): void {
		Install::maybe_upgrade();

		// Immer: stündlicher Cron (bestätigt vorgemerkte Punkte, räumt Lese-Sessions auf).
		Points::init();
		Reading::init();

		if ( Settings::on( 'module_api' ) ) {
			Auth::init();
			WebSession::init();
			Content::init();
			add_action( 'rest_api_init', array( self::class, 'routes' ) );
		}
		if ( Settings::on( 'module_web_reading' ) ) {
			Reading::init_web();
		}
		if ( Settings::on( 'module_referral' ) ) {
			Referral::init();
		}
		Rewards::init();
		if ( class_exists( 'WooCommerce' ) ) {
			WooCommerce::init();
		}
		Privacy::init();
		if ( is_admin() ) {
			Admin::init();
		}
		if ( defined( 'WP_CLI' ) && WP_CLI ) {
			\WP_CLI::add_command( 'vibono', Cli::class );
		}
	}

	/**
	 * Hook mit Fehlerschutz registrieren: Ein Fehler im Plugin darf Seitenaufbau, Warenkorb oder Kasse
	 * nicht abbrechen. Er wird protokolliert, Filter geben den unveränderten Wert zurück.
	 */
	public static function hook( string $hook, callable $callback, int $priority = 10, int $args = 1 ): void {
		add_filter(
			$hook,
			static function ( ...$params ) use ( $callback, $hook ) {
				try {
					return $callback( ...$params );
				} catch ( \Throwable $e ) {
					self::report( $e, $hook );
					return $params[0] ?? null;
				}
			},
			$priority,
			$args
		);
	}

	/** Fehler ins PHP-Log schreiben und den letzten Fehler für die Übersicht im Backend merken. */
	public static function report( \Throwable $e, string $where ): void {
		$msg = sprintf( '%s: %s (%s:%d)', $where, $e->getMessage(), basename( $e->getFile() ), $e->getLine() );
		error_log( 'Vibono App API – abgefangener Fehler in ' . $msg ); // phpcs:ignore
		if ( function_exists( 'set_transient' ) ) {
			set_transient( self::LAST_ERROR, array( 'at' => time(), 'message' => $msg ), WEEK_IN_SECONDS );
		}
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
		( new Rest\RewardsController() )->register();
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
