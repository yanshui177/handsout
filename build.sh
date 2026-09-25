#!/bin/bash
# Handsout 打包脚本：编译 release 产物并组装成 .app bundle
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 编译 release..."
# 部分受限环境（如 CI / 沙箱内）无法使用 SwiftPM 自带的 sandbox，失败则回退
swift build -c release || swift build -c release --disable-sandbox

APP="dist/Handsout.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/Handsout" "$APP/Contents/MacOS/Handsout"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if [ ! -f "Resources/AppIcon.icns" ]; then
  echo "==> 生成应用图标..."
  python3 Scripts/make_icon.py
fi
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名..."
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    (签名跳过，非致命)"

echo "==> 完成: $(pwd)/$APP"
