#!/bin/bash

# Альтернативный скрипт для автоматического обновления номера билда
# Использует agvtool (Apple Generic Versioning Tool) - встроенный инструмент Xcode

set -e

# Получаем количество коммитов в текущей ветке
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

# Если git недоступен, используем timestamp
if [ "$BUILD_NUMBER" = "1" ] && ! git rev-parse --git-dir > /dev/null 2>&1; then
    BUILD_NUMBER=$(date +%s)
fi

# Используем agvtool для обновления build number
# agvtool требует, чтобы проект был настроен для использования версионирования
cd "${PROJECT_DIR}"

# Обновляем build number через agvtool
agvtool new-version -all "${BUILD_NUMBER}" 2>/dev/null || {
    # Если agvtool не работает, используем прямой метод
    PROJECT_FILE="${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"
    if [ -f "$PROJECT_FILE" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/g" "$PROJECT_FILE"
        else
            sed -i "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/g" "$PROJECT_FILE"
        fi
    fi
}

echo "✅ Build number updated to: ${BUILD_NUMBER}"

