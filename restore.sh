#!/usr/bin/env bash
# ==============================================================================
# restore.sh: Развертывание настроек KDE Plasma из репозитория в ~/.config
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_CONFIG="$SCRIPT_DIR/config"
SYSTEM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

DRY_RUN=0
USE_COPY=0
SHOW_HELP=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        --copy)
            USE_COPY=1
            ;;
        -h|--help)
            SHOW_HELP=1
            ;;
        *)
            echo "Неизвестный параметр: $arg"
            echo "Использование: $0 [--dry-run] [--copy]"
            exit 1
            ;;
    esac
done

if [ "$SHOW_HELP" -eq 1 ]; then
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "Опции:"
    echo "  --dry-run   Имитация развертывания без изменения файлов"
    echo "  --copy      Копировать файлы вместо создания символических ссылок"
    echo "  -h, --help  Показать эту справку"
    exit 0
fi

echo "================================================================="
echo "  KDE Plasma Dotfiles Restore"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Режим: DRY-RUN (симуляция, файлы не изменяются)"
fi
echo "  Метод: $([ "$USE_COPY" -eq 1 ] && echo "Копирование (copy)" || echo "Символические ссылки (symlink)")"
echo "================================================================="
echo "Источник (репозиторий): $DOTFILES_CONFIG"
echo "Целевой каталог:       $SYSTEM_CONFIG"
echo "-----------------------------------------------------------------"

# Проверка наличия каталога config в репозитории
if [ ! -d "$DOTFILES_CONFIG" ]; then
    echo "❌ ОШИБКА: Каталог '$DOTFILES_CONFIG' не найден!" >&2
    exit 1
fi

# Поиск всех файлов в репозитории для восстановления
mapfile -t FILES_TO_RESTORE < <(find "$DOTFILES_CONFIG" -maxdepth 1 -type f -printf "%f\n" | sort)

if [ "${#FILES_TO_RESTORE[@]}" -eq 0 ]; then
    echo "⚠️ В каталоге $DOTFILES_CONFIG нет конфигурационных файлов для восстановления."
    exit 0
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$SYSTEM_CONFIG/kde_backup_$TIMESTAMP"
BACKUP_CREATED=0

# Шаг 1: Резервное копирование существующих файлов в ~/.config
echo "==> Проверка существующих файлов в системе..."
for file in "${FILES_TO_RESTORE[@]}"; do
    target="$SYSTEM_CONFIG/$file"
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$BACKUP_CREATED" -eq 0 ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "    [DRY-RUN] Будет создан каталог бэкапа: $BACKUP_DIR"
            else
                mkdir -p "$BACKUP_DIR"
                echo "    Создан каталог резервной копии: $BACKUP_DIR"
            fi
            BACKUP_CREATED=1
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [DRY-RUN] Бэкап: $target -> $BACKUP_DIR/$file"
        else
            cp -a "$target" "$BACKUP_DIR/$file"
            echo "    Сохранен бэкап: $file"
        fi
    fi
done

if [ "$BACKUP_CREATED" -eq 0 ]; then
    echo "    Существующих файлов для бэкапа не найдено (чистая установка)."
fi

echo "-----------------------------------------------------------------"
echo "==> Применение конфигураций..."

RESTORED_COUNT=0

for file in "${FILES_TO_RESTORE[@]}"; do
    src="$DOTFILES_CONFIG/$file"
    target="$SYSTEM_CONFIG/$file"

    if [ ! -f "$src" ]; then
        echo "⚠️ Файл $src не найден, пропуск."
        continue
    fi

    if [ "$USE_COPY" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [DRY-RUN] cp -p '$src' '$target'"
        else
            mkdir -p "$(dirname "$target")"
            cp -p "$src" "$target"
            echo "    [Скопирован] $file -> $target"
        fi
    else
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [DRY-RUN] ln -sf '$src' '$target'"
        else
            mkdir -p "$(dirname "$target")"
            # Удаляем старый файл/ссылку перед созданием новой симлинки
            rm -f "$target"
            ln -s "$src" "$target"
            echo "    [Симлинк] $target -> $src"
        fi
    fi
    RESTORED_COUNT=$((RESTORED_COUNT + 1))
done

echo "-----------------------------------------------------------------"
echo "Успешно обработано файлов: $RESTORED_COUNT"
if [ "$BACKUP_CREATED" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo "Резервная копия старых файлов сохранена в: $BACKUP_DIR"
fi

echo "================================================================="
echo "Для применения настроек перезапустите оболочку Plasma:"
echo ""
echo "  • Для Plasma 6:"
echo "      kquitapp6 plasmashell && kstart plasmashell"
echo "      qdbus org.kde.KWin /KWin reconfigure"
echo ""
echo "  • Для Plasma 5:"
echo "      kquitapp5 plasmashell && kstart plasmashell"
echo "      qdbus org.kde.KWin /KWin reconfigure"
echo "================================================================="
