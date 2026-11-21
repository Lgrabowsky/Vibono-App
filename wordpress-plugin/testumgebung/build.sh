#!/usr/bin/env bash
# Baut das Windows-Paket "Vibono-Testumgebung" (ZIP zum Entpacken und Doppelklicken).
#
# Inhalt: PHP für Windows, WordPress, SQLite statt MySQL, WooCommerce, das Plugin vibono-app-api
# mit Demodaten und die Testzentrale. Die Einrichtung (Installation, Demodaten) läuft hier beim
# Bauen mit dem PHP dieses Rechners; ausgeliefert wird eine fertig eingerichtete Datenbank.
#
# Aufruf:  ./build.sh            → dist/Vibono-Test.zip
# Benötigt: php (≥ 8.1, mit pdo_sqlite), composer, git, curl, unzip, zip
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$HERE/../vibono-app-api"
CACHE="${CACHE:-$HERE/.cache}"
OUT="${OUT:-$HERE/dist}"
NAME="Vibono-Test" # kurz halten: Windows-Explorer entpackt keine Pfade über 260 Zeichen
PKG="$OUT/$NAME"

WP_VERSION="7.1.4"
WC_VERSION="11.3.0"
SQLITE_VERSION="v3.1.3"
PHP_WIN_VERSION="8.3.37"

fetch() { # url datei
	if [ ! -s "$CACHE/$2" ]; then
		echo "  lade $2"
		curl -fsSL --retry 3 -o "$CACHE/$2.tmp" "$1"
		mv "$CACHE/$2.tmp" "$CACHE/$2"
	fi
}

echo "1/7 Downloads"
mkdir -p "$CACHE"
fetch "https://github.com/shivammathur/php-builder-windows/releases/download/php8.3/php-$PHP_WIN_VERSION-nts-Win32-vs16-x64.zip" "php-$PHP_WIN_VERSION-win.zip"
fetch "https://github.com/woocommerce/woocommerce/releases/download/$WC_VERSION/woocommerce.zip" "woocommerce-$WC_VERSION.zip"
fetch "https://github.com/WordPress/sqlite-database-integration/releases/download/$SQLITE_VERSION/plugin-sqlite-database-integration.zip" "sqlite-$SQLITE_VERSION.zip"
if [ ! -d "$CACHE/wordpress-$WP_VERSION" ]; then
	echo "  lade WordPress $WP_VERSION"
	git clone -q --depth 1 --branch "$WP_VERSION" https://github.com/WordPress/WordPress "$CACHE/wordpress-$WP_VERSION"
	rm -rf "$CACHE/wordpress-$WP_VERSION/.git"
fi

echo "2/7 WordPress zusammenstellen"
rm -rf "$PKG" "$OUT/$NAME.zip"
mkdir -p "$PKG/system"
WP="$PKG/system/wp"
cp -r "$CACHE/wordpress-$WP_VERSION" "$WP"
rm -f "$WP/wp-content/plugins/hello.php" "$WP/wp-config-sample.php" "$WP/readme.html" "$WP/license.txt"
find "$WP/wp-content/themes" -mindepth 1 -maxdepth 1 -type d ! -name twentytwentyfive -exec rm -rf {} +
unzip -q "$CACHE/woocommerce-$WC_VERSION.zip" -d "$WP/wp-content/plugins/"
unzip -q "$CACHE/sqlite-$SQLITE_VERSION.zip" -d "$WP/wp-content/plugins/"
mv "$WP/wp-content/plugins/plugin-sqlite-database-integration" "$WP/wp-content/plugins/sqlite-database-integration"
# Der Platzhalter für den Pfad bleibt stehen: db.php sucht dann selbst unter plugins/sqlite-database-integration.
sed -e "s#{SQLITE_PLUGIN}#sqlite-database-integration/load.php#g" \
	"$WP/wp-content/plugins/sqlite-database-integration/db.copy" > "$WP/wp-content/db.php"
