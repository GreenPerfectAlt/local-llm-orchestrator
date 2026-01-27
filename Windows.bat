@echo off
:: Переключаем кодировку на UTF-8 для поддержки русского языка и эмодзи
chcp 65001 >nul

title 🥝 KIWIPEDIA: FINAL DIRECTOR'S CUT (USB EDITION)
cd /d "%~dp0"
setlocal enabledelayedexpansion

:: ==========================================
:: 1. 📂 ЗАГРУЗКА СОХРАНЕННЫХ НАСТРОЕК
:: ==========================================
set "PREV_MODEL="
set "PREV_LAYERS=20"
set "PREV_CTX_INDEX=3"

if exist "settings.ini" (
    for /f "usebackq tokens=1* delims==" %%A in ("settings.ini") do (
        if "%%A"=="MODEL" set "PREV_MODEL=%%B"
        if "%%A"=="LAYERS" set "PREV_LAYERS=%%B"
        if "%%A"=="CTX" set "PREV_CTX_INDEX=%%B"
    )
)

:: ==========================================
:: ⚙️ НАСТРОЙКИ ПУТЕЙ
:: ==========================================
set "ST_FOLDER=SillyTavern-1.15.0"
set "RISU_FOLDER=RisuAI"
set "RISU_EXE=RisuAI.exe"

:: Программы
set "KOBOLDCPP=%~dp0koboldcpp-nocuda.exe"
set "KIWIX_SERVE=%~dp0kiwix-serve.exe"

:: !!! ПУТЬ К LLAMA (CPU ВЕРСИЯ) !!!
set "LLAMA_CLI=%~dp0llama-b7837-bin-win-cpu-x64\llama-cli.exe"

:: ==========================================
:: 🧹 ЧИСТКА ПРОЦЕССОВ
:: ==========================================
taskkill /f /im koboldcpp.exe >nul 2>&1
taskkill /f /im koboldcpp-nocuda.exe >nul 2>&1
taskkill /f /im kiwix-serve.exe >nul 2>&1
taskkill /f /im RisuAI.exe >nul 2>&1
taskkill /f /im llama-cli.exe >nul 2>&1

:: ==========================================
:: 2. 🔍 ПОИСК ZIM (Википедия)
:: ==========================================
cls
echo 🔍 [1/4] Сканируем диск %~d0 на наличие ZIM архивов...
set USE_KIWIX=0
set i=0

pushd "%~d0\"
for /f "delims=" %%f in ('dir /b /s *.zim 2^>nul') do (
    set /a i+=1
    set "zim[!i!]=%%~ff"
)
popd

if %i%==0 goto ZIM_MANUAL

echo Найдено %i% архивов:
for /L %%n in (1,1,%i%) do echo    📚 %%n. !zim[%%n]!
echo    ⛔ 0. Пропустить Kiwix
echo    ⌨️ X. Ввести путь вручную

echo.
set /p ZIM_CHOICE="👉 Ваш выбор (0-%i%): "
if /I "%ZIM_CHOICE%"=="X" goto ZIM_MANUAL
if "%ZIM_CHOICE%"=="0" goto ZIM_DONE

set "RAW_ZIM=!zim[%ZIM_CHOICE%]!"
set "SELECTED_ZIM=!RAW_ZIM:]=!"
set USE_KIWIX=1
goto ZIM_DONE

:ZIM_MANUAL
echo.
set /p SELECTED_ZIM="✍️ Введите полный путь к .zim: "
if "%SELECTED_ZIM%"=="" goto ZIM_DONE
set USE_KIWIX=1

:ZIM_DONE

:: ==========================================
:: 3. 🧠 ПОИСК МОДЕЛЕЙ (GGUF)
:: ==========================================
cls
echo.
echo 🧠 [2/4] Сканируем диск %~d0 на наличие AI моделей...
set i=0
set "DEF_MODEL_NUM=1"

pushd "%~d0\"
for /f "delims=" %%f in ('dir /b /s *.gguf 2^>nul') do (
    set /a i+=1
    set "model[!i!]=%%~ff"
    if "%%~ff"=="!PREV_MODEL!" set "DEF_MODEL_NUM=!i!"
)
popd

