#!/bin/zsh
# TG-AISUM Mobile — Theos 式构建：swiftc + SDK 直接交叉编译，不依赖 Xcode 平台注册
# 产物: TGAISUM.ipa（未签名，TrollStore 直接安装）
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SDK=$(xcrun -sdk iphoneos --show-sdk-path)
TARGET=arm64-apple-ios16.0
APP_NAME=TGAISUM
BUILD="$ROOT/build/swiftc"
VENDOR=$ROOT/vendor

mkdir -p "$BUILD"

# 1) 定位 TDLibFramework.xcframework：优先 $TDLIB_XCFRAMEWORK，其次 vendor/，最后 /tmp/
CANDIDATES=("${TDLIB_XCFRAMEWORK:-}" "$ROOT/vendor/TDLibFramework.xcframework" "/tmp/TDLibFramework.xcframework")
XCF=""
for c in "${CANDIDATES[@]}"; do
  [ -n "$c" ] && [ -d "$c" ] && XCF="$c" && break
done
if [ -z "$XCF" ] && [ -f "$ROOT/vendor/TDLibFramework.zip" ]; then
  echo "解压 vendor/TDLibFramework.zip ..."
  (cd "$ROOT/vendor" && unzip -q -o TDLibFramework.zip)
  XCF="$ROOT/vendor/TDLibFramework.xcframework"
fi
if [ -z "$XCF" ]; then
  cat >&2 <<'MISSING'
缺少 TDLibFramework.xcframework。二选一：
  1) curl -L -o vendor/TDLibFramework.zip \
       https://github.com/Swiftgram/TDLibFramework/releases/download/1.8.69-4c6377aa/TDLibFramework.zip
  2) export TDLIB_XCFRAMEWORK=/path/to/TDLibFramework.xcframework
MISSING
  exit 1
fi
echo "Using xcframework: $XCF"
SLICE=""
for d in "$XCF/ios-arm64" "$XCF/ios-arm64_x86_64-simulator"; do
  [ -d "$d" ] && SLICE="$d" && break
done
if [ -z "$SLICE" ]; then
  SLICE=$(ls -d "$XCF"/ios-arm64* | head -1)
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
if [ -d "$ROOT/assets" ]; then
  cp "$ROOT"/assets/AppIcon*.png "$STAGE/" 2>/dev/null || true
fi

if [ "$DYNAMIC" -gt 0 ]; then
  mkdir -p "$STAGE/Frameworks"
  cp -R "$FW" "$STAGE/Frameworks/"
  ldid -S "$STAGE/Frameworks/TDLibFramework.framework/TDLibFramework" 2>/dev/null || true
fi

# strip 与 ldid 顺序固定：先瘦身再签名，否则签名失效
strip -x "$STAGE/$APP_NAME" 2>/dev/null || true
ldid -S "$STAGE/$APP_NAME"
plutil -lint "$STAGE/Info.plist"

cd "$BUILD"
rm -f "$ROOT/$APP_NAME.ipa"
zip -qry "$ROOT/$APP_NAME.ipa" Payload
VER=$(plutil -extract CFBundleShortVersionString raw "$STAGE/Info.plist")
cp "$ROOT/$APP_NAME.ipa" "$ROOT/$APP_NAME-$VER.ipa"
echo "IPA 已生成: $ROOT/$APP_NAME.ipa（副本 $APP_NAME-$VER.ipa）"
