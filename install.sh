#!/usr/bin/env bash
# ==============================================================================
# install.sh: Bootstrap-скрипт развертывания окружения KDE Plasma на чистой системе
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"
RESTORE_SCRIPT="$SCRIPT_DIR/restore.sh"

DRY_RUN=0
NON_INTERACTIVE=0
USE_COPY=0
SKIP_PACKAGES=0
SHOW_HELP=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        -y|--yes|--noconfirm)
            NON_INTERACTIVE=1
            ;;
        --copy)
            USE_COPY=1
            ;;
        --no-packages)
            SKIP_PACKAGES=1
            ;;
        -h|--help)
            SHOW_HELP=1
            ;;
        *)
            echo "Неизвестный параметр: $arg"
            echo "Использование: $0 [--dry-run] [-y|--noconfirm] [--copy] [--no-packages]"
            exit 1
            ;;
    esac
done

if [ "$SHOW_HELP" -eq 1 ]; then
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "Bootstrap-скрипт для полного развертывания KDE Plasma dotfiles."
    echo ""
    echo "Опции:"
    echo "  --dry-run        Имитация работы без установки пакетов и изменения файлов"
    echo "  -y, --noconfirm  Не запрашивать подтверждения (автоматическая установка)"
    echo "  --copy           Копировать файлы конфигурации вместо создания симлинков"
    echo "  --no-packages    Пропустить шаг установки системных пакетов"
    echo "  -h, --help       Показать эту справку"
    exit 0
fi

echo "================================================================="
echo "  KDE Plasma Bootstrap & Deployment"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Режим: DRY-RUN (симуляция)"
fi
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Определение пакетного менеджера и установка зависимостей
# ------------------------------------------------------------------------------
if [ "$SKIP_PACKAGES" -eq 1 ]; then
    echo "[-] Шаг проверки пакетов пропущен по запросу (--no-packages)."
else
    echo "==> [Этап 1/3] Проверка пакетного менеджера и зависимостей..."

    PKG_MANAGER=""
    PKG_INSTALL_CMD=""

    if command -v paru >/dev/null 2>&1; then
        PKG_MANAGER="paru"
        PKG_INSTALL_CMD="paru -S --needed"
    elif command -v yay >/dev/null 2>&1; then
        PKG_MANAGER="yay"
        PKG_INSTALL_CMD="yay -S --needed"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        PKG_INSTALL_CMD="sudo pacman -S --needed"
    else
        echo "⚠️ Внимание: Ни pacman, ни AUR-хелперы (paru/yay) не найдены в PATH."
        echo "   Шаг установки системных пакетов будет пропущен."
    fi

    if [ -n "$PKG_MANAGER" ] && [ -f "$PACKAGES_FILE" ]; then
        echo "    Обнаружен пакетный менеджер: $PKG_MANAGER"
        echo "    Чтение списка пакетов из: $PACKAGES_FILE"

        # Читаем пакеты, исключая комментарии и пустые строки
        MISSING_PKGS=()
        while IFS= read -r pkg || [ -n "$pkg" ]; do
            # Убираем пробелы и комментарии
            pkg=$(echo "$pkg" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -z "$pkg" ] && continue

            if ! pacman -Q "$pkg" >/dev/null 2>&1; then
                MISSING_PKGS+=("$pkg")
            fi
        done < "$PACKAGES_FILE"

        if [ "${#MISSING_PKGS[@]}" -eq 0 ]; then
            echo "✅ Все необходимые пакеты уже установлены."
        else
            echo "📦 Найдено ${#MISSING_PKGS[@]} недостающих пакетов:"
            for p in "${MISSING_PKGS[@]}"; do
                echo "   - $p"
            done

            INSTALL_PROCEED=0
            if [ "$NON_INTERACTIVE" -eq 1 ]; then
                INSTALL_PROCEED=1
            elif [ "$DRY_RUN" -eq 1 ]; then
                echo "    [DRY-RUN] Будет выполнена команда: $PKG_INSTALL_CMD ${MISSING_PKGS[*]}"
            else
                read -rp "Желаете установить недостающие пакеты сейчас? [Y/n]: " answer
                answer="${answer:-y}"
                if [[ "$answer" =~ ^[YyДд]$ ]]; then
                    INSTALL_PROCEED=1
                else
                    echo "Пропуск установки пакетов."
                fi
            fi

            if [ "$INSTALL_PROCEED" -eq 1 ]; then
                if [ "$DRY_RUN" -eq 1 ]; then
                    echo "    [DRY-RUN] $PKG_INSTALL_CMD ${MISSING_PKGS[*]}"
                else
                    echo "==> Установка пакетов..."
                    $PKG_INSTALL_CMD "${MISSING_PKGS[@]}"
                fi
            fi
        fi
    fi
fi

echo "-----------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Восстановление конфигурационных файлов через restore.sh
# ------------------------------------------------------------------------------
echo "==> [Этап 2/3] Накат конфигураций KDE Plasma..."

if [ ! -f "$RESTORE_SCRIPT" ]; then
    echo "❌ ОШИБКА: Скрипт восстановления '$RESTORE_SCRIPT' не найден!" >&2
    exit 1
fi

RESTORE_ARGS=()
if [ "$DRY_RUN" -eq 1 ]; then
    RESTORE_ARGS+=("--dry-run")
fi
if [ "$USE_COPY" -eq 1 ]; then
    RESTORE_ARGS+=("--copy")
fi

bash "$RESTORE_SCRIPT" "${RESTORE_ARGS[@]}"

echo "-----------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Перезапуск сессии Plasma и KWin
# ------------------------------------------------------------------------------
echo "==> [Этап 3/3] Перезапуск сессии и графических компонентов..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [DRY-RUN] qdbus6 org.kde.KWin /KWin reconfigure"
    echo "    [DRY-RUN] systemctl --user restart plasma-plasmashell"
else
    # 1. Перезагрузка настроек оконного менеджера KWin
    if command -v qdbus6 >/dev/null 2>&1; then
        echo "    Применение конфигурации KWin..."
        qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || {
            echo "    (Примечание: KWin не запущен в текущей сессии или недоступен по DBus)"
        }
    elif command -v qdbus >/dev/null 2>&1; then
        echo "    Применение конфигурации KWin (qdbus)..."
        qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi

    # 2. Перезапуск оболочки Plasma через systemd user-сервис
    echo "    Перезапуск оболочки plasma-plasmashell..."
    if systemctl --user restart plasma-plasmashell >/dev/null 2>&1; then
        echo "    ✅ Служба plasma-plasmashell успешно перезапущена."
    else
        echo "    (Примечание: systemd user-сессия недоступна из текущего терминала. Настройки вступят в силу при следующем входе)."
    fi
fi

echo "================================================================="
echo "🎉 Развертывание KDE Plasma dotfiles завершено!"
echo "================================================================="
