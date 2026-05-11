#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_DIR/app"
RELEASE_DIR="$PROJECT_DIR/releases"
FLUTTER_APK_DIR="$APP_DIR/build/app/outputs/flutter-apk"
APP_NAME="爆肝AI"

cd "$APP_DIR"
flutter build apk --release --split-per-abi "$@"

VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml | cut -d+ -f1)"
mkdir -p "$RELEASE_DIR"
# 避免 releases/ 残留旧版本/旧命名 APK 造成误发；每次只保留当前构建输出。
find "$RELEASE_DIR" -maxdepth 1 -type f -name '*.apk' -delete

copied=0
for apk in "$FLUTTER_APK_DIR"/app-*-release.apk; do
  [ -f "$apk" ] || continue
  file_name="$(basename "$apk")"
  abi="${file_name#app-}"
  abi="${abi%-release.apk}"
  target_name="$APP_NAME-v$VERSION-$abi-release.apk"
  cp "$apk" "$FLUTTER_APK_DIR/$target_name"
  cp "$apk" "$RELEASE_DIR/$target_name"
  echo "$RELEASE_DIR/$target_name"
  copied=$((copied + 1))
done

if [ "$copied" -eq 0 ]; then
  source_apk="$FLUTTER_APK_DIR/app-release.apk"
  target_name="$APP_NAME-v$VERSION-release.apk"
  cp "$source_apk" "$FLUTTER_APK_DIR/$target_name"
  cp "$source_apk" "$RELEASE_DIR/$target_name"
  echo "$RELEASE_DIR/$target_name"
fi
