#!/bin/sh
set -eu

PROJECT_FILE="${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"
STAMP_FILE="${DERIVED_FILE_DIR}/build_number.stamp"

if [ -d "${PROJECT_DIR}/.git" ]; then
  BUILD_NUMBER="$(git -C "${PROJECT_DIR}" rev-list --count HEAD 2>/dev/null || true)"
else
  BUILD_NUMBER=""
fi

if [ -z "${BUILD_NUMBER}" ]; then
  BUILD_NUMBER="$(date +%s)"
fi

if [ ! -f "${PROJECT_FILE}" ]; then
  echo "⚠️  Warning: Project file not found: ${PROJECT_FILE}"
  exit 0
fi

if /usr/bin/perl -0pi -e "s/CURRENT_PROJECT_VERSION = \\d+;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "${PROJECT_FILE}" 2>/dev/null; then
  echo "✅ Build number updated to: ${BUILD_NUMBER}"
else
  echo "⚠️  Warning: Could not update build number in ${PROJECT_FILE}"
fi

echo "${BUILD_NUMBER}" > "${STAMP_FILE}"
