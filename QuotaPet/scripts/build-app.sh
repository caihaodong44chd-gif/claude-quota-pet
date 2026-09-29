#!/usr/bin/env bash
# 把 SwiftPM 编译出来的可执行文件打包成 build/QuotaPet.app（ad-hoc 签名）
# UNIVERSAL=1 时 Apple 芯片和 Intel 各编一份再合成一个（make release 用）
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/QuotaPet.app

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${UNIVERSAL:-}" == 1 ]]; then
    # 命令行工具里没有 XCBuild，--arch 两个一起编不了，只能按 triple 各编一次再用 lipo 合并。
    # 下面渲染图标用本机架构的那份（BIN），不用再单独编一次本机的
    bins=()
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx14.0"
        swift build -c release --product QuotaPet --triple "$triple"
        bin="$(swift build -c release --triple "$triple" --show-bin-path)/QuotaPet"
        bins+=("$bin")
        if [[ "$arch" == "$(uname -m)" ]]; then BIN="$bin"; fi
    done
    lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/QuotaPet"
else
    swift build -c release --product QuotaPet
    BIN="$(swift build -c release --show-bin-path)/QuotaPet"
    cp "$BIN" "$APP/Contents/MacOS/QuotaPet"
fi
# 去掉调试符号：链接器会把编译时每个 .o 的本机绝对路径（带用户名）记在里面，发出去的包不能带
strip -S "$APP/Contents/MacOS/QuotaPet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"  # 各语言的 App 名字（访达、通知里显示的）

# 用宠物的像素画生成 App 图标
"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "✅ 已生成 $APP"
