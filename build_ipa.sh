#!/bin/zsh
# TG-AISUM Mobile — Theos 式构建：swiftc + SDK 直接交叉编译，不依赖 Xcode 平台注册
# 产物: TGAISUM.ipa（未签名，TrollStore 直接安装）
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SDK=$(xcrun -sdk iphoneos --show-sdk-path)
TARGET=arm64-apple-ios16.0
APP_NAME=TGAISUM
BUILD=build/swiftc
VENDOR=$ROOT/vendor

mkdir -p "$BUILD"

# 1) 找 TDLibFramework 的 iOS arm64 切片
if [ ! -d /tmp/TDLibFramework.xcframework ]; then
  echo "缺少 TDLibFramework，先解压 vendor 包" >&2
  exit 1
fi
SLICE=""
for d in /tmp/TDLibFramework.xcframework/ios-arm64 /tmp/TDLibFramework.xcframework/ios-arm64_x86_64-simulator; do
  [ -d "$d" ] && SLICE="$d" && break
done
if [ -z "$SLICE" ]; then
  SLICE=$(ls -d /tmp/TDLibFramework.xcframework/ios-arm64* | head -1)
fi
FW="$SLICE/TDLibFramework.framework"
echo "Framework slice: $FW"
otool -l "$FW/TDLibFramework" | grep -m1 "LC_ID_DYLIB\|LC_RPATH" >/dev/null 2>&1 || true
DYNAMIC=$(otool -hv "$FW/TDLibFramework" 2>/dev/null | grep -c DYLIB || true)
echo "Framework type: DYLIB=$DYNAMIC"

FRAMEWORK_LINK_FLAGS=(-F"$SLICE" -framework TDLibFramework)

# 2) 先产出 TDLibKit 模块（swiftmodule + 静态库），App 再导入链接
#    （必须分模块：TDLibKit 里有与 Foundation 重名的生成类型如 Date）
TDLIBKIT_SRCS=("$VENDOR"/TDLibKit/**/*.swift(N))

if [ -f "$BUILD/libTDLibKit.a" ] && [ -f "$BUILD/TDLibKit.swiftmodule" ]; then
  echo "=== 复用已编译的 TDLibKit ==="
else
echo "=== 编译 TDLibKit 模块接口 ==="
swiftc \
  -sdk "$SDK" -target "$TARGET" \
  -swift-version 5 -Onone \
  -parse-as-library \
  -module-name TDLibKit \
  -emit-module -emit-module-path "$BUILD/TDLibKit.swiftmodule" \
  -Xcc -fmodule-map-file="$VENDOR/TDLibShim/module.modulemap" -Xcc -I"$VENDOR/TDLibShim" \
  "${TDLIBKIT_SRCS[@]}"

echo "=== 编译 TDLibKit 静态库 ==="
swiftc \
  -sdk "$SDK" -target "$TARGET" \
  -swift-version 5 -Onone \
  -parse-as-library \
  -module-name TDLibKit \
  -emit-library -static -o "$BUILD/libTDLibKit.a" \
  -Xcc -fmodule-map-file="$VENDOR/TDLibShim/module.modulemap" -Xcc -I"$VENDOR/TDLibShim" \
  "${TDLIBKIT_SRCS[@]}"
fi

# 3) 编译 App
echo "=== 编译 App ==="
APP_SRCS=(TGAISUM/**/*.swift(N))

swiftc \
  -sdk "$SDK" -target "$TARGET" \
  -swift-version 5 -Onone \
  -parse-as-library \
  -module-name TGAISUM \
  -I "$BUILD" \
  -Xcc -fmodule-map-file="$VENDOR/TDLibShim/module.modulemap" -Xcc -I"$VENDOR/TDLibShim" \
  "${FRAMEWORK_LINK_FLAGS[@]}" \
  -Xlinker -lc++ -Xlinker -lz \
  -o "$BUILD/$APP_NAME" \
  "$BUILD/libTDLibKit.a" \
  "${APP_SRCS[@]}"

# 4) 组装 .app + ldid 签名 + IPA
echo "=== 组装 IPA ==="
STAGE="$BUILD/Payload/$APP_NAME.app"
rm -rf "$BUILD/Payload"
mkdir -p "$STAGE"
cp "$BUILD/$APP_NAME" "$STAGE/$APP_NAME"
cp Info_plist_template.plist "$STAGE/Info.plist"

if [ "$DYNAMIC" -gt 0 ]; then
  mkdir -p "$STAGE/Frameworks"
  cp -R "$FW" "$STAGE/Frameworks/"
  ldid -S "$STAGE/Frameworks/TDLibFramework.framework/TDLibFramework" 2>/dev/null || true
fi

ldid -S "$STAGE/$APP_NAME"
plutil -lint "$STAGE/Info.plist"

cd "$BUILD"
rm -f "$ROOT/$APP_NAME.ipa"
zip -qry "$ROOT/$APP_NAME.ipa" Payload
echo "IPA 已生成: $ROOT/$APP_NAME.ipa"
