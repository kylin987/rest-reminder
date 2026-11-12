#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/休息提醒.app"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
MODE="${1:-}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile_slice() {
  local arch="$1"
  local output="$2"
  swiftc \
    -swift-version 5 \
    -O \
    -target "${arch}-apple-macosx14.0" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework ServiceManagement \
    -o "$output" \
    "$ROOT"/Sources/*.swift
}

if [[ "$MODE" == "--share" ]]; then
  compile_slice arm64 "/tmp/rest-arm64-$$"
  compile_slice x86_64 "/tmp/rest-x64-$$"
  lipo -create -output "$APP/Contents/MacOS/RestReminder" "/tmp/rest-arm64-$$" "/tmp/rest-x64-$$"
  rm -f "/tmp/rest-arm64-$$" "/tmp/rest-x64-$$"
else
  compile_slice arm64 "$APP/Contents/MacOS/RestReminder"
fi

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICON_PNG="/tmp/rest-icon-$$.png"
ICONSET="/tmp/rest-iconset-$$.iconset"
if swiftc -swift-version 5 -target arm64-apple-macosx14.0 -sdk "$SDK" -framework AppKit -o "/tmp/rest-make-icon-$$" "$ROOT/scripts/make_icon.swift" \
   && "/tmp/rest-make-icon-$$" "$ICON_PNG"; then
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
rm -f "/tmp/rest-make-icon-$$" "$ICON_PNG"
rm -rf "$ICONSET"

codesign --force --sign - "$APP" >/dev/null

if [[ "$MODE" == "--share" ]]; then
  STAGE="$(mktemp -d /tmp/rest-share.XXXXXX)"
  mkdir -p "$STAGE/休息提醒"
  cp -R "$APP" "$STAGE/休息提醒/"
  cat > "$STAGE/休息提醒/打开说明.txt" << 'EOF'
休息提醒

需要 macOS 14 或更新版本，Apple 芯片和 Intel 芯片都可以。

1. 把「休息提醒.app」拖进「应用程序」文件夹，再双击打开。
2. 如果系统提示「已损坏」或「无法验证开发者」：
   打开「终端」，输入下面这一行（末尾有一个空格），把应用拖进终端，然后回车：
   xattr -cr 
   完成后再次双击打开。
   也可以到「系统设置 → 隐私与安全性」里点「仍要打开」。
3. 菜单栏会出现杯子图标。点它就能改时长、暂停或退出。

请发送这个压缩包，不要直接发送 .app。聊天软件有时会把应用程序包拆坏。
EOF
  ZIP="$ROOT/dist/休息提醒.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$STAGE/休息提醒" "$ZIP"
  rm -rf "$STAGE"
  echo "share $ZIP"
elif [[ "$MODE" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  DEST="$HOME/Applications/休息提醒.app"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  xattr -cr "$DEST" || true
  codesign --force --sign - "$DEST" >/dev/null
  killall RestReminder >/dev/null 2>&1 || true
  open "$DEST"
  echo "installed $DEST"
else
  echo "built $APP"
fi
