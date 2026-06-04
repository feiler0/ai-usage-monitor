@echo off
chcp 65001 >nul
echo ============================================
echo   AI Usage Monitor - Build Script
echo ============================================
echo.

cd /d "%~dp0\.."

echo [1/3] Checking Nim environment...
nim --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Nim is not installed or not in PATH
    echo   Install via: winget install nim.nim
    exit /b 1
)
echo [OK] Nim ready

echo.
echo [2/3] Installing dependencies (winim)...
nimble install winim -y --silent 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [WARN] nimble install may have failed, trying to continue...
)
echo [OK] Dependencies checked

echo.
echo [3/3] Building Release (optimized)...
if not exist dist mkdir dist
echo   Target: dist\ai-usage-monitor.exe

:: Release optimization flags
:: -d:release      Release mode
:: --opt:size      Optimize for size
:: --mm:arc        ARC memory management (minimal GC overhead)
:: --app:gui       Windows GUI (no console window)
:: --stackTrace:off  Remove stack traces (smaller binary)
:: --lineTrace:off   Remove line trace info
:: --assertions:off  Remove assertions
:: --panics:on       Keep panic handlers
:: -d:danger        Maximum optimization level
:: -d:strip         Strip debug symbols
:: --passC:"-flto"  GCC link-time optimization (optional, may increase build time)
:: --passL:"-flto"  GCC LTO linker flag

nim c ^
  -d:release ^
  --opt:size ^
  --mm:arc ^
  --app:gui ^
  --stackTrace:off ^
  --lineTrace:off ^
  --assertions:off ^
  --panics:on ^
  -d:danger ^
  -d:strip ^
  -o:dist\ai-usage-monitor.exe ^
  src/main.nim

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================
    echo   BUILD SUCCESS
    echo ============================================
    for %%A in (dist\ai-usage-monitor.exe) do (
        echo   Output: dist\ai-usage-monitor.exe
        echo   Size:   %%~zA bytes
    )
    echo.
    echo Usage:
    echo   1. Run dist\ai-usage-monitor.exe
    echo   2. Window appears at center of screen
    echo   3. Drag anywhere to move
    echo   4. Right-click tray icon for menu
    echo   5. Runtime config file: config.json (auto-created next to working directory)
    echo   6. Stats file: stats.json (auto-managed)
    echo.
    echo To start on boot:
    echo   Create shortcut in shell:startup folder
) else (
    echo.
    echo [ERROR] Build failed. Check errors above.
    exit /b 1
)
