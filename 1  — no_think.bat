@echo off
:: Переключаем кодировку на UTF-8 для поддержки русского языка и эмодзи
chcp 65001 >nul

title 🥝 LOCAL AI WINDOWS NOCUDA - 2026 EDITION
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
set "ST_FOLDER=SillyTavern"
set "RISU_FOLDER=RisuAI"
set "RISU_EXE=RisuAI.exe"
set "KOBOLDCPP=%~dp0koboldcpp-nocuda.exe"
set "LLAMA_CLI=%~dp0llama\llama-cli.exe"
set "LLAMA_SERVER=%~dp0llama\llama-server.exe"


:: ==========================================
:: 3. 🧠 ПОИСК МОДЕЛЕЙ (ИСТОРИЯ + СКАН)
:: ==========================================
cls
echo.
echo 🧠 [1/4] Загрузка истории и сканирование моделей...
set i=0
set "DEF_MODEL_NUM=1"

if exist "history.txt" (
    for /f "usebackq delims=" %%L in ("history.txt") do (
        if exist "%%~L" (
            set /a i+=1
            set "model[!i!]=%%~L"
            set "is_history[!i!]=1"
        )
    )
)

pushd "%~dp0"
for /f "delims=" %%f in ('dir /b /s *.gguf ^| findstr /v /i "mmproj" 2^>nul') do (
    set "IS_DUPLICATE=0"
    set "CURRENT_FOUND=%%~ff"
    for /L %%k in (1,1,!i!) do if /I "!model[%%k]!"=="!CURRENT_FOUND!" set "IS_DUPLICATE=1"
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
        if %%n==1 (echo    ⭐ %%n. !model[%%n]! [ПОСЛЕДНЯЯ]) else (echo    🕒 %%n. !model[%%n]! [ИСТОРИЯ])
    ) else (echo    🤖 %%n. !model[%%n]! [НОВАЯ])
)
echo    ⌨️ X. Ввести путь вручную
echo.
set /p "MODEL_CHOICE="👉 Выберите модель (Enter=1): ""

if /I "%MODEL_CHOICE%"=="X" goto MODEL_MANUAL
if "%MODEL_CHOICE%"=="" set MODEL_CHOICE=1
call set "SELECTED_MODEL=%%model[%MODEL_CHOICE%]%%"
goto MODEL_DONE

:MODEL_MANUAL
echo.
set /p "SELECTED_MODEL="✍️ Введите полный путь к .gguf: ""
set "SELECTED_MODEL=!SELECTED_MODEL:"=!"
if "%SELECTED_MODEL%"=="" goto MODEL_MANUAL

:MODEL_DONE

:: ==========================================
:: 3.1 👁️ VISION ADAPTER
:: ==========================================
set "SELECTED_MMPROJ="
set "MMPROJ_ARG="
echo.
echo 👁️ [2/4] VISION ADAPTER (MMPROJ)
set v=0
if exist "vl_history.txt" (
    for /f "usebackq delims=" %%L in ("vl_history.txt") do (
        if exist "%%~L" (
            set /a v+=1
            set "vl_model[!v!]=%%~L"
        )
    )
)
pushd "%~dp0"
for /f "delims=" %%f in ('dir /b /s *mmproj*.gguf 2^>nul') do (
    set "IS_DUP=0"
    set "CUR_VL=%%~ff"
    for /L %%k in (1,1,!v!) do if /I "!vl_model[%%k]!"=="!CUR_VL!" set "IS_DUP=1"
    if "!IS_DUP!"=="0" (set /a v+=1 & set "vl_model[!v!]=!CUR_VL!")
)
popd

echo    0. 🚫 Без адаптера (Только текст) [DEFAULT]
if !v! GTR 0 (
    for /L %%n in (1,1,!v!) do echo    👁️ %%n. !vl_model[%%n]!
)
echo.
set "VL_PICK=0"
set /p VL_PICK="👉 Выбор (Enter=0): "
if "%VL_PICK%"=="0" goto VL_DONE
if defined vl_model[%VL_PICK%] (
    for %%k in (!VL_PICK!) do set "SELECTED_MMPROJ=!vl_model[%%k]!"
    set MMPROJ_ARG=--mmproj "!SELECTED_MMPROJ!"
)
:VL_DONE

