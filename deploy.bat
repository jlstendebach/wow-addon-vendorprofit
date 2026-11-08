@echo off
setlocal

rem Copies the VendorProfit addon into WoW Forever's AddOns folder, replacing
rem whatever version is there, and stamps the version from git into the copy
rem (scripts\stamp-version.ps1).
rem
rem WoW installed somewhere else? Create deploy.local.bat next to this file
rem (git ignores it) with one line pointing at your AddOns folder:
rem     set "ADDONS=D:\Games\World of Warcraft\_forever_\Interface\AddOns"
rem
rem Messages go through labels rather than ( ) blocks: the AddOns path has
rem parentheses in it, which would end a block early.

call :colors
rem update.bat prints its own header and calls this for the rest.
if not defined VP_UPDATING call :header deploy

set "ADDONS="
if exist "%~dp0deploy.local.bat" call "%~dp0deploy.local.bat"
if not defined ADDONS set "ADDONS=C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
set "SOURCE=%~dp0VendorProfit"
set "TARGET=%ADDONS%\VendorProfit"
set "LOG=%TEMP%\vendorprofit-deploy.log"

if not exist "%SOURCE%\VendorProfit.toc" goto :noaddon
if not exist "%ADDONS%\" goto :noaddons

rem /MIR makes the target an exact copy, so files removed from the addon are
rem removed in game too. It only ever touches the VendorProfit folder. The
rem list of copied files goes to a log, read below to sum up what changed.
robocopy "%SOURCE%" "%TARGET%" /MIR /NS /NDL /NP /NJH /NJS /R:2 /W:1 /LOG:"%LOG%" >nul
rem robocopy exit codes: 8 and up mean something failed; 2 means files were
rem removed from the target.
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto :copyfailed

rem The .toc always differs (the copy's is stamped), so it isn't counted.
set "CHANGED=0"
for /f %%n in ('findstr /R "." "%LOG%" ^| findstr /V /I /L /C:"VendorProfit.toc" ^| find /c /v ""') do set "CHANGED=%%n"
rem The game only notices added or removed files on a restart.
set "RESTART="
findstr /I /L /C:"New File" "%LOG%" >nul && set "RESTART=1"
set /a "REMOVED=RC & 2"
if not "%REMOVED%"=="0" set "RESTART=1"

if "%CHANGED%"=="0" (set "COPIED=no file changes") else if "%CHANGED%"=="1" (set "COPIED=1 file updated") else set "COPIED=%CHANGED% files updated"
echo   %GREEN%+%OFF% %DIM%Copy     %OFF% %COPIED%

rem The repository's .toc says @project-version@; the copy gets the real one.
set "VERSION="
for /f "delims=" %%v in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stamp-version.ps1" -Toc "%TARGET%\VendorProfit.toc"') do set "VERSION=%%v"
if not defined VERSION goto :stampfailed
echo   %GREEN%+%OFF% %DIM%Version  %OFF% %GOLD%%BOLD%%VERSION%%OFF%
echo   %GREEN%+%OFF% %DIM%Folder   %OFF% %TARGET%
echo.
if defined RESTART goto :restart
echo   %OKBADGE% DEPLOYED %OFF%  Type %BOLD%/reload%OFF% in game.
echo.
exit /b 0

:restart
echo   %OKBADGE% DEPLOYED %OFF%  %GOLD%%BOLD%Restart WoW%OFF%: files were added or removed, so /reload isn't enough.
echo.
exit /b 0

:noaddon
echo   %FAILBADGE% FAILED %OFF%  Can't find the addon at:
echo             %SOURCE%
echo.
exit /b 1

:noaddons
echo   %FAILBADGE% FAILED %OFF%  Can't find the AddOns folder at:
echo             %ADDONS%
echo.
echo   %DIM%WoW installed somewhere else? Create deploy.local.bat next to deploy.bat%OFF%
echo   %DIM%with one line pointing at your AddOns folder, for example:%OFF%
echo   %DIM%    set "ADDONS=D:\Games\World of Warcraft\_forever_\Interface\AddOns"%OFF%
echo.
exit /b 1

:copyfailed
type "%LOG%"
echo.
echo   %FAILBADGE% FAILED %OFF%  Couldn't copy the addon into WoW.
echo   %DIM%If it says access is denied, close WoW or run this as administrator.%OFF%
echo.
exit /b 1

:stampfailed
echo.
echo   %FAILBADGE% FAILED %OFF%  Copied, but couldn't stamp the version into:
echo             %TARGET%\VendorProfit.toc
echo.
exit /b 1

rem cmd understands ANSI color codes on Windows 10 and later.
:colors
for /f %%e in ('echo prompt $E^| cmd') do set "ESC=%%e"
set "OFF=%ESC%[0m"
set "BOLD=%ESC%[1m"
set "DIM=%ESC%[90m"
set "GOLD=%ESC%[93m"
set "GREEN=%ESC%[92m"
set "OKBADGE=%ESC%[1;30;102m"
set "FAILBADGE=%ESC%[1;97;101m"
exit /b

:header
echo.
echo   %GOLD%%BOLD%[$] VENDOR PROFIT%OFF%  %DIM%// %~1%OFF%
echo   %DIM%==============================================%OFF%
echo.
exit /b
