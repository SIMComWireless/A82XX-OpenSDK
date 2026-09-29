@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM  Customer_Application build script
REM
REM  Builds the code in customer_code\ into flashable firmware using the SIMCOM
REM  OpenSDK. This whole folder can be copied anywhere - the only thing that has
REM  to be correct is SDK_DIR below.
REM
REM  How it works (the "copy into the SDK" scheme):
REM    1. customer_code\ is copied into <SDK_DIR>\AL\APP\customer_code\
REM    2. customer_code\main.c is copied over <SDK_DIR>\AL\APP\main.c
REM       (the SDK's originals are backed up as *.simcom on the first run)
REM    3. the SDK is built with its own build.py
REM    4. the firmware and the flash package are copied back into output\
REM
REM  Commands:
REM    build.bat              build (incremental)          [default]
REM    build.bat rebuild      clean this module, then build
REM    build.bat clean        delete the build output
REM    build.bat menuconfig   configure features, text UI
REM    build.bat guiconfig    configure features, GUI
REM    build.bat restore      put the SDK's original files back
REM    build.bat help         show this text
REM
REM  NOTE: after changing the configuration you must run "build.bat rebuild",
REM        otherwise the change does not take effect.
REM ============================================================================


REM ---- The only path you normally need to change ----------------------------
set "SDK_DIR=E:\OpenSDK\RedCap\2508027B01V01A8272M7B_SDK_260826\simcom_sdk"

REM Leave APP_TARGET empty to detect the module from %SDK_DIR%\kernel\.
REM Set it explicitly to build for a specific module.
set "APP_TARGET="
REM ---------------------------------------------------------------------------

REM This folder, whatever it is called and wherever it sits.
REM %~dp0 always ends with a backslash; drop it.
set "APP_DIR=%~dp0"
set "APP_DIR=%APP_DIR:~0,-1%"
set "SDK_APP_DIR=%SDK_DIR%\AL\APP"
set "OUT_DIR=%APP_DIR%\output"


REM ============================================================================
REM  Command line
REM ============================================================================
set "ACTION=build"
if not "%~1"=="" (
    set "ACTION="
    if /i "%~1"=="build"      set "ACTION=build"
    if /i "%~1"=="app"        set "ACTION=build"
    if /i "%~1"=="rebuild"    set "ACTION=rebuild"
    if /i "%~1"=="clean"      set "ACTION=clean"
    if /i "%~1"=="menuconfig" set "ACTION=menuconfig"
    if /i "%~1"=="guiconfig"  set "ACTION=guiconfig"
    if /i "%~1"=="restore"    set "ACTION=restore"
    if /i "%~1"=="help"       set "ACTION=help"
    if /i "%~1"=="/?"         set "ACTION=help"
    if not defined ACTION (
        echo ERROR: unknown command "%~1"
        goto :USAGE
    )
)
if /i "%ACTION%"=="help" goto :USAGE


REM ============================================================================
REM  Validate the environment
REM ============================================================================
if not exist "%SDK_DIR%\build.py" (
    echo ERROR: no build.py under SDK_DIR:
    echo        %SDK_DIR%
    echo        Fix SDK_DIR at the top of this script.
    exit /b 1
)
if not exist "%SDK_DIR%\kernel\" (
    echo ERROR: no kernel\ directory under SDK_DIR:
    echo        %SDK_DIR%
    echo        This does not look like a SIMCOM release OpenSDK.
    exit /b 1
)

REM Detect the module name from the one directory under kernel\.
set "TARGET=%APP_TARGET%"
if not defined TARGET (
    for /d %%d in ("%SDK_DIR%\kernel\*") do (
        if not defined TARGET set "TARGET=%%~nxd"
    )
)
if not defined TARGET (
    echo ERROR: cannot detect the module name.
    echo        Set APP_TARGET at the top of this script.
    exit /b 1
)

set "APP_OUT=%SDK_DIR%\output\%TARGET%\APP"

echo.
echo  SDK      : %SDK_DIR%
echo  Module   : %TARGET%
echo  App dir  : %APP_DIR%
echo  Command  : %ACTION%
echo.


REM ============================================================================
REM  clean / restore
REM ============================================================================
if /i "%ACTION%"=="clean" goto :CLEAN
if /i "%ACTION%"=="restore" goto :RESTORE


REM ============================================================================
REM  menuconfig / guiconfig
REM  These edit the SDK's own Kconfig tree, which is the one this build uses.
REM ============================================================================
if /i "%ACTION%"=="menuconfig" goto :CONFIG
if /i "%ACTION%"=="guiconfig"  goto :CONFIG


