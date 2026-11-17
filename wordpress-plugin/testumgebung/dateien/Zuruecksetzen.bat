@echo off
setlocal
title Vibono-Testumgebung zuruecksetzen
cd /d "%~dp0"

echo.
echo  Vibono-Testumgebung zuruecksetzen
echo  ---------------------------------
echo  Alle Aenderungen (Punkte, Bestellungen, neue Konten, Einstellungen, Aktionen)
echo  werden verworfen. Danach ist alles wie beim ersten Start.
echo.

netstat -ano | findstr /R /C:":8080 .*LISTENING" >nul
if not errorlevel 1 (
	echo  Die Testumgebung laeuft noch. Bitte zuerst das Fenster "Vibono-Testumgebung"
	echo  schliessen und dann Zuruecksetzen.bat erneut starten.
	echo.
	pause
	exit /b 1
)

choice /c JN /m "  Wirklich zuruecksetzen? J = ja, N = nein"
if errorlevel 2 exit /b 0

copy /y "%~dp0system\grundzustand.sqlite" "%~dp0system\wp\wp-content\database\.ht.sqlite" >nul
if errorlevel 1 (
	echo  Das hat nicht geklappt. Laeuft die Testumgebung vielleicht noch?
	pause
	exit /b 1
)
del /q "%~dp0system\wp\wp-content\fehlerprotokoll.log" 2>nul
echo.
echo  Fertig. Jetzt Start.bat starten.
echo.
pause
