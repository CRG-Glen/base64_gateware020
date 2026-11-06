@echo off
rem Base64 TG68 build for Windows.
rem   1. Unpack oss-cad-suite (https://github.com/YosysHQ/oss-cad-suite-build/releases,
rem      the windows-x64 .exe) somewhere, e.g. C:\oss-cad-suite
rem   2. Set OSS below to that folder (or set it in your environment)
rem   3. build.bat min        (or fastmem / full, optionally --seeds 5)
if "%OSS%"=="" set OSS=C:\oss-cad-suite
if not exist "%OSS%\environment.bat" (
  echo oss-cad-suite not found at %OSS% - edit build.bat or set OSS=...
  exit /b 1
)
call "%OSS%\environment.bat"
where python3 >nul 2>nul && (python3 "%~dp0scripts\build.py" %* & exit /b %errorlevel%)
python "%~dp0scripts\build.py" %*
