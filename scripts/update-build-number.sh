#!/bin/bash

# Скрипт для автоматического обновления номера билда
# Использует количество коммитов в git как build number

set -e

# Получаем количество коммитов в текущей ветке
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

# Если git недоступен, используем timestamp
if [ "$BUILD_NUMBER" = "1" ] && ! git rev-parse --git-dir > /dev/null 2>&1; then
    BUILD_NUMBER=$(date +%s)
fi

# Обновляем CURRENT_PROJECT_VERSION в project.pbxproj
PROJECT_FILE="${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"

if [ -f "$PROJECT_FILE" ]; then
    # Обновляем CURRENT_PROJECT_VERSION для всех конфигураций
    # Используем sed с правильным синтаксисом для macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/g" "$PROJECT_FILE"
    else
        sed -i "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/g" "$PROJECT_FILE"
    fi
    echo "✅ Build number updated to: ${BUILD_NUMBER}"
else
    echo "⚠️  Warning: Project file not found at $PROJECT_FILE"
fi