REM ============================================================================
REM  build
REM ============================================================================

REM ---- Check python up front, so the failure is obvious. --------------------
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: python is not on PATH.
    echo        Install Python 3, then: pip install kconfiglib windows-curses
    exit /b 1
)

REM ---- 1. Back up the SDK's files, once, so "restore" can undo everything. --
if not exist "%SDK_APP_DIR%\main.c.simcom" (
    copy /y "%SDK_APP_DIR%\main.c" "%SDK_APP_DIR%\main.c.simcom" >nul
    echo  [1/4] Backed up AL\APP\main.c          -^> main.c.simcom
)
if not exist "%SDK_APP_DIR%\CMakeLists.txt.simcom" (
    copy /y "%SDK_APP_DIR%\CMakeLists.txt" "%SDK_APP_DIR%\CMakeLists.txt.simcom" >nul
    echo  [1/4] Backed up AL\APP\CMakeLists.txt  -^> CMakeLists.txt.simcom
)
echo  [1/4] SDK originals backed up (kept for "build.bat restore").

REM ---- 2. Copy the customer code into the SDK. -----------------------------
REM Wipe first, so files deleted here do not linger in the SDK.
if exist "%SDK_APP_DIR%\customer_code" rmdir /s /q "%SDK_APP_DIR%\customer_code"
xcopy "%APP_DIR%\customer_code" "%SDK_APP_DIR%\customer_code\" /S /E /Y /I >nul
if errorlevel 1 (
    echo ERROR: failed to copy customer_code\ into the SDK.
    exit /b 1
)

copy /y "%APP_DIR%\customer_code\main.c" "%SDK_APP_DIR%\main.c" >nul
echo  [2/4] Copied customer_code\ and main.c into AL\APP\.

