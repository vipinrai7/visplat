@echo off
setlocal enabledelayedexpansion

echo ==================================================
echo   ShotGrid Demo - Data Seeding Tool
echo ==================================================
echo.

REM Check if Docker is running
docker info >nul 2>&1
if errorlevel 1 (
    echo [91mError: Docker is not running.[0m
    echo    Please start Docker Desktop and try again.
    exit /b 1
)

echo [36mChecking if PostgreSQL is running...[0m

REM Check if postgres container exists and is running
docker-compose ps postgres | findstr /C:"Up" >nul 2>&1
if errorlevel 1 (
    echo [33mStarting PostgreSQL container...[0m
    docker-compose up -d postgres
    echo [33mWaiting for PostgreSQL to be ready (this may take 30-60 seconds)...[0m

    REM Wait for postgres to be healthy
    set /a elapsed=0
    set /a timeout=60

    :wait_loop
    if !elapsed! geq !timeout! goto timeout_reached

    docker-compose ps postgres | findstr /C:"healthy" >nul 2>&1
    if not errorlevel 1 (
        echo [92mPostgreSQL is ready![0m
        goto postgres_ready
    )

    timeout /t 2 /nobreak >nul
    set /a elapsed+=2
    echo|set /p="."
    goto wait_loop

    :timeout_reached
    echo.
    echo [93mPostgreSQL health check timed out, but proceeding anyway...[0m
    goto postgres_ready
) else (
    echo [92mPostgreSQL is already running[0m
)

:postgres_ready
echo.
echo [36mRunning seeding tool...[0m
echo.

REM Run the seeding tool
docker-compose run --rm seeding_tool

if errorlevel 1 (
    echo.
    echo [91mSeeding failed! Check the error messages above.[0m
    exit /b 1
)

echo.
echo ==================================================
echo   Seeding Complete!
echo ==================================================
echo.
echo Next steps:
echo   - Access Metabase: http://localhost:3000
echo   - Access Superset: http://localhost:8088
echo.

endlocal