if %i%==0 goto MODEL_MANUAL

echo Найдено %i% моделей:
for /L %%n in (1,1,%i%) do (
    if %%n==!DEF_MODEL_NUM! (echo   ⭐ %%n. !model[%%n]! [DEFAULT]) else (echo   🤖 %%n. !model[%%n]!)
)
echo   ⌨️ X. Ввести путь вручную
echo.
set /p MODEL_CHOICE="👉 Выберите модель (Enter=!DEF_MODEL_NUM!): "
if /I "%MODEL_CHOICE%"=="X" goto MODEL_MANUAL
if "%MODEL_CHOICE%"=="" set MODEL_CHOICE=!DEF_MODEL_NUM!
set "SELECTED_MODEL=!model[%MODEL_CHOICE%]!"
goto MODEL_DONE

:MODEL_MANUAL
set /p SELECTED_MODEL="✍️ Введите полный путь к .gguf: "

:MODEL_DONE

:: ==========================================
:: 4. 🛠 ТЕХНИЧЕСКИЕ НАСТРОЙКИ
:: ==========================================
echo.
echo 🔧 Настройка GPU/CPU...
set /p G_LAYERS="👉 Слои GPU (Enter = !PREV_LAYERS!): "
if "%G_LAYERS%"=="" set G_LAYERS=!PREV_LAYERS!

echo.
echo 📏 Размер контекста (Память):
echo   1. 2048 (Быстро)
echo   2. 4096 (Стандарт)
echo   3. 8192 (Большой)
echo   4. 16384 (Огромный)
set /p C_CHOICE="👉 Выбор (Enter = !PREV_CTX_INDEX!): "
if "%C_CHOICE%"=="" set C_CHOICE=!PREV_CTX_INDEX!

if "%C_CHOICE%"=="1" set C_SIZE=2048
if "%C_CHOICE%"=="2" set C_SIZE=4096
if "%C_CHOICE%"=="3" set C_SIZE=8192
if "%C_CHOICE%"=="4" set C_SIZE=16384
if "%C_SIZE%"=="" set C_SIZE=4096

(
    echo MODEL=!SELECTED_MODEL!
    echo LAYERS=!G_LAYERS!
    echo CTX=!C_CHOICE!
) > "settings.ini"

:: ==========================================
:: 5. 🖥️ ВЫБОР ИНТЕРФЕЙСА
:: ==========================================
cls
echo.
echo 🖥️ [3/4] ВЫБОР ИНТЕРФЕЙСА
echo ------------------------------------------
echo   0. 🌐 KoboldCPP Only (Браузер) [DEFAULT]
echo   1. 🍻 SillyTavern (Красивый чат)
echo   2. 🎭 RisuAI (Для ролеплея)
echo   3. 📟 Native Console (llama-cli.exe)
echo.
set "UI_CHOICE=0"
set /p UI_CHOICE="👉 Ваш выбор (Enter=0): "

if "%UI_CHOICE%"=="" set UI_CHOICE=0

:: ==========================================
:: 6. 🚀 ЗАПУСК СИСТЕМ
:: ==========================================
cls
echo 🚀 [ЗАПУСК СИСТЕМ]

if "%USE_KIWIX%"=="1" (
    echo [+] 📚 Запускаем Kiwix Server...
    start "KIWIX" "%KIWIX_SERVE%" --port=8080 "%SELECTED_ZIM%"
)

:: Если выбрана консоль (3), сразу запускаем Llama
if "%UI_CHOICE%"=="3" goto LAUNCH_NATIVE

:: Иначе запускаем KoboldCPP
echo [+] 🧠 Запускаем KoboldCPP (Backend)...
start "KOBOLD" /high "%KOBOLDCPP%" ^
 --model "%SELECTED_MODEL%" ^
 --threads 6 ^
 --gpulayers %G_LAYERS% ^
 --contextsize %C_SIZE% ^
 --quantkv 1 ^
 --smartcontext ^
 --usevulkan 0 ^
 --nommap ^
 --skiplauncher

echo [WAIT] ⏳ Ждем 5 секунд прогрузки нейросети...
timeout /t 5 >nul

