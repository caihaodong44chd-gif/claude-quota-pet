#!/usr/bin/env bash
# 把 SwiftPM 编译出来的可执行文件打包成 build/QuotaPet.app（ad-hoc 签名，本机自用）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product QuotaPet
BIN="$(swift build -c release --show-bin-path)/QuotaPet"
APP=build/QuotaPet.app

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuotaPet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"  # 各语言的 App 名字（访达、通知里显示的）

# 用宠物的像素画生成 App 图标
"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "✅ 已生成 $APP"
