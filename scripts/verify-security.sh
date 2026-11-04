#!/usr/bin/env bash
# ==============================================================================
# verify-security.sh: Сканирование файлов на наличие секретов и токенов
# ==============================================================================
set -euo pipefail

# Регулярное выражение для поиска секретов, приватных ключей, паролей и токенов
SENSITIVE_REGEX="(password[[:space:]]*=|passwd[[:space:]]*=|secret[[:space:]]*=|api[_-]?key|bearer[[:space:]]+[a-zA-Z0-9_\-\.]+|private[_-]?key|BEGIN[ A-Z0-9_-]*PRIVATE KEY|kwallet|auth[_-]?token|access[_-]?token)"

TARGET_DIR="${1:-$(dirname "$0")/../config}"

echo "==> Сканирование конфигурационных файлов в: $TARGET_DIR"
FOUND=0

while IFS= read -r -d '' file; do
    # Исключаем файлы в .git
    if [[ "$file" == *"/.git/"* ]]; then
        continue
    fi

    # Сканирование содержимого через grep -Ei
    MATCHES=$(grep -Ein "$SENSITIVE_REGEX" "$file" 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
        echo "❌ [ТРЕВОГА] Подозрительные данные в '$file':"
        echo "$MATCHES"
        echo "----------------------------------------------------"
        FOUND=1
    fi
done < <(find "$TARGET_DIR" -type f -print0)

if [ $FOUND -ne 0 ]; then
    echo "❌ ОШИБКА: Обнаружены потенциально чувствительные данные!"
    exit 1
else
    echo "✅ Проверка безопасности успешно пройдена: чувствительные данные не найдены."
    exit 0
fi