if "%UI_CHOICE%"=="0" goto LAUNCH_LITE
if "%UI_CHOICE%"=="1" goto LAUNCH_ST
if "%UI_CHOICE%"=="2" goto LAUNCH_RISU
goto LAUNCH_LITE

:LAUNCH_ST
echo [+] 🍻 Запускаем SillyTavern...
pushd "%~dp0%ST_FOLDER%"
set PATH=%CD%\node;%PATH%
start "SillyTavern" node server.js
popd
goto END

:LAUNCH_RISU
echo [+] 🎭 Запускаем RisuAI...
pushd "%~dp0%RISU_FOLDER%"
start "RisuAI" "%RISU_EXE%"
popd
goto END

:LAUNCH_LITE
echo [+] 🌐 Открываем Kobold Lite...
start http://localhost:5001
goto END

:LAUNCH_NATIVE
cls
echo [+] 📟 ЗАПУСК LLAMA-CLI (Ultimate Edition: DRY + Dynatemp)
echo [INFO] 🧠 Модель: %SELECTED_MODEL%
echo.

:: --- 📂 НАСТРОЙКА ПАПКИ ДОКУМЕНТОВ ---
set "DOCS_DIR=%~dp0lib"
if not exist "%DOCS_DIR%" (
    mkdir "%DOCS_DIR%"
    echo [INFO] Создана папка "lib".
)

:: --- 🔍 СКАНЕР ---
echo 🔍 Сканирую папку lib...
set "count=0"
pushd "%DOCS_DIR%" 2>nul
for /f "delims=" %%f in ('dir /b /s *.txt *.md *.py *.json *.log 2^>nul') do (
    set /a count+=1
    set "found_file[!count!]=%%~f"
    echo   [!count!] 📄 %%~nxf
)
popd

echo.
echo ---------------------------------------------------
echo [1-%count%] Выбери файл для анализа
echo [Enter] Просто чат (Ученый наука)
echo ---------------------------------------------------

set "INPUT_CHOICE="
set /p INPUT_CHOICE="👉 Твой выбор: "

:: === ЛОГИКА ===
if "%INPUT_CHOICE%"=="" goto MODE_SCIENTIST
if defined found_file[%INPUT_CHOICE%] goto MODE_FILE
goto MODE_MANUAL

:MODE_SCIENTIST
echo [INFO] 🧪 Включаем режим: Безумный Ученый...
:: Разрешаем <think>, чтобы 14B модель раскрыла потенциал
set "PROMPT_ARG=-p "You are a VERBOSE Mad Scientist. 2. Technical terms in English (Russian). 3. Don't use the LaTex in math formulas. 4. Reply in Russian after.""

goto LAUNCH_NOW

:MODE_FILE
set "TARGET_FILE=!found_file[%INPUT_CHOICE%]!"
set "PROMPT_ARG=--file "!TARGET_FILE!""
echo [INFO] 📖 Читаем файл: !TARGET_FILE!
goto LAUNCH_NOW

:MODE_MANUAL
set "PROMPT_ARG=--file "%INPUT_CHOICE%""
goto LAUNCH_NOW

:LAUNCH_NOW
echo.
echo [DEBUG] Старт через 2 сек...
timeout /t 2 >nul

:: --- ЗАПУСК ---
:: Используем !PROMPT_ARG! для безопасности и -r "### User:" для синхронизации с промптом
"%LLAMA_CLI%" ^
 -m "%SELECTED_MODEL%" ^
 -ngl 0 ^
 -c %C_SIZE% ^
 -b 512 ^
 -t 6 ^
 --color on ^
 -cnv ^
 --log-file "%~d0\history.txt" ^
 --no-mmap ^
 -r "### User:" ^
 --temp 0.7 ^
 --dynatemp-range 0.2 ^
 --min-p 0.05 ^
 --top-k 40 ^
 --top-p 0.95 ^
 --dry-multiplier 0.8 ^
 --dry-base 1.75 ^
 --dry-allowed-length 2 ^
 --dry-penalty-last-n -1 ^
 --repeat-penalty 1.0 ^
 --keep -1 ^
 %PROMPT_ARG%

echo.
echo [INFO] Чат завершен.
pause
goto END

:END
exit