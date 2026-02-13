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
set "PREV_CTX_INDEX=2"
set "PREV_MMPROJ="

if exist "settings.ini" (
    for /f "usebackq tokens=1* delims==" %%A in ("settings.ini") do (
        if "%%A"=="MODEL" set "PREV_MODEL=%%B"
        if "%%A"=="LAYERS" set "PREV_LAYERS=%%B"
        if "%%A"=="CTX" set "PREV_CTX_INDEX=%%B"
        if "%%A"=="MMPROJ" set "PREV_MMPROJ=%%B"
    )
)

:: --- ФИКС КАВЫЧЕК ---
if defined PREV_MODEL set "PREV_MODEL=!PREV_MODEL:"=!"
if defined PREV_MMPROJ set "PREV_MMPROJ=!PREV_MMPROJ:"=!"

:: ==========================================
:: ⚙️ НАСТРОЙКИ ПУТЕЙ
:: ==========================================
set "ST_FOLDER=SillyTavern-1.15.0"
set "RISU_FOLDER=RisuAI"
set "RISU_EXE=RisuAI.exe"

set "KOBOLDCPP=%~dp0koboldcpp-nocuda.exe"
set "KIWIX_SERVE=%~dp0kiwix-serve.exe"
set "LLAMA_CLI=%~dp0llama-b7837-bin-win-cpu-x64\llama-cli.exe"

:: ==========================================
:: 🧹 ЧИСТКА ПРОЦЕССОВ
:: ==========================================
taskkill /f /im koboldcpp.exe >nul 2>&1
taskkill /f /im koboldcpp-nocuda.exe >nul 2>&1
taskkill /f /im RisuAI.exe >nul 2>&1
taskkill /f /im llama-cli.exe >nul 2>&1

:: ==========================================
:: 3. 🧠 ПОИСК МОДЕЛЕЙ (ИСТОРИЯ + СКАН)
:: ==========================================
cls
echo.
echo 🧠 [2/4] Загрузка истории и сканирование...
set i=0
set "DEF_MODEL_NUM=1"

:: 1. Сначала читаем ИСТОРИЮ
if exist "history.txt" (
    for /f "usebackq delims=" %%L in ("history.txt") do (
        if exist "%%~L" (
            set /a i+=1
            set "model[!i!]=%%~L"
            set "is_history[!i!]=1"
        )
    )
)

:: 2. Сканируем ТЕКУЩУЮ папку
pushd "%~dp0"
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
popd

if %i%==0 goto MODEL_MANUAL

echo Найдено %i% моделей:
for /L %%n in (1,1,%i%) do (
    if "!is_history[%%n]!"=="1" (
        if %%n==1 (
            echo   ⭐ %%n. !model[%%n]! [ПОСЛЕДНЯЯ]
        ) else (
            echo   🕒 %%n. !model[%%n]! [ИСТОРИЯ]
        )
    ) else (
        echo   🤖 %%n. !model[%%n]! [НОВАЯ]
    )
)

echo   ⌨️ X. Ввести путь вручную
echo.
set /p MODEL_CHOICE="👉 Выберите модель (Enter=1): "

if /I "%MODEL_CHOICE%"=="X" goto MODEL_MANUAL
if "%MODEL_CHOICE%"=="" set MODEL_CHOICE=1
if not defined model[%MODEL_CHOICE%] set MODEL_CHOICE=1

set "SELECTED_MODEL=!model[%MODEL_CHOICE%]!"
goto MODEL_DONE

:MODEL_MANUAL
echo.
set /p SELECTED_MODEL="✍️ Введите полный путь к .gguf: "
set "SELECTED_MODEL=!SELECTED_MODEL:"=!"
if "%SELECTED_MODEL%"=="" goto MODEL_MANUAL

:MODEL_DONE

:: ==========================================
:: 3.1 👁️ VISION ADAPTER (БЫСТРЫЙ ВЫБОР)
:: ==========================================
set "SELECTED_MMPROJ="
set "MMPROJ_ARG="

echo.
echo 👁️ [2/3] VISION ADAPTER (MMPROJ)

set v=0
:: 1. Читаем историю VL
if exist "vl_history.txt" (
    for /f "usebackq delims=" %%L in ("vl_history.txt") do (
        if exist "%%~L" (
            set /a v+=1
            set "vl_model[!v!]=%%~L"
            set "is_vl_hist[!v!]=1"
        )
    )
)

:: 2. Сканируем папку (ищем новые)
pushd "%~dp0"
for /f "delims=" %%f in ('dir /b /s *mmproj*.gguf 2^>nul') do (
    set "IS_DUP=0"
    set "CUR_VL=%%~ff"
    for /L %%k in (1,1,!v!) do if /I "!vl_model[%%k]!"=="!CUR_VL!" set "IS_DUP=1"
    
    if "!IS_DUP!"=="0" (
        set /a v+=1
        set "vl_model[!v!]=!CUR_VL!"
        set "is_vl_hist[!v!]=0"
    )
)
popd

:: 3. Вывод списка
echo    0. 🚫 Без адаптера (Только текст) [DEFAULT]

if !v! GTR 0 (
    for /L %%n in (1,1,!v!) do (
        if "!is_vl_hist[%%n]!"=="1" (
            echo    🕒 %%n. !vl_model[%%n]!
        ) else (
            echo    👁️ %%n. !vl_model[%%n]!
        )
    )
)

echo.
set "VL_PICK=0"
set /p VL_PICK="👉 Выбор (Enter=0): "

:: Логика обработки (0 = Выход)
if "%VL_PICK%"=="0" (
    echo [INFO] Vision отключен.
    goto VL_DONE
)

:: Проверяем, ввел ли юзер число из списка
set "VALID_SELECTION=0"
for /L %%i in (1,1,!v!) do (
    if "%%i"=="%VL_PICK%" set "VALID_SELECTION=1"
)

if "%VALID_SELECTION%"=="1" (
    :: Хитрый трюк для получения переменной по индексу
    for %%k in (!VL_PICK!) do set "SELECTED_MMPROJ=!vl_model[%%k]!"
    set "MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!""
    echo [OK] Подключен Vision: !SELECTED_MMPROJ!
) else (
    :: Если ввели не цифру, проверяем, может это путь к файлу вручную?
    if exist "%VL_PICK%" (
        set "SELECTED_MMPROJ=%VL_PICK%"
        set "MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!""
        echo [OK] Путь принят: !SELECTED_MMPROJ!
    ) else (
        echo [INFO] Неверный выбор, Vision отключен.
    )
)

:VL_DONE

:: Если ммпрож был выбран в INI, но мы отказались сейчас - сбросим его или оставим? 
:: Логика выше сбрасывает (set "SELECTED_MMPROJ=" в начале), это верно.

:: ==========================================
:: 4. 🛠 ТЕХНИЧЕСКИЕ НАСТРОЙКИ (ВЕРНУЛ ЭТОТ БЛОК)
:: ==========================================
echo.
echo 🔧 Настройка GPU/CPU...
echo [INFO] Текущие слои: !PREV_LAYERS!
set /p G_LAYERS="👉 Слои GPU (Enter = !PREV_LAYERS!): "
if "%G_LAYERS%"=="" set G_LAYERS=!PREV_LAYERS!

echo.
echo 📏 Размер контекста (Память):
echo   1. 2048 
echo   2. 4096 
echo   3. 8192 
echo   4. 16384 
echo [INFO] Текущий выбор: !PREV_CTX_INDEX!

set /p C_CHOICE="👉 Выбор (Enter = !PREV_CTX_INDEX!): "
if "%C_CHOICE%"=="" set C_CHOICE=!PREV_CTX_INDEX!

:: Логика конвертации выбора в размер
set C_SIZE=4096
if "!C_CHOICE!"=="1" set C_SIZE=2048
if "!C_CHOICE!"=="2" set C_SIZE=4096
if "!C_CHOICE!"=="3" set C_SIZE=8192
if "!C_CHOICE!"=="4" set C_SIZE=16000

:: ==========================================
:: 5. 💾 ОБНОВЛЕНИЕ ИСТОРИИ И НАСТРОЕК
:: ==========================================
:: 1. Обновляем history.txt
(
    echo !SELECTED_MODEL!
    if exist "history.txt" (
        for /f "usebackq delims=" %%L in ("history.txt") do (
            if /I NOT "%%~L"=="!SELECTED_MODEL!" (
                if exist "%%~L" echo %%L
            )
        )
    )
) > "history_tmp.txt"
move /y "history_tmp.txt" "history.txt" >nul

:: 2. Сохраняем настройки
(
    echo MODEL="!SELECTED_MODEL!"
    echo LAYERS=!G_LAYERS!
    echo CTX=!C_CHOICE!
    if defined SELECTED_MMPROJ echo MMPROJ="!SELECTED_MMPROJ!"
) > "settings.ini"

:: --- СОХРАНЕНИЕ VL ИСТОРИИ ---
if defined SELECTED_MMPROJ (
    (
        echo !SELECTED_MMPROJ!
        if exist "vl_history.txt" (
            for /f "usebackq delims=" %%L in ("vl_history.txt") do (
                if /I NOT "%%~L"=="!SELECTED_MMPROJ!" (
                    if exist "%%~L" echo %%L
                )
            )
        )
    ) > "vl_history_tmp.txt"
    move /y "vl_history_tmp.txt" "vl_history.txt" >nul
)

:: ==========================================
:: 6. 🖥️ ВЫБОР ИНТЕРФЕЙСА
:: ==========================================
cls
echo.
echo 🖥️ [3/4] ВЫБОР ИНТЕРФЕЙСА
echo ------------------------------------------
echo   0. 🌐 KoboldCPP Only (Браузер) [DEFAULT]
echo   1. 🍻 SillyTavern (Красивый чат)
echo   2. 🍒 Cherry Studio (RAG/База знаний)
echo   3. 📟 Native Console (llama-cli.exe)
echo.
set "UI_CHOICE=0"
set /p UI_CHOICE="👉 Ваш выбор (Enter=0): "
if "%UI_CHOICE%"=="" set UI_CHOICE=0

:: ==========================================
:: 7. 🚀 ЗАПУСК СИСТЕМ
:: ==========================================
cls
echo 🚀 [ЗАПУСК СИСТЕМ]

if "%UI_CHOICE%"=="3" goto LAUNCH_NATIVE

echo [+] 🧠 Запускаем KoboldCPP (Backend)...
start "KOBOLD" /high "%KOBOLDCPP%" ^
 --model "%SELECTED_MODEL%" ^
 %MMPROJ_ARG% ^
 --threads 5 ^
 --blasthreads 5 ^
 --gpulayers %G_LAYERS% ^
 --contextsize %C_SIZE% ^
 --usevulkan 0 ^
 --blasbatch 512 ^
 --foreground ^
 --flashattention ^
 --highpriority ^
 --skiplauncher

echo [WAIT] ⏳ Ждем 5 секунд прогрузки нейросети...
timeout /t 5 >nul

if "%UI_CHOICE%"=="0" goto LAUNCH_LITE
if "%UI_CHOICE%"=="1" goto LAUNCH_ST
if "%UI_CHOICE%"=="2" goto LAUNCH_CHERRY
goto LAUNCH_LITE

:LAUNCH_ST
echo [+] 🍻 Запускаем SillyTavern...
pushd "%~dp0%ST_FOLDER%"
set PATH=%CD%\node;%PATH%
set NODE_TLS_REJECT_UNAUTHORIZED=0
start "SillyTavern" node server.js
popd
goto END

:LAUNCH_CHERRY
echo [+] 🍒 Запускаем Cherry Studio...
start "CherryStudio" "%~dp0Cherry-Studio-1.7.15-x64-portable.exe"
goto END

:LAUNCH_LITE
echo [+] 🌐 Открываем Kobold Lite...
start http://localhost:5001
goto END

:LAUNCH_NATIVE
cls
echo [+] 📟 ЗАПУСК LLAMA-CLI
echo [INFO] 🧠 Модель: %SELECTED_MODEL%
echo.
set "DOCS_DIR=%~dp0lib"
if not exist "%DOCS_DIR%" (
    mkdir "%DOCS_DIR%"
)
echo 🔍 Сканирую папку lib...
set "count=0"
pushd "%DOCS_DIR%" 2>nul
for /f "delims=" %%f in ('dir /b /s *.txt *.md *.py *.json *.log 2^>nul') do (
    set /a count+=1
    set "found_file[!count!]=%%~f"
    echo [!count!] 📄 %%~nxf
)
popd
echo.
echo ---------------------------------------------------
echo [1-%count%] Выбери файл для анализа
echo [Enter] jailbreak.txt
echo ---------------------------------------------------
set "INPUT_CHOICE="
set /p INPUT_CHOICE="👉 Твой выбор: "
if "%INPUT_CHOICE%"=="" goto MODE_JAILBREAK
if defined found_file[%INPUT_CHOICE%] goto MODE_FILE
goto MODE_MANUAL

:MODE_JAILBREAK
echo [INFO] 🔓 jailbreak.txt
set "PROMPT_ARG=-f jailbreak.txt"
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

"%LLAMA_CLI%" ^
 -m "%SELECTED_MODEL%" ^
 %MMPROJ_ARG% ^
 -ngl 0 ^
 -c %C_SIZE% ^
 -b 1024 ^
 -t 6 ^
 --temp 0.6 ^
 --min-p 0.05 ^
 --top-k 40 ^
 --top-p 0.95 ^
 --repeat-penalty 1.2 ^
 --repeat-last-n 64 ^
 --dry-multiplier 0.0 ^
 --jinja ^
 --keep -1 ^
 %PROMPT_ARG%

echo.
echo [INFO] Чат завершен.
pause
goto END

:END
exit