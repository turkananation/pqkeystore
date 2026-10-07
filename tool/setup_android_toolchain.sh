#!/usr/bin/env bash
# Installs a JDK and the Android SDK command-line toolchain WITHOUT Android
# Studio, user-locally (no sudo). Every download is checksum-verified.
#
#   tool/setup_android_toolchain.sh            # JDK 25 + SDK (no emulator)
#   PQKS_WITH_EMULATOR=1 tool/setup_android_toolchain.sh
#   PQKS_TOOLCHAIN_DIR=/opt/tc tool/setup_android_toolchain.sh
#
# Versions are chosen for Flutter 3.47.x with Gradle 9.3.x:
#   - JDK 25 (current LTS; Flutter supports Java <= 25 with Gradle >= 9.1)
#   - compileSdk/targetSdk 36 (Flutter defaults), latest build-tools 36.x
# Re-running is safe; completed steps are skipped.
set -euo pipefail

JDK_MAJOR="${PQKS_JDK_MAJOR:-25}"
ANDROID_API="${PQKS_ANDROID_API:-36}"
ROOT="${PQKS_TOOLCHAIN_DIR:-$HOME/develop}"
JDK_DIR="$ROOT/jdk-$JDK_MAJOR"
SDK_DIR="$ROOT/android-sdk"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$(uname -m)" in
  x86_64) ADOPTIUM_ARCH=x64 ;;
  aarch64) ADOPTIUM_ARCH=aarch64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
for tool in curl python3 unzip tar sha256sum sha1sum; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
mkdir -p "$ROOT"
# Progress bars only on an interactive terminal.
if [ -t 2 ]; then CURL_PROGRESS="--progress-bar"; else CURL_PROGRESS="-sS"; fi

# ── JDK (Eclipse Temurin via the Adoptium API) ───────────────────────────
if [ -x "$JDK_DIR/bin/java" ]; then
  echo "JDK already present: $JDK_DIR"
else
  echo "Resolving latest Temurin JDK $JDK_MAJOR ($ADOPTIUM_ARCH)..."
  curl -fsSL "https://api.adoptium.net/v3/assets/latest/$JDK_MAJOR/hotspot?architecture=$ADOPTIUM_ARCH&image_type=jdk&os=linux&vendor=eclipse" \
    -o "$TMP/jdk.json"
  read -r JDK_URL JDK_SHA < <(python3 -c '
import json,sys
pkg=json.load(open(sys.argv[1]))[0]["binary"]["package"]
print(pkg["link"], pkg["checksum"])' "$TMP/jdk.json")
  echo "Downloading $JDK_URL"
  curl -fL $CURL_PROGRESS "$JDK_URL" -o "$TMP/jdk.tar.gz"
  echo "$JDK_SHA  $TMP/jdk.tar.gz" | sha256sum -c -
  mkdir -p "$JDK_DIR"
  tar -xzf "$TMP/jdk.tar.gz" -C "$JDK_DIR" --strip-components=1
fi
export JAVA_HOME="$JDK_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | head -1

# ── Android command-line tools (resolved from Google's repository index) ─
if [ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Android cmdline-tools already present: $SDK_DIR"
else
  echo "Resolving latest Android command-line tools..."
  curl -fsSL https://dl.google.com/android/repository/repository2-3.xml -o "$TMP/repo.xml"
  read -r TOOLS_FILE TOOLS_SHA1 < <(python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for pkg in root.iter("remotePackage"):
    if pkg.get("path") != "cmdline-tools;latest":
        continue
    for archive in pkg.iter("archive"):
        host = archive.find("host-os")
        if host is not None and host.text == "linux":
            c = archive.find("complete")
            print(c.find("url").text, c.find("checksum").text)
            sys.exit(0)
sys.exit("cmdline-tools;latest for linux not found")' "$TMP/repo.xml")
  echo "Downloading $TOOLS_FILE"
  curl -fL $CURL_PROGRESS "https://dl.google.com/android/repository/$TOOLS_FILE" -o "$TMP/tools.zip"
  echo "$TOOLS_SHA1  $TMP/tools.zip" | sha1sum -c -
  mkdir -p "$SDK_DIR/cmdline-tools"
  unzip -q "$TMP/tools.zip" -d "$TMP/tools"
  rm -rf "$SDK_DIR/cmdline-tools/latest"
  mv "$TMP/tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
fi
export ANDROID_HOME="$SDK_DIR"
export PATH="$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/platform-tools:$PATH"

# ── SDK packages ─────────────────────────────────────────────────────────
# Newer cmdline-tools ship the `android` CLI ("android sdk ...", '/'-separated
# package paths) and deprecate sdkmanager (';'-separated). Support both.
ANDROID_CLI="$SDK_DIR/cmdline-tools/latest/bin/android"
if [ -x "$ANDROID_CLI" ]; then
  sdk_list() { "$ANDROID_CLI" --sdk="$SDK_DIR" sdk list --all 2>/dev/null; }
  sdk_install() { "$ANDROID_CLI" --sdk="$SDK_DIR" sdk install "$@"; }
  SEP="/"
else
  yes | sdkmanager --sdk_root="$SDK_DIR" --licenses >/dev/null || true
  sdk_list() { sdkmanager --sdk_root="$SDK_DIR" --list 2>/dev/null; }
  sdk_install() { sdkmanager --sdk_root="$SDK_DIR" --install "$@"; }
  SEP=";"
fi

# Newest stable (non-rc) build-tools for the target API.
BUILD_TOOLS="$(sdk_list | grep -oE "build-tools${SEP}${ANDROID_API}\.[0-9]+\.[0-9]+([[:space:]]|$)" \
  | tr -d '[:space:]\n' | sed "s/build-tools/\nbuild-tools/g" | grep . | sort -V | tail -1 || true)"
[ -n "$BUILD_TOOLS" ] || BUILD_TOOLS="build-tools${SEP}${ANDROID_API}.0.0"

PACKAGES=("platform-tools" "platforms${SEP}android-$ANDROID_API" "$BUILD_TOOLS")
if [ "${PQKS_WITH_EMULATOR:-0}" = "1" ]; then
  PACKAGES+=("emulator" "system-images${SEP}android-$ANDROID_API${SEP}google_apis${SEP}x86_64")
fi
echo "Installing: ${PACKAGES[*]}"
sdk_install "${PACKAGES[@]}"

# ── Point Flutter at the toolchain ───────────────────────────────────────
if command -v flutter >/dev/null; then
  flutter config --jdk-dir="$JDK_DIR" --android-sdk="$SDK_DIR" >/dev/null
  yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
fi

cat <<EOF

Done. Add to your shell profile (~/.bashrc or ~/.zshrc):

  export JAVA_HOME="$JDK_DIR"
  export ANDROID_HOME="$SDK_DIR"
  export PATH="\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"

The NDK is downloaded automatically by the Android Gradle Plugin on first
build if needed. Verify with: flutter doctor -v
EOF
