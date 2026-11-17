@echo off
setlocal
title Vibono-Testumgebung
cd /d "%~dp0"

set "PHP=%~dp0system\php\php.exe"
set "PHPARGS=-c "%~dp0system\php.ini" -d "extension_dir=%~dp0system\php\ext" -d "curl.cainfo=%~dp0system\wp\wp-includes\certificates\ca-bundle.crt" -d "openssl.cafile=%~dp0system\wp\wp-includes\certificates\ca-bundle.crt""
set "DB=%~dp0system\wp\wp-content\database\.ht.sqlite"
set "URL=http://localhost:8080/testzentrale/"

echo.
echo  ==========================================================
echo   Vibono-Testumgebung
echo   WordPress-Plugin "Vibono App API ^& Punkte" zum Ausprobieren
echo   Laeuft nur auf diesem PC. Keine Verbindung zu vibono.de.
echo  ==========================================================
echo.

if not exist "%PHP%" (
	echo  FEHLER: system\php\php.exe fehlt. Bitte das ZIP vollstaendig entpacken
	echo  ^(Rechtsklick auf die ZIP-Datei, "Alle extrahieren"^) und Start.bat
	echo  im entpackten Ordner starten.
	echo.
	pause
	exit /b 1
)

"%PHP%" %PHPARGS% -r "exit(extension_loaded('pdo_sqlite') ? 0 : 3);" >nul 2>&1
set "RC=%errorlevel%"
if "%RC%"=="3" (
	echo  FEHLER: PHP startet, findet aber seine Erweiterungen nicht.
	echo  Liegt der Ordner vielleicht in einem Pfad mit Sonderzeichen?
	echo  Tipp: Ordner nach C:\Vibono-Testumgebung verschieben und erneut starten.
	echo.
	pause
	exit /b 1
)
if not "%RC%"=="0" (
	echo  FEHLER: PHP kann nicht starten. Meist fehlt die kostenlose
	echo  "Microsoft Visual C++ Runtime". Sie wird jetzt im Browser geladen:
	echo  Datei vc_redist.x64.exe ausfuehren, installieren, dann Start.bat erneut starten.
	echo.
	start "" "https://aka.ms/vs/17/release/vc_redist.x64.exe"
	pause
	exit /b 1
)

netstat -ano | findstr /R /C:":8080 .*LISTENING" >nul
if not errorlevel 1 (
	echo  Die Testumgebung laeuft schon ^(oder ein anderes Programm nutzt Port 8080^).
	echo  Der Browser wird geoeffnet: %URL%
	start "" "%URL%"
	echo.
	pause
	exit /b 0
)

if not exist "%DB%" (
	echo  Erster Start: Testdaten werden eingerichtet ...
	copy /y "%~dp0system\grundzustand.sqlite" "%DB%" >nul
)

echo  Die Testumgebung startet. Gleich oeffnet sich der Browser mit der Testzentrale:
echo     %URL%
echo.
echo  Backend:   http://localhost:8080/wp-admin/   Benutzer: admin   Passwort: vibono-test
echo  Testkonten: anna@vibono-test.local, ben@vibono-test.local, clara@vibono-test.local
echo             Passwort jeweils: vibono-test
echo.
echo  Fragt Windows nach dem Netzwerkzugriff: "Zulassen" waehlen, wenn du auch
echo  vom Handy im WLAN zugreifen moechtest. Sonst "Abbrechen", am PC geht es trotzdem.
echo.
echo  DIESES FENSTER OFFEN LASSEN. Zum Beenden einfach schliessen.
echo  ----------------------------------------------------------
echo.

start "" /b powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 3; Start-Process '%URL%'"

"%PHP%" %PHPARGS% -S 0.0.0.0:8080 -t "%~dp0system\wp" "%~dp0system\router.php"

echo.
echo  Die Testumgebung wurde beendet.
pause
