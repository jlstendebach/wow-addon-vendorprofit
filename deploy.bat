@echo off
setlocal

rem Copies the VendorProfit addon into WoW Forever's AddOns folder, replacing
rem whatever version is there, and stamps the version from git into the copy
rem (scripts\stamp-version.ps1).
rem
rem WoW installed somewhere else? Create deploy.local.bat next to this file
rem (git ignores it) with one line pointing at your AddOns folder:
rem     set "ADDONS=D:\Games\World of Warcraft\_forever_\Interface\AddOns"

set "ADDONS="
if exist "%~dp0deploy.local.bat" call "%~dp0deploy.local.bat"
if not defined ADDONS set "ADDONS=C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
set "SOURCE=%~dp0VendorProfit"
set "TARGET=%ADDONS%\VendorProfit"
set "EXITCODE=0"

if not exist "%SOURCE%\VendorProfit.toc" (
    echo Can't find the addon at "%SOURCE%".
    set "EXITCODE=1"
    goto :done
)
if not exist "%ADDONS%\" (
    echo Can't find the AddOns folder at "%ADDONS%".
    echo If WoW is installed somewhere else, create deploy.local.bat next to deploy.bat
    echo with one line pointing at your AddOns folder, for example:
    echo     set "ADDONS=D:\Games\World of Warcraft\_forever_\Interface\AddOns"
    set "EXITCODE=1"
    goto :done
)

rem /MIR makes the target an exact copy, so files removed from the addon are
rem removed in game too. It only ever touches the VendorProfit folder.
robocopy "%SOURCE%" "%TARGET%" /MIR /NJH /NJS /NDL /NP /R:2 /W:1
rem robocopy exit codes 0-7 mean success; 8 and up mean something failed.
if errorlevel 8 (
    echo Deploy failed. If it says access is denied, close WoW or run this as administrator.
    set "EXITCODE=1"
    goto :done
)

rem The repository's .toc says @project-version@; the copy gets the real one.
set "VERSION="
for /f "delims=" %%v in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stamp-version.ps1" -Toc "%TARGET%\VendorProfit.toc"') do set "VERSION=%%v"
if not defined VERSION (
    echo Deployed, but couldn't stamp the version into "%TARGET%\VendorProfit.toc".
    set "EXITCODE=1"
    goto :done
)
echo Deployed Vendor Profit for Auctionator %VERSION% to "%TARGET%".
echo In game: /reload picks up changed files. Restart WoW if files were added or removed.

:done
exit /b %EXITCODE%
