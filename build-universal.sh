#!/bin/bash

# Скрипт для создания универсальной сборки macOS приложения
# Использование: ./build-universal.sh

set -e

PROJECT_NAME="MegaplanHepler"
SCHEME_NAME="MegaplanHepler"
BUILD_DIR="build"
ARCHIVE_DIR="${BUILD_DIR}/archive"
EXPORT_DIR="${BUILD_DIR}/export"

# Проверка и настройка Xcode
echo "🔍 Проверка Xcode..."
if [ -d "/Applications/Xcode.app" ]; then
    CURRENT_XCODE=$(xcode-select -p 2>/dev/null || echo "")
    XCODE_PATH="/Applications/Xcode.app/Contents/Developer"
    if [ "$CURRENT_XCODE" != "$XCODE_PATH" ]; then
        echo "⚠️  xcode-select указывает на: ${CURRENT_XCODE}"
        echo "⚙️  Переключаю на Xcode (требуется sudo)..."
        if sudo xcode-select -s "$XCODE_PATH" 2>/dev/null; then
            echo "✅ Переключено на Xcode"
        else
            echo "❌ Не удалось переключить xcode-select"
            echo "   Выполните вручную: sudo xcode-select -s $XCODE_PATH"
            exit 1
        fi
    else
        echo "✅ Xcode настроен правильно"
    fi
else
    echo "❌ Ошибка: Xcode не найден в /Applications/Xcode.app"
    echo "   Установите Xcode из App Store"
    exit 1
fi

echo "🧹 Очистка предыдущих сборок..."
rm -rf "${BUILD_DIR}"
mkdir -p "${ARCHIVE_DIR}"
mkdir -p "${EXPORT_DIR}"

echo "📦 Создание Archive..."
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_DIR}/${PROJECT_NAME}.xcarchive" \
    -destination "generic/platform=macOS" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual" \
    DEVELOPMENT_TEAM="" \
    2>&1 | grep -v "warning:" || true

echo "📤 Экспорт приложения..."
# Пробуем экспортировать через exportOptions.plist
if [ -f "exportOptions.plist" ]; then
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_DIR}/${PROJECT_NAME}.xcarchive" \
        -exportPath "${EXPORT_DIR}" \
        -exportOptionsPlist exportOptions.plist 2>/dev/null || {
        echo "⚠️  Экспорт через exportOptions.plist не удался, используем приложение из архива"
    }
fi

# Ищем приложение в экспорте или в архиве
APP_PATH="${EXPORT_DIR}/${PROJECT_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    # Если экспорт не создал .app, берем из архива
    APP_PATH="${ARCHIVE_DIR}/${PROJECT_NAME}.xcarchive/Products/Applications/${PROJECT_NAME}.app"
    if [ -d "$APP_PATH" ]; then
        echo "📋 Копирую приложение из архива в export..."
        cp -R "$APP_PATH" "${EXPORT_DIR}/"
        APP_PATH="${EXPORT_DIR}/${PROJECT_NAME}.app"
    fi
fi

if [ -d "$APP_PATH" ]; then
    echo "✅ Приложение создано: ${APP_PATH}"
    echo "📊 Размер: $(du -sh "${APP_PATH}" | cut -f1)"
    echo "🏗️  Архитектуры: $(lipo -info "${APP_PATH}/Contents/MacOS/${PROJECT_NAME}" 2>/dev/null || echo 'N/A')"
    echo ""
    echo "📦 Для распространения скопируйте ${APP_PATH} на другой Mac"
else
    echo "❌ Ошибка: приложение не найдено"
    exit 1
fi

