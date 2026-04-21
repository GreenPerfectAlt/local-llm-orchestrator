@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "LLAMA_SERVER=%ROOT%llama\llama-server.exe"
set "DOCS_DIR=%ROOT%lib"
set "HISTORY_FILE=%ROOT%history.txt"
set "SYS_PROMPT=%DOCS_DIR%\syspromt.txt"
set "CHAT_PS=%ROOT%chat_client.ps1"
set "PORT=11434"

:: =========================
:: 1. MODEL PICK
:: =========================
cls
echo.
echo [1/4] Loading model history and scanning...
set i=0

if exist "%HISTORY_FILE%" (
    for /f "usebackq delims=" %%L in ("%HISTORY_FILE%") do (
        if exist "%%~L" (
            set /a i+=1
            set "model[!i!]=%%~fL"
            set "is_history[!i!]=1"
        )
    )
)

pushd "%ROOT%" >nul 2>&1
for /f "delims=" %%f in ('dir /b /s *.gguf ^| findstr /v /i "mmproj" 2^>nul') do (
    set "IS_DUPLICATE=0"
    set "CURRENT_FOUND=%%~ff"
    for /L %%k in (1,1,!i!) do (
        if /I "!model[%%k]!"=="!CURRENT_FOUND!" set "IS_DUPLICATE=1"
    )
    if "!IS_DUPLICATE!"=="0" (
        set /a i+=1
        set "model[!i!]=!CURRENT_FOUND!"
        set "is_history[!i!]=0"
    )
)
popd >nul 2>&1

if %i%==0 goto MODEL_MANUAL

echo.
echo Found %i% models:
for /L %%n in (1,1,%i%) do (
    if "!is_history[%%n]!"=="1" (
        if %%n==1 (
            echo   * %%n. !model[%%n]! [LAST]
        ) else (
            echo   * %%n. !model[%%n]! [HISTORY]
        )
    ) else (
        echo   * %%n. !model[%%n]! [NEW]
    )
)
echo   X. Enter path manually
echo.
set /p "MODEL_CHOICE=Choose model (Enter=1): "

if /I "%MODEL_CHOICE%"=="X" goto MODEL_MANUAL
if "%MODEL_CHOICE%"=="" set "MODEL_CHOICE=1"

if not defined model[%MODEL_CHOICE%] (
    echo.
    echo [ERROR] Invalid model selection.
    pause
    exit /b
)

set "SELECTED_MODEL=!model[%MODEL_CHOICE%]!"
goto SAVE_HISTORY

:MODEL_MANUAL
echo.
set /p "SELECTED_MODEL=Enter full path to .gguf: "
set "SELECTED_MODEL=!SELECTED_MODEL:"=!"
if "%SELECTED_MODEL%"=="" goto MODEL_MANUAL
if not exist "%SELECTED_MODEL%" (
    echo.
    echo [ERROR] File not found.
    pause
    goto MODEL_MANUAL
)

:SAVE_HISTORY
> "%HISTORY_FILE%.tmp" echo %SELECTED_MODEL%
if exist "%HISTORY_FILE%" (
    for /f "usebackq delims=" %%L in ("%HISTORY_FILE%") do (
        if /I not "%%~fL"=="%SELECTED_MODEL%" echo %%~fL>>"%HISTORY_FILE%.tmp"
    )
)
move /y "%HISTORY_FILE%.tmp" "%HISTORY_FILE%" >nul

:: =========================
:: 2. MMPROJ PICK
:: =========================
cls
echo.
echo [2/4] Select Vision Adapter (mmproj)...

set "MMPROJ_ARG="
set "SELECTED_MMPROJ="
set v=0

pushd "%ROOT%" >nul 2>&1
for /f "delims=" %%f in ('dir /b /s *mmproj*.gguf 2^>nul') do (
    set /a v+=1
    set "vl_model[!v!]=%%~ff"
)
popd >nul 2>&1

echo.
echo   0. No adapter [DEFAULT]
if !v! GTR 0 (
    for /L %%n in (1,1,!v!) do (
        echo   %%n. !vl_model[%%n]!
    )
)
echo   X. Enter path manually
echo.
set /p "VL_PICK=Choose: "

if "%VL_PICK%"=="" set "VL_PICK=0"

if /I "%VL_PICK%"=="X" (
    set /p "SELECTED_MMPROJ=Enter full path to mmproj.gguf: "
    set "SELECTED_MMPROJ=!SELECTED_MMPROJ:"=!"
    if not "!SELECTED_MMPROJ!"=="" (
        if exist "!SELECTED_MMPROJ!" (
            set "MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!""
        ) else (
            echo.
            echo [ERROR] mmproj file not found.
            pause
            exit /b
        )
    )
    goto PICK_FILE
)

if "%VL_PICK%"=="0" goto PICK_FILE

if defined vl_model[%VL_PICK%] (
    set "SELECTED_MMPROJ=!vl_model[%VL_PICK%]!"
    set "MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!""
)

:: =========================
:: 3. SESSION FILE PICK
:: =========================
:PICK_FILE
cls
echo.
echo [3/4] Select session file

if not exist "%DOCS_DIR%" mkdir "%DOCS_DIR%"

echo.
echo Scanning lib folder...
set "count=0"

pushd "%DOCS_DIR%" >nul 2>&1
for /f "delims=" %%f in ('dir /b *.txt *.md *.log 2^>nul') do (
    if /i "%%f" NEQ "syspromt.txt" (
        set /a count+=1
        set "found_file[!count!]=%%f"
        echo [!count!] %%f
    )
)
popd >nul 2>&1

echo.
echo ------------------------------
echo [1-%count%] Select session file
echo [Enter] System prompt only
echo ------------------------------

set "INPUT_CHOICE="
set /p "INPUT_CHOICE=Your choice: "

set "SESSION_FILE="
set "SN="

if "%INPUT_CHOICE%"=="" goto SERVER_CHECK

if defined found_file[%INPUT_CHOICE%] (
    set "SN=!found_file[%INPUT_CHOICE%]!"
) else (
    set "SN=%INPUT_CHOICE%"
)

set "SESSION_FILE=%DOCS_DIR%\!SN!"
if not exist "!SESSION_FILE!" type nul > "!SESSION_FILE!"

:: =========================
:: 4. SERVER START
:: =========================
:SERVER_CHECK
cls
echo.
echo [4/4] Preparing launch...
echo [DEBUG] Model: %SELECTED_MODEL%
if defined SELECTED_MMPROJ (echo [DEBUG] MMPROJ: %SELECTED_MMPROJ%) else (echo [DEBUG] MMPROJ: NONE)
if defined SESSION_FILE (echo [DEBUG] Session: %SESSION_FILE%) else (echo [DEBUG] Session: DISABLED)
echo.

netstat -ano | findstr /R /C:":%PORT% .*LISTENING" >nul
if %errorlevel%==0 (
    echo [INFO] Server already running.
) else (
    echo [INFO] Server not found. Starting llama-server...
    start "LLAMA_SERVER_CORE" /min "%LLAMA_SERVER%" ^
     -m "%SELECTED_MODEL%" ^
     !MMPROJ_ARG! ^
     --port %PORT% ^
     --jinja ^
     -n -1 -ngl -1 -t 6 -tb 6 --prio 3 ^
     --mmap --cache-ram 2048 ^
     --flash-attn on --fit on --parallel 1

    echo [INFO] Waiting for server...
    timeout /t 8 >nul
)

echo.
echo [INFO] Opening chat...
powershell -NoProfile -ExecutionPolicy Bypass -File "%CHAT_PS%" -Port %PORT% -SystemPromptFile "%SYS_PROMPT%" -SessionFile "%SESSION_FILE%"

echo.
echo [INFO] Chat closed.
pause
exit /b