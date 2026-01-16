#!/bin/bash

# Скрипт для создания универсальной сборки macOS приложения
# Использование: ./scripts/build-universal.sh или из корня проекта

set -e

# Определяем корневую директорию проекта (где находится .xcodeproj)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

PROJECT_NAME="MegaplanHepler"
SCHEME_NAME="MegaplanHepler"
BUILD_DIR="build"
ARCHIVE_DIR="${BUILD_DIR}/archive"
EXPORT_DIR="${BUILD_DIR}/export"
PROJECT_FILE="${PROJECT_NAME}.xcodeproj/project.pbxproj"
INFO_PLIST="Info.plist"

# Функция для обновления build number
update_build_number() {
    echo "🔢 Обновление build number..."
    
    # Получаем количество коммитов в текущей ветке
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
    
    # Если git недоступен, используем timestamp
    if [ "$BUILD_NUMBER" = "1" ] && ! git rev-parse --git-dir > /dev/null 2>&1; then
        BUILD_NUMBER=$(date +%s)
    fi
    
    echo "   Build number: ${BUILD_NUMBER}"
    
    # Обновляем CURRENT_PROJECT_VERSION в project.pbxproj
    if [ -f "$PROJECT_FILE" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$PROJECT_FILE" 2>/dev/null || {
                echo "⚠️  Предупреждение: не удалось обновить CURRENT_PROJECT_VERSION в project.pbxproj"
            }
        else
            sed -i "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$PROJECT_FILE" 2>/dev/null || {
                echo "⚠️  Предупреждение: не удалось обновить CURRENT_PROJECT_VERSION в project.pbxproj"
            }
        fi
        echo "   ✅ Обновлен CURRENT_PROJECT_VERSION в project.pbxproj"
    fi
    
    # Обновляем CFBundleVersion в Info.plist
    if [ -f "$INFO_PLIST" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # Используем PlistBuddy для более надежного обновления
            /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$INFO_PLIST" 2>/dev/null || {
                # Fallback на sed если PlistBuddy не работает (ищем конкретно CFBundleVersion)
                sed -i '' "/<key>CFBundleVersion<\/key>/,/<\/string>/s/<string>[0-9]*<\/string>/<string>${BUILD_NUMBER}<\/string>/" "$INFO_PLIST" 2>/dev/null || {
                    echo "⚠️  Предупреждение: не удалось обновить CFBundleVersion в Info.plist"
                }
            }
        else
            sed -i "/<key>CFBundleVersion<\/key>/,/<\/string>/s/<string>[0-9]*<\/string>/<string>${BUILD_NUMBER}<\/string>/" "$INFO_PLIST" 2>/dev/null || {
                echo "⚠️  Предупреждение: не удалось обновить CFBundleVersion в Info.plist"
            }
        fi
        echo "   ✅ Обновлен CFBundleVersion в Info.plist"
    fi
    
    echo "✅ Build number обновлен до: ${BUILD_NUMBER}"
}

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

# Обновляем build number перед сборкой
update_build_number

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