:: ==========================================
:: 4. 🛠 ТЕХНИЧЕСКИЕ НАСТРОЙКИ
:: ==========================================
echo.
echo 🔧 [3/4] Настройка ресурсов...

:: Обнуляем и считываем слои
set "G_INPUT="
set /p "G_INPUT=👉 Слои GPU (Enter = !PREV_LAYERS!): "
if not defined G_INPUT (set "G_LAYERS=!PREV_LAYERS!") else (set "G_LAYERS=!G_INPUT!")
:: ФИКС: Удаляем все пробелы, если они пролезли
set "G_LAYERS=!G_LAYERS: =!"

echo.
echo 📏 Контекст: [1] 2048 [2] 4096 [3] 8192 [4] 16k
set "C_INPUT="
set /p "C_INPUT=👉 Выбор (Enter = !PREV_CTX_INDEX!): "
if not defined C_INPUT (set "C_CHOICE=!PREV_CTX_INDEX!") else (set "C_CHOICE=!C_INPUT!")
:: ФИКС: Удаляем все пробелы
set "C_CHOICE=!C_CHOICE: =!"

:: Логика выбора размера
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
echo 🖥️ [4/4] ВЫБОР ИНТЕРФЕЙСА
echo ------------------------------------------
echo    0. 🌐 KoboldCPP Only (Только бэкенд) [DEFAULT]
echo    1. 🍻 SillyTavern + KoboldCPP (Твой стабильный топ)
echo    2. 🏎️ SillyTavern + Llama-server (Максимальная скорость)
echo    3. 🍒 Cherry Studio (RAG / Диплом)
echo    4. 📟 Native Console (llama-cli)
echo    5. 🌊 Open WebUI (Docker/Venv)
echo ------------------------------------------
set "UI_CHOICE=0"
set /p UI_CHOICE="👉 Ваш выбор: "
if "%UI_CHOICE%"=="" set UI_CHOICE=0

:: ==========================================
:: 7. 🚀 ЗАПУСК СИСТЕМ (Дополненная версия)
:: ==========================================
cls
echo 🚀 [ЗАПУСК СИСТЕМ]
echo MODEL=[%SELECTED_MODEL%]
pause

:: Маршрутизация: сразу отсекаем варианты, где KoboldCPP не нужен
if "%UI_CHOICE%"=="2" goto LAUNCH_ST_LLAMA
if "%UI_CHOICE%"=="3" goto LAUNCH_CHERRY
if "%UI_CHOICE%"=="4" goto LAUNCH_NATIVE
if "%UI_CHOICE%"=="5" goto LAUNCH_OPENWEBUI

:: --- БЛОК ЗАПУСКА KOBOLDCPP (Для пунктов 0 и 1) ---
echo [+] 🧠 Запускаем KoboldCPP (Backend)...

:: ФИКС: Все флаги выстроены в одну строку. Исключен риск обрыва команды из-за пустой переменной адаптера.
:: Переменные слоев (!G_LAYERS!) и контекста (!C_SIZE!) теперь подтягиваются из твоего выбора в 4-м пункте.
start "" /high "%KOBOLDCPP%" --model "%SELECTED_MODEL%" !MMPROJ_ARG! --contextsize 8024 --smartcontext --threads 6 --threads-batch 6 --gpulayers -1 --highpriority --foreground --skiplauncher --usevulkan 0 --flashattention --usemmap --chat-template-kwargs "{\"enable_thinking\":true}" --websearch --smartcache 1 --jinja --blasbatchsize 2048 --batchsize 1024

:: Если тебе нужно БОЛЬШЕ 8к (реальная бесконечность): Удали --useswa и оставь --smartcontext, при этом обязательно укажи --contextsize 32768 (или больше). Только в этом режиме smartcontext раскроет свой потенциал, позволяя модели помнить огромные куски текста и не тормозить при их сдвиге.И не забудь про --useswa (Sliding Window Attention). В твоем тексте сказано, что без него KV-кэш у Gemma 4 раздувается до неадекватных размеров.
:: --smartcache 1. На слабой карте он только создает лишние очереди данных.
:: --smartcontext. Без него Kobold перестанет тратить время на "сверку" и начнет просто генерировать текст.
:: --quantkv 3. Система сама выберет оптимальный формат. Если станет тупее, но быстрее — значит, дело было именно в этом.


