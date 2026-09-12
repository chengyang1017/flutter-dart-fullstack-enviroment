@echo off
setlocal
set "REPO_ROOT=%~dp0.."
set "COMPOSE_FILE=%REPO_ROOT%\infra\docker-compose.yml"
set "ENV_FILE=%REPO_ROOT%\.env"

if not exist "%ENV_FILE%" if exist "%REPO_ROOT%\.env.example" copy "%REPO_ROOT%\.env.example" "%ENV_FILE%" >nul

docker compose --env-file "%ENV_FILE%" -f "%COMPOSE_FILE%" up -d
if errorlevel 1 exit /b %errorlevel%

docker compose --env-file "%ENV_FILE%" -f "%COMPOSE_FILE%" ps
endlocal