REM Register customer_code as a subdirectory of AL\APP, once.
findstr /c:"add_subdirectory(customer_code)" "%SDK_APP_DIR%\CMakeLists.txt" >nul 2>&1
if not errorlevel 1 goto :CMAKE_PATCHED
>>"%SDK_APP_DIR%\CMakeLists.txt" echo.
>>"%SDK_APP_DIR%\CMakeLists.txt" echo # Appended by Customer_Application\build.bat
>>"%SDK_APP_DIR%\CMakeLists.txt" echo if (EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/customer_code/CMakeLists.txt")
>>"%SDK_APP_DIR%\CMakeLists.txt" echo     add_subdirectory(customer_code)
>>"%SDK_APP_DIR%\CMakeLists.txt" echo endif()
echo  [2/4] Registered customer_code in AL\APP\CMakeLists.txt.
:CMAKE_PATCHED

REM ---- 3. Build inside the SDK. --------------------------------------------
REM NOTE: build.py always exits 0, even when ninja fails - it only prints
REM ">>>>> build successed. <<<<<" or ">>>>> build fail. <<<<<". It also
REM rewrites build_<module>.log from scratch on every run, so that marker in
REM that file is the only reliable verdict on the build.
set "BUILD_CMD=python build.py %TARGET%_app"
if /i "%ACTION%"=="rebuild" set "BUILD_CMD=python build.py %TARGET%_app -c"

set "SDK_LOG=%SDK_DIR%\output\%TARGET%\build_%TARGET%.log"

echo  [3/4] Running: %BUILD_CMD%
echo.
pushd "%SDK_DIR%"
%BUILD_CMD%
popd
echo.

set "BUILD_OK="
if not exist "%SDK_LOG%" goto :VERDICT
findstr /c:">>>>> build successed. <<<<<" "%SDK_LOG%" >nul 2>&1
if not errorlevel 1 set "BUILD_OK=1"
:VERDICT

REM ---- 4. Copy the results back into this folder. --------------------------
REM The log is always copied. The firmware is only copied on success, so a
REM failed build never leaves stale binaries looking like fresh output.
if not exist "%OUT_DIR%" md "%OUT_DIR%" >nul

if exist "%SDK_LOG%" copy /y "%SDK_LOG%" "%OUT_DIR%\build_%TARGET%.log" >nul
if exist "%SDK_DIR%\output\%TARGET%\simcom_build.log" copy /y "%SDK_DIR%\output\%TARGET%\simcom_build.log" "%OUT_DIR%\simcom_build.log" >nul

if not defined BUILD_OK goto :SKIP_ARTIFACTS

REM Named explicitly: a "customer_app.*" wildcard would miss the _crc / _lzma
REM variants, which use an underscore rather than a dot.
for %%f in (customer_app.elf
            customer_app.elf.map
            customer_app.elf.map.json
            customer_app.bin
            customer_app_crc.bin
            customer_app_lzma.bin
            customer_app_lzma_crc.bin) do (
    if exist "%APP_OUT%\%%f" copy /y "%APP_OUT%\%%f" "%OUT_DIR%\%%f" >nul
)

REM The flash package is produced automatically by the APP build; there is no
REM separate "package" target in this SDK (build.py's _package branch is
REM commented out, and packaging is a POST_BUILD step in
REM configs\ASR\1903SR\app_extern_build_flow.cmake).
if exist "%SDK_DIR%\output\package\%TARGET%" (
    xcopy "%SDK_DIR%\output\package\%TARGET%" "%OUT_DIR%\package\%TARGET%\" /S /E /Y /I >nul
)
:SKIP_ARTIFACTS
echo  [4/4] Output folder: %OUT_DIR%


REM ============================================================================
REM  Result
REM ============================================================================
if not defined BUILD_OK goto :FAILED

echo.
echo ============================================================
echo  BUILD SUCCEEDED  -  %TARGET%
echo ============================================================
echo  Firmware      : %OUT_DIR%\customer_app.bin
echo  ELF with debug: %OUT_DIR%\customer_app.elf
echo  Flash package : %OUT_DIR%\package\%TARGET%\
echo  Build log     : %OUT_DIR%\build_%TARGET%.log
echo.

if "%~1"=="" pause
endlocal & exit /b 0


:FAILED
echo.
echo ============================================================
echo  BUILD FAILED  -  %TARGET%
echo ============================================================
echo  Log           : %OUT_DIR%\build_%TARGET%.log
echo  The output folder still holds the previous build, if any.
echo.

if "%~1"=="" pause
endlocal & exit /b 1


REM ============================================================================
REM  clean
REM ============================================================================
:CLEAN
if exist "%SDK_DIR%\output\%TARGET%" rmdir /s /q "%SDK_DIR%\output\%TARGET%"
if exist "%SDK_DIR%\output\package\%TARGET%" rmdir /s /q "%SDK_DIR%\output\package\%TARGET%"
if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
md "%OUT_DIR%" >nul 2>&1
echo Cleaned the build output of %TARGET%.
endlocal & exit /b 0


REM ============================================================================
REM  restore  -  put the SDK back exactly as shipped
REM ============================================================================
:RESTORE
if not exist "%SDK_APP_DIR%\main.c.simcom" (
    echo Nothing to restore - the SDK has not been patched by this script.
    endlocal & exit /b 0
)
copy /y "%SDK_APP_DIR%\main.c.simcom" "%SDK_APP_DIR%\main.c" >nul
if exist "%SDK_APP_DIR%\CMakeLists.txt.simcom" (
    copy /y "%SDK_APP_DIR%\CMakeLists.txt.simcom" "%SDK_APP_DIR%\CMakeLists.txt" >nul
) else (
    echo WARNING: CMakeLists.txt.simcom is missing - AL\APP\CMakeLists.txt
    echo          still carries the appended add_subdirectory for customer_code.
)
if exist "%SDK_APP_DIR%\customer_code" rmdir /s /q "%SDK_APP_DIR%\customer_code"
if exist "%SDK_APP_DIR%\main.c.simcom" del /f /q "%SDK_APP_DIR%\main.c.simcom"
if exist "%SDK_APP_DIR%\CMakeLists.txt.simcom" del /f /q "%SDK_APP_DIR%\CMakeLists.txt.simcom"
echo Restored the SDK originals in %SDK_APP_DIR%
endlocal & exit /b 0


REM ============================================================================
REM  menuconfig / guiconfig
REM ============================================================================
:CONFIG
pushd "%SDK_DIR%"
python build.py %ACTION%
set "CFG_RC=%ERRORLEVEL%"
popd
echo.
if "%CFG_RC%"=="0" echo Configuration saved. Now run "build.bat rebuild" for it to take effect.
endlocal & exit /b %CFG_RC%


REM ============================================================================
REM  usage
REM ============================================================================
:USAGE
echo Usage: build.bat [command]
echo.
echo   (no command)   build, incremental             [default]
echo   rebuild        clean this module, then build
echo   clean          delete the build output
echo   menuconfig     configure features, text UI
echo   guiconfig      configure features, GUI
echo   restore        put the SDK's original files back
echo   help           show this text
echo.
echo Before the first build, set SDK_DIR at the top of this script to your
echo SIMCOM OpenSDK directory.
endlocal & exit /b 0