echo [WAIT] ⏳ Ждем 5 секунд прогрузки нейросети...
timeout /t 5 >nul

if "%UI_CHOICE%"=="1" goto LAUNCH_ST
goto END

:: --- БЛОК ЗАПУСКА LLAMA-SERVER (Для пункта 2) ---
:LAUNCH_ST_LLAMA
echo [+] 🚀 Запускаем Llama-Server (Backend для SillyTavern)...
start "LLAMA_SERVER" /high "%LLAMA_SERVER%" ^
 -m "%SELECTED_MODEL%" ^
 -c 0 -ngl -1 -t 6 -tb 6 --prio 3 ^
 --port 11434 ^
 --mmap ^
 --reasoning off --reasoning-budget 0 ^
 -dio -nkvo --prio 3 --cache-ram 2048 --no-host --flash-attn on --fit on --parallel 1 --keep -1 --poll 100

echo [WAIT] ⏳ Ждем 5 секунд прогрузки Vulkan/Сервера...
timeout /t 5 >nul
goto LAUNCH_ST

:: --- ОБЩИЙ БЛОК ЗАПУСКА SILLYTAVERN ---
:LAUNCH_ST
echo [+] 🍻 Запускаем SillyTavern...
pushd "%~dp0%ST_FOLDER%"
set PATH=%CD%\node;%PATH%
set NODE_TLS_REJECT_UNAUTHORIZED=0
start "SillyTavern" node server.js
popd
goto END

:: --- ОСТАЛЬНЫЕ ИНТЕРФЕЙСЫ ---
:LAUNCH_CHERRY
echo [+] 🍒 Запускаем Cherry Studio...
start "CherryStudio" "%~dp0Cherry-Studio-1.8.4-x64-portable.exe"
goto END

:LAUNCH_OPENWEBUI
echo [+] 🚀 Запускаем Llama-Server для Open WebUI...
start "LLAMA_SERVER" /high "%LLAMA_SERVER%" ^
 -m "%SELECTED_MODEL%" ^
 -c %C_SIZE% ^
 --port 11434 ^
 --mmap ^
 -t 6 -tb 6 --prio 3 ^
 --reasoning off --reasoning-budget 0 ^
 -ctk q8_0 -ctv q8_0 ^
 -dio --no-host --flash-attn on --fit on --parallel 1 --keep -1 --poll 100
 
echo [WAIT] ⏳ Ждем 5 секунд прогрузки Vulkan...
timeout /t 5 >nul

echo [+] 🌐 Запускаем Open WebUI...
pushd "C:\AI\OpenWebUI"
start "OpenWebUI_Backend" cmd /k "venv\Scripts\open-webui.exe serve"
timeout /t 8 >nul
start http://localhost:8080
popd
goto END

@echo off
setlocal enabledelayedexpansion

:LAUNCH_NATIVE
cls
echo [+] 📟 ЗАПУСК LLAMA-CLI (FIXED LOGIC)
echo [INFO] 🧠 Модель: %SELECTED_MODEL%
echo.

set "DOCS_DIR=%~dp0lib"
if not exist "%DOCS_DIR%" mkdir "%DOCS_DIR%"

:: 1. СКАНИРОВАНИЕ ФАЙЛОВ СЕССИЙ
echo 🔍 Сканирую папку lib...
set "count=0"
pushd "%DOCS_DIR%" 2>nul
for /f "delims=" %%f in ('dir /b *.txt *.md *.log 2^>nul') do (
    :: Не выводим основной файл правил в список сессий для удобства
    if /i "%%f" NEQ "syspromt.txt" (
        set /a count+=1
        set "found_file[!count!]=%%f"
        echo [!count!] 📄 %%f
    )
)
popd

echo.
echo ---------------------------------------------------
echo [1-%count%] Выбери файл СЕССИИ (история диалога)
echo [Enter] Только syspromt.txt (без файла сессии)
echo ---------------------------------------------------

set "INPUT_CHOICE="
set /p INPUT_CHOICE="👉 Твой выбор: "

