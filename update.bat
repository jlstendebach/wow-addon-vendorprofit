@echo off
setlocal

rem Brings the branch you're on up to date with main (and fetches the release
rem tags, so the version stamp is right), then deploys it with deploy.bat.
rem On a branch with work main doesn't have yet, that work is deployed too.
rem Stops without deploying if git fails, such as a merge conflict.

cd /d "%~dp0"
call :colors
call :header update
set "VP_UPDATING=1"

git fetch --quiet origin --tags
if errorlevel 1 goto :fetchfailed
echo   %GREEN%+%OFF% %DIM%Fetch    %OFF% main and release tags

set "BRANCH="
for /f "delims=" %%b in ('git branch --show-current') do set "BRANCH=%%b"
if not defined BRANCH set "BRANCH=HEAD"
set "BEHIND=0"
for /f %%n in ('git rev-list --count HEAD..origin/main') do set "BEHIND=%%n"
if "%BEHIND%"=="0" goto :uptodate

git merge --quiet --no-edit origin/main
if errorlevel 1 goto :mergefailed
if "%BEHIND%"=="1" (set "WHAT=1 commit") else set "WHAT=%BEHIND% commits"
echo   %GREEN%+%OFF% %DIM%Merge    %OFF% %WHAT% from main into %BOLD%%BRANCH%%OFF%
goto :deploy

:uptodate
echo   %GREEN%+%OFF% %DIM%Merge    %OFF% %BOLD%%BRANCH%%OFF% already has everything in main

:deploy
call "%~dp0deploy.bat"
exit /b %ERRORLEVEL%

:fetchfailed
echo.
echo   %FAILBADGE% FAILED %OFF%  Couldn't fetch from GitHub. Nothing was updated or deployed.
echo.
exit /b 1

:mergefailed
echo.
echo   %FAILBADGE% FAILED %OFF%  Merging main into %BRANCH% stopped. Nothing was deployed.
echo   %DIM%Git says why above. For a conflict: fix it and commit, or undo with git merge --abort%OFF%
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