mkdir -p "$WP/wp-content/database" "$WP/wp-content/uploads"

echo "3/7 Plugin vibono-app-api (mit Claude-SDK für den Energiedichte-Rechner)"
mkdir -p "$WP/wp-content/plugins/vibono-app-api"
( cd "$PLUGIN_SRC" && tar --exclude=./vendor --exclude=./tests --exclude=./.phpunit.cache -cf - . ) | tar -xf - -C "$WP/wp-content/plugins/vibono-app-api"
( cd "$WP/wp-content/plugins/vibono-app-api" && composer install --no-dev --no-interaction --quiet --optimize-autoloader )
find "$WP/wp-content/plugins/vibono-app-api/vendor" -name .git -type d -prune -exec rm -rf {} +
# Standard-Webhooks bringt Bibliotheken für viele Sprachen mit (lange Pfade). Gebraucht wird nur PHP.
SW="$WP/wp-content/plugins/vibono-app-api/vendor/standard-webhooks/standard-webhooks"
find "$SW/libraries" -mindepth 1 -maxdepth 1 -type d ! -name php -exec rm -rf {} +
rm -rf "$SW/assets" "$SW/spec"
rm -f "$WP/wp-content/plugins/vibono-app-api/composer.lock"

echo "4/7 Testumgebung (MU-Plugin, Konfiguration)"
mkdir -p "$WP/wp-content/mu-plugins"
cp -r "$HERE/mu-plugin/." "$WP/wp-content/mu-plugins/"
salts=""
for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
	salts+="define( '$k', '$(head -c 48 /dev/urandom | base64 | tr -d '\n/+=' )' );"$'\n'
done
php -r '$c = file_get_contents($argv[1]); $c = str_replace("__SALTS__", rtrim($argv[2]), $c); $c = str_replace("__JWT__", $argv[3], $c); file_put_contents($argv[4], $c);' \
	"$HERE/dateien/wp-config.php" "$salts" "$(head -c 48 /dev/urandom | base64 | tr -d '\n/+=')" "$WP/wp-config.php"
cp "$HERE/dateien/router.php" "$PKG/system/router.php"

echo "5/7 Einrichten (Installation, Plugins aktivieren, Demodaten)"
php "$HERE/einrichten.php" install "$WP"
php "$HERE/einrichten.php" aktivieren "$WP"
php "$HERE/einrichten.php" demodaten "$WP"
cp "$WP/wp-content/database/.ht.sqlite" "$PKG/system/grundzustand.sqlite"
rm -f "$WP/wp-content/fehlerprotokoll.log"

echo "6/7 PHP für Windows und Startdateien"
unzip -q "$CACHE/php-$PHP_WIN_VERSION-win.zip" -d "$PKG/system/php"
rm -rf "$PKG/system/php/"{phpdbg.exe,php8phpdbg.dll,php8embed.lib,deplister.exe,php-cgi.exe}
cp "$HERE/dateien/php.ini" "$PKG/system/php.ini"
for f in Start.bat Zuruecksetzen.bat; do
	# Windows-Zeilenenden, sonst zeigt der Editor bzw. cmd.exe sie falsch an.
	sed 's/\r$//; s/$/\r/' "$HERE/dateien/$f" > "$PKG/$f"
done

# LIESMICH mit UTF-8-Kennung (BOM), damit auch ältere Editoren die Umlaute richtig zeigen.
{ printf '\xEF\xBB\xBF'; sed 's/\r$//; s/$/\r/' "$HERE/dateien/LIESMICH.txt"; } > "$PKG/LIESMICH.txt"
LONGEST=$(cd "$OUT" && find "$NAME" | awk '{ print length($0) }' | sort -n | tail -1)
echo "  längster Pfad im Paket: $LONGEST Zeichen"

echo "7/7 ZIP"
( cd "$OUT" && zip -q -r -9 "$NAME.zip" "$NAME" )
du -h "$OUT/$NAME.zip"