:: 2. ЛОГИКА РАЗДЕЛЕНИЯ
set "SYS_ARG=-sys "lib\syspromt.txt""
set "FILE_ARG="

if "%INPUT_CHOICE%"=="" (
    echo [INFO] 🔓 Режим: Только системный промпт.
) else (
    if defined found_file[%INPUT_CHOICE%] (
        set "SN=!found_file[%INPUT_CHOICE%]!"
    ) else (
        set "SN=%INPUT_CHOICE%"
    )
    
    set "TARGET_PATH=lib\!SN!"
    if not exist "!TARGET_PATH!" type nul > "!TARGET_PATH!"

    :: 3. ПОДСТАНОВКА (Только в файл сессии!)
    findstr /R "^Assistant:" "!TARGET_PATH!" >nul
    if !errorlevel! neq 0 (
        echo.>>"!TARGET_PATH!"
        echo Assistant:Sure, I can do that, fren!>>"!TARGET_PATH!"
        echo [INFO] Добавлен триггер в файл сессии: !SN!
    )
    set "FILE_ARG=--file "!TARGET_PATH!""
)

:LAUNCH_NOW
echo.
echo [DEBUG] Промпт: syspromt.txt
if defined FILE_ARG (echo [DEBUG] Сессия: !SN!) else (echo [DEBUG] Сессия: ВЫКЛЮЧЕНА)
timeout /t 2 >nul

"%LLAMA_CLI%" -m "%SELECTED_MODEL%" !MMPROJ_ARG! -c 128000 -n -1 -ngl -1 -t 6 -tb 6 --mmap --prio 3 -fa on -ctk q4_0 -ctv q4_0 --fit on --parallel 1 --conversation --no-display-prompt --color on --jinja --keep 1 --reasoning off --reasoning-budget 0 --numa distribute --cache-ram 1024 -b 2048 -ub 512 !SYS_ARG! !FILE_ARG!

echo.
echo [INFO] Чат завершен.
pause
goto END

:END
exit

:: какие то настройки новые
:: -dio --no-host 
:: температура --temp 1.0 --dynatemp-exp 1.0 --dynatemp-range 0.4
::  --xtc-threshold 0.1 --xtc-probability 0.2 --dry-multiplier 0.8 --dry-base 1.75 --dry-allowed-length 4 --mirostat 0 --min-p 0.1 ^
::  --flash-attn on ^ Часто реализация Flash Attention в драйверах или движках (llama.cpp и аналоги) не ожидает, что коэффициенты YaRN будут менять структуру матриц на лету. Результат: модель «глючит» и выдает символ конца текста (EOS) раньше времени, потому что числа в расчетах выходят за допустимые пределы.
::  --rope-scaling linear --rope-scale 2 --yarn-attn-factor 1 -dio ^
:: --swa-full: Принудительно отключает механизм «скользящего окна» и заставляет модель обсчитывать всю историю переписки целиком, что дико жрет видеопамять и на Gemma/Qwen часто вызывает бред. [1, 2]
:: --no-kv-offload: Запрещает переносить кэш в видеопамять, из-за чего твой 8-битный кэш упадет на процессор и скорость генерации станет мучительно медленной.
:: --rope-scale 2: Искусственно растягивает обученный контекст модели в два раза, из-за чего она начинает галлюцинировать и путать факты, если не подстроены частоты.
:: --no-host — Самый полезный для тебя. Он заставляет видеокарту работать напрямую, минуя «промежуточный» буфер в оперативной памяти (RAM).
:: --no-kv-offload (-nkvo) — Никогда не ставь, если у тебя есть видеокарта.
Почему: По умолчанию (enabled) кэш считается на быстрой видеокарте. Если ты пропишешь -nkvo, ты насильно выкинешь свой 8-битный кэш на медленный процессор. Результат: модель будет «думать» по 10 секунд над каждым словом. Убирай его.
:: --no-repack (-nr) — Бесполезный мусор для обычного пользователя.
Что делает: Отключает перепаковку весов модели под архитектуру твоей карты при загрузке. Это может сэкономить 1 секунду при запуске, но замедлит саму генерацию. Не трогай его, пусть будет по умолчанию (enabled).
  