#!/usr/bin/env bash
# 构建 CameraParallelServiceStub.apk —— SpecialTypesProvider 的最小替身。
#
# 依赖（主机）：
#   Android SDK build-tools 提供 aapt2 / d8 / zipalign / apksigner
#   JDK 17+ 提供 javac
#   不需要 gradle、不需要 androidx、不联网
#
# 用法：
#   KEYSTORE=~/aperture.keystore KS_ALIAS=aperture ./build.sh
#   KEYSTORE=... KS_ALIAS=... KS_PASS=... ./build.sh      # 非交互
#
# 产物：hyperos/camera/CameraParallelServiceStub.apk（与 port_build.sh 的期望路径一致）
#
# 签名的 key 必须和 Aperture 是同一套（docs/03 §3.2.2）；用别人签的 key 也能装，
# 但会和你的 Aperture 签名不一致，后续升级/共存容易出问题。
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$(cd "$HERE/.." && pwd)/CameraParallelServiceStub.apk}

die() { echo "error: $*" >&2; exit 1; }

[ -n "${KEYSTORE:-}" ] || die "设置 KEYSTORE=<keystore 路径>（应与 Aperture 同一套 key）"
[ -f "$KEYSTORE" ]     || die "keystore 不存在：$KEYSTORE"
[ -n "${KS_ALIAS:-}" ] || die "设置 KS_ALIAS=<keystore 里的别名>"

# --- 定位 SDK / 工具链 -------------------------------------------------------
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  for d in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" /opt/android-sdk /usr/lib/android-sdk; do
    [ -d "$d" ] && SDK=$d && break
  done
fi
[ -n "$SDK" ] && [ -d "$SDK" ] || die "找不到 Android SDK；设置 ANDROID_SDK_ROOT"

BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1 || true)
ANDROID_JAR=$(ls "$SDK"/platforms/*/android.jar 2>/dev/null | sort -V | tail -1 || true)
[ -n "$BT" ] || die "缺 build-tools（sdkmanager 'build-tools;35.0.0'）"
[ -n "$ANDROID_JAR" ] || die "缺 platforms/*/android.jar（sdkmanager 'platforms;android-35'）"

AAPT2="$BT/aapt2"
D8="$BT/d8"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"
for t in "$AAPT2" "$D8" "$ZIPALIGN" "$APKSIGNER"; do
  [ -x "$t" ] || die "缺可执行文件：$t"
done
command -v javac >/dev/null 2>&1 || die "缺 javac（JDK 17+）"

MIN_SDK=${MIN_SDK:-30}
TARGET_SDK=${TARGET_SDK:-35}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- 1) 资源表 + 清单 --------------------------------------------------------
echo "== aapt2 link"
"$AAPT2" link \
  -o "$WORK/base.apk" \
  -I "$ANDROID_JAR" \
  --manifest "$HERE/AndroidManifest.xml" \
  --min-sdk-version "$MIN_SDK" \
  --target-sdk-version "$TARGET_SDK"

# --- 2) 编译 ----------------------------------------------------------------
echo "== javac"
mkdir -p "$WORK/classes"
find "$HERE/java" -name '*.java' > "$WORK/sources.txt"
[ -s "$WORK/sources.txt" ] || die "没找到 java 源码"
javac -source 8 -target 8 -Xlint:-options \
      -bootclasspath "$ANDROID_JAR" \
      -d "$WORK/classes" \
      @"$WORK/sources.txt"

# --- 3) dex -----------------------------------------------------------------
echo "== d8"
mkdir -p "$WORK/dex"
"$D8" --release --min-api "$MIN_SDK" --lib "$ANDROID_JAR" \
      --output "$WORK/dex" \
      $(find "$WORK/classes" -name '*.class')

# --- 4) 组包 ----------------------------------------------------------------
echo "== package"
cp "$WORK/base.apk" "$WORK/unsigned.apk"
( cd "$WORK/dex" && zip -q -X "$WORK/unsigned.apk" classes.dex )

# --- 5) 对齐 + 签名 ---------------------------------------------------------
echo "== zipalign + apksigner"
"$ZIPALIGN" -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
if [ -n "${KS_PASS:-}" ]; then
  "$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias "$KS_ALIAS" \
    --ks-pass "pass:$KS_PASS" --out "$OUT" "$WORK/aligned.apk"
else
  echo "（交互输入 keystore 密码）"
  "$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias "$KS_ALIAS" \
    --out "$OUT" "$WORK/aligned.apk"
fi

"$APKSIGNER" verify --verbose "$OUT" >/dev/null
echo "== ok: $OUT ($(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT") bytes)"
"$AAPT2" dump badging "$OUT" | head -4
