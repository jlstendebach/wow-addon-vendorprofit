@echo off
setlocal

rem Brings the branch you're on up to date with main (and fetches the release
rem tags, so the version stamp is right), then deploys it with deploy.bat.
rem On a branch with work main doesn't have yet, that work is deployed too.
rem Stops without deploying if git fails, such as a merge conflict.

cd /d "%~dp0"

git fetch origin --tags
if errorlevel 1 (
    echo Couldn't fetch from GitHub, so nothing was updated or deployed.
    exit /b 1
)

git merge --no-edit origin/main
if errorlevel 1 (
    echo Merging main stopped, so nothing was deployed.
    echo Fix the conflicts and commit, or undo with: git merge --abort
    exit /b 1
)

call "%~dp0deploy.bat"
exit /b %ERRORLEVEL%
