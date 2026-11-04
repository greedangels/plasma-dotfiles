#!/usr/bin/env bash
# ==============================================================================
# backup.sh: Синхронизация настроек KDE Plasma из ~/.config в ~/dotfiles/kde/config
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_CONFIG="$SCRIPT_DIR/config"
SYSTEM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

# Отслеживаемые ключевые конфигурации KDE Plasma
TRACKED_FILES=(
    "kdeglobals"                              # Цветовая схема, шрифты, стили виджетов
    "plasmarc"                                # Глобальные настройки Plasma
    "kwinrc"                                  # Оконный менеджер KWin, эффекты
    "breezerc"                                # Оформление Breeze
    "kglobalshortcutsrc"                      # Глобальные горячие клавиши
    "plasma-org.kde.plasma.desktop-appletsrc" # Панели, виджеты и апплеты рабочего стола
    "kwinrulesrc"                             # Специфичные правила окон KWin
    "dolphinrc"                               # Настройки файлового менеджера Dolphin
    "konsolerc"                               # Настройки терминала Konsole
)

DRY_RUN=0
SHOW_HELP=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            SHOW_HELP=1
            ;;
        *)
            echo "Неизвестный параметр: $arg"
            echo "Использование: $0 [--dry-run]"
            exit 1
            ;;
    esac
done

if [ "$SHOW_HELP" -eq 1 ]; then
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "Опции:"
    echo "  --dry-run   Показать diff и планируемые изменения без модификации файлов"
    echo "  -h, --help  Показать эту справку"
    exit 0
fi

mkdir -p "$DOTFILES_CONFIG"

echo "================================================================="
echo "  KDE Plasma Dotfiles Backup"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Режим: DRY-RUN (без записи изменений)"
fi
echo "================================================================="
echo "Источник:      $SYSTEM_CONFIG"
echo "Репозиторий:   $DOTFILES_CONFIG"
echo "-----------------------------------------------------------------"

UPDATED_COUNT=0
UNCHANGED_COUNT=0
MISSING_COUNT=0

for file in "${TRACKED_FILES[@]}"; do
    src="$SYSTEM_CONFIG/$file"
    dst="$DOTFILES_CONFIG/$file"

    if [ ! -f "$src" ]; then
        echo "[-] Пропущен (не найден в системе): $file"
        MISSING_COUNT=$((MISSING_COUNT + 1))
        continue
    fi

    # Проверка существования в репозитории
    if [ ! -f "$dst" ]; then
        echo "[+] Новый файл: $file"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [DRY-RUN] Будет скопирован: $src -> $dst"
        else
            cp -p "$src" "$dst"
            echo "    Скопирован в репозиторий."
        fi
        UPDATED_COUNT=$((UPDATED_COUNT + 1))
        continue
    fi

    # Проверка различий
    if diff -q "$dst" "$src" >/dev/null 2>&1; then
        echo "[=] Без изменений: $file"
        UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
    else
        echo "[~] Изменен: $file"
        echo "----------------- DIFF ($file) -----------------"
        diff --color=auto -u "$dst" "$src" || true
        echo "------------------------------------------------"

        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [DRY-RUN] Будет обновлен из $src"
        else
            cp -p "$src" "$dst"
            echo "    Файл обновлен."
        fi
        UPDATED_COUNT=$((UPDATED_COUNT + 1))
    fi
done

echo "-----------------------------------------------------------------"
echo "Итоги синхронизации:"
echo "  Обновлено / добавлено: $UPDATED_COUNT"
echo "  Без изменений:         $UNCHANGED_COUNT"
echo "  Не найдено в системе:  $MISSING_COUNT"

# Запуск сканирования безопасности
echo ""
if [ -f "$SCRIPT_DIR/scripts/verify-security.sh" ]; then
    bash "$SCRIPT_DIR/scripts/verify-security.sh" "$DOTFILES_CONFIG"
fi

echo "================================================================="
if [ "$DRY_RUN" -eq 0 ] && [ "$UPDATED_COUNT" -gt 0 ]; then
    echo "Запустите 'git status' или 'git diff' в каталоге репозитория для проверки."
fi
