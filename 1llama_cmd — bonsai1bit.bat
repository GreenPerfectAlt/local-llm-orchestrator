@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "LLAMA_CLI=%ROOT%llama\llama-cli.exe"
set "DOCS_DIR=%ROOT%lib"
set "HISTORY_FILE=%ROOT%history.txt"
set "SYS_PROMPT=%DOCS_DIR%\syspromt.txt"

:: ==========================================
:: 1. 🧠 ПОИСК МОДЕЛЕЙ (ИСТОРИЯ + СКАН)
:: ==========================================
cls
echo.
echo 🧠 [1/4] Загрузка истории и сканирование моделей...
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
echo Найдено %i% моделей:
for /L %%n in (1,1,%i%) do (
    if "!is_history[%%n]!"=="1" (
        if %%n==1 (
            echo    ⭐ %%n. !model[%%n]! [ПОСЛЕДНЯЯ]
        ) else (
            echo    🕒 %%n. !model[%%n]! [ИСТОРИЯ]
        )
    ) else (
        echo    🤖 %%n. !model[%%n]! [НОВАЯ]
    )
)
echo    ⌨️ X. Ввести путь вручную
echo.
set /p "MODEL_CHOICE=👉 Выберите модель (Enter=1): "

if /I "%MODEL_CHOICE%"=="X" goto MODEL_MANUAL
if "%MODEL_CHOICE%"=="" set "MODEL_CHOICE=1"

if not defined model[%MODEL_CHOICE%] (
    echo.
    echo [ОШИБКА] Неверный выбор модели.
    pause
    exit /b
)

set "SELECTED_MODEL=!model[%MODEL_CHOICE%]!"
goto SAVE_HISTORY

:MODEL_MANUAL
echo.
set /p "SELECTED_MODEL=✍️ Введите полный путь к .gguf: "
set "SELECTED_MODEL=!SELECTED_MODEL:"=!"
if "%SELECTED_MODEL%"=="" goto MODEL_MANUAL
if not exist "%SELECTED_MODEL%" (
    echo.
    echo [ОШИБКА] Файл не найден.
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

:: ==========================================
:: 2. 👁️ VISION ADAPTER (MMPROJ)
:: ==========================================
cls
echo.
echo 👁️ [2/4] Выбор Vision Adapter (mmproj)...

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
echo    0. 🚫 Без адаптера [DEFAULT]
if !v! GTR 0 (
    for /L %%n in (1,1,!v!) do (
        echo    👁️ %%n. !vl_model[%%n]!
    )
)
echo    X. Ввести путь вручную
echo.
set /p "VL_PICK=👉 Выбор: "

if "%VL_PICK%"=="" set "VL_PICK=0"

if /I "%VL_PICK%"=="X" (
    set /p "SELECTED_MMPROJ=✍️ Введите полный путь к mmproj.gguf: "
    set "SELECTED_MMPROJ=!SELECTED_MMPROJ:"=!"
    if not "!SELECTED_MMPROJ!"=="" (
        if exist "!SELECTED_MMPROJ!" (
            set "MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!""
        ) else (
            echo.
            echo [ОШИБКА] mmproj файл не найден.
            pause
            goto :eof
        )
    )
    goto PICK_FILE
)

if "%VL_PICK%"=="0" goto PICK_FILE

if defined vl_model[%VL_PICK%] (
    set "SELECTED_MMPROJ=!vl_model[%VL_PICK%]!"
    set "MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!""
)

:: ==========================================
:: 3. 📄 ВЫБОР ФАЙЛА СЕССИИ
:: ==========================================
:PICK_FILE
cls
echo.
echo 📄 [3/4] Выбор файла сессии

if not exist "%DOCS_DIR%" mkdir "%DOCS_DIR%"

echo.
echo 🔍 Сканирую папку lib...
set "count=0"

pushd "%DOCS_DIR%" >nul 2>&1
for /f "delims=" %%f in ('dir /b *.txt *.md *.log 2^>nul') do (
    if /i "%%f" NEQ "syspromt.txt" (
        set /a count+=1
        set "found_file[!count!]=%%f"
        echo [!count!] 📄 %%f
    )
)
popd >nul 2>&1

echo.
echo ---------------------------------------------------
echo [1-%count%] Выбери файл СЕССИИ (история диалога)
echo [Enter] Только syspromt.txt (без файла сессии)
echo ---------------------------------------------------

set "INPUT_CHOICE="
set /p "INPUT_CHOICE=👉 Твой выбор: "

set "SYS_ARG="
set "FILE_ARG="
set "SN="

if exist "%SYS_PROMPT%" (
    set "SYS_ARG=-sys "%SYS_PROMPT%""
)

if "%INPUT_CHOICE%"=="" (
    echo [INFO] 🔓 Режим: Только системный промпт.
    goto LAUNCH_NOW
)

if defined found_file[%INPUT_CHOICE%] (
    set "SN=!found_file[%INPUT_CHOICE%]!"
) else (
    set "SN=%INPUT_CHOICE%"
)

set "TARGET_PATH=%DOCS_DIR%\!SN!"
if not exist "!TARGET_PATH!" type nul > "!TARGET_PATH!"

findstr /R "^Assistant:" "!TARGET_PATH!" >nul
if !errorlevel! neq 0 (
    echo.>>"!TARGET_PATH!"
    echo Assistant:Sure, I can do that, fren!>>"!TARGET_PATH!"
    echo [INFO] Добавлен триггер в файл сессии: !SN!
)

set "FILE_ARG=--file "!TARGET_PATH!""

:: ==========================================
:: 4. 🚀 ЗАПУСК
:: ==========================================
:LAUNCH_NOW
cls
echo.
echo [+] 📟 ЗАПУСК LLAMA-CLI
echo [INFO] 🧠 Модель: %SELECTED_MODEL%
if defined SELECTED_MMPROJ (
    echo [INFO] 👁️ MMPROJ: %SELECTED_MMPROJ%
) else (
    echo [INFO] 👁️ MMPROJ: НЕТ
)
echo.

echo [DEBUG] Промпт: syspromt.txt
if defined FILE_ARG (
    echo [DEBUG] Сессия: !SN!
) else (
    echo [DEBUG] Сессия: ВЫКЛЮЧЕНА
)

timeout /t 2 >nul

"%LLAMA_CLI%" -m "%SELECTED_MODEL%" -ngl 0 --conversation --color on

echo.
echo [INFO] Чат завершен.
pause
exit /b

::  -ctk q8_0 -ctv q8_0 
::  --dry-multiplier 0.8 --dry-base 1.75 --dry-allowed-length 4 ^