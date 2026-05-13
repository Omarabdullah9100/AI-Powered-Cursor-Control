#!/bin/bash
# AIPointer Release Build Script v2
#
# Usage:
#   ./scripts/release-build.sh                  build all platforms, sign + notarize where possible
#   ./scripts/release-build.sh 1.0.0            same, explicit version
#   ./scripts/release-build.sh 1.0.0 --mac      mac only
#   ./scripts/release-build.sh 1.0.0 --mac --linux   mac + linux, skip windows
#   ./scripts/release-build.sh 1.0.0 --no-sign       skip all signing
#   ./scripts/release-build.sh 1.0.0 --no-notarize   sign but skip Apple notary
#   ./scripts/release-build.sh 1.0.0 --no-clean      keep existing release/ folder (incremental)
#
# Resilience model:
#   Each platform build is wrapped in its own error handler. If Windows fails
#   on a Mac host (common: missing Wine, missing mono), Linux + Mac still run.
#   At the end, the script reports which platforms succeeded and writes
#   latest.json with ONLY the successfully built artifacts. Partial releases
#   are valid; the auto-updater only advertises what actually exists.
#
# Signing:
#   The Mac identity is configured in electron-builder.yml. If that identity
#   matches a cert in your Keychain, the Mac build is auto-signed regardless
#   of --no-sign (electron-builder discovers it). To force truly unsigned Mac
#   builds, temporarily remove the identity line from electron-builder.yml.
#
# Notarization:
#   Requires APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD in env.
#   Without them, signed-but-not-notarized DMGs are produced (still installable,
#   user just sees the unidentified-developer prompt on first launch). With --no-
#   notarize, notarization is explicitly skipped.
#
# SHA-512 must be hex (128 chars). The script refuses to write latest.json if
# any sha is the wrong length (defends against accidental base64 piping).

# NOT using `set -e` because we want per-platform resilience.
# Using `set -u` to catch typos in variable names.
set -u

# ── Config ────────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/release"
VITE_DIST_DIR="$ROOT_DIR/dist"
DIST_ELECTRON_DIR="$ROOT_DIR/dist-electron"
RELEASE_DIR="$DIST_DIR/release-artifacts"
META_ROOT_DIR="$RELEASE_DIR/metadata-root"
META_UPDATES_DIR="$RELEASE_DIR/metadata-updates"

UPDATES_URL_BASE="https://aipointer.app/updates"

# ── Parse args ────────────────────────────────────────────────────────────
cd "$ROOT_DIR"

VERSION=""
DO_MAC=0
DO_WIN=0
DO_LINUX=0
DO_SIGN=1
DO_NOTARIZE=1
CLEAN=1
EXPLICIT_TARGETS=0

for arg in "$@"; do
  case "$arg" in
    --mac)         DO_MAC=1;   EXPLICIT_TARGETS=1 ;;
    --win)         DO_WIN=1;   EXPLICIT_TARGETS=1 ;;
    --linux)       DO_LINUX=1; EXPLICIT_TARGETS=1 ;;
    --no-sign)     DO_SIGN=0 ;;
    --no-notarize) DO_NOTARIZE=0 ;;
    --no-clean)    CLEAN=0 ;;
    --help|-h)
      grep -E '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg"
      exit 1
      ;;
    *)
      if [ -z "$VERSION" ]; then VERSION="$arg"; fi
      ;;
  esac
done

# Default: all platforms if none specified
if [ "$EXPLICIT_TARGETS" = "0" ]; then
  DO_MAC=1
  DO_WIN=1
  DO_LINUX=1
fi

if [ -z "$VERSION" ]; then
  VERSION=$(node -p "require('./package.json').version")
fi

ACTUAL_VERSION=$(node -p "require('./package.json').version")
if [ "$VERSION" != "$ACTUAL_VERSION" ]; then
  echo "Warning: requested version $VERSION differs from package.json version $ACTUAL_VERSION"
  echo "Continue? [y/N]"
  read -r response
  if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
    echo "Aborted."
    exit 1
  fi
fi

ARCH=$(uname -m)
HOST_OS=$(uname -s)
TODAY_SHORT=$(date -u +"%Y-%m-%d")
TODAY_FULL=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo ""
echo "=============================================="
echo "  AIPointer Release Build, v${VERSION}"
echo "=============================================="
echo "Root:        $ROOT_DIR"
echo "Host:        $HOST_OS $ARCH"
printf "Targets:    "
[ "$DO_MAC" = "1" ]   && printf " mac"
[ "$DO_WIN" = "1" ]   && printf " win"
[ "$DO_LINUX" = "1" ] && printf " linux"
echo ""
echo "Sign:        $DO_SIGN"
echo "Notarize:    $DO_NOTARIZE"
echo "Clean first: $CLEAN"
echo "Updates URL: $UPDATES_URL_BASE"
echo ""

# ── Honor --no-sign / --no-notarize via env vars ─────────────────────────
if [ "$DO_SIGN" = "0" ]; then
  echo "[env] Signing disabled. Unsetting CSC_* + APPLE_*."
  unset CSC_LINK             2>/dev/null || true
  unset CSC_KEY_PASSWORD     2>/dev/null || true
  unset APPLE_ID             2>/dev/null || true
  unset APPLE_TEAM_ID        2>/dev/null || true
  unset APPLE_APP_SPECIFIC_PASSWORD 2>/dev/null || true
  export CSC_IDENTITY_AUTO_DISCOVERY=false
fi
if [ "$DO_NOTARIZE" = "0" ]; then
  echo "[env] Notarization disabled. Unsetting APPLE_*."
  unset APPLE_ID             2>/dev/null || true
  unset APPLE_TEAM_ID        2>/dev/null || true
  unset APPLE_APP_SPECIFIC_PASSWORD 2>/dev/null || true
fi

# ── Status tracking ──────────────────────────────────────────────────────
# 0 = not built, 1 = success, 2 = failed
STATUS_MAC=0
STATUS_WIN=0
STATUS_LINUX=0
ERRORS=()

# ── Step 1: Clean + raise ulimit ─────────────────────────────────────────
if [ "$CLEAN" = "1" ]; then
  echo "--- Step 1/5: Clean + raise ulimit ---"
  rm -rf "$DIST_DIR" "$VITE_DIST_DIR" "$DIST_ELECTRON_DIR"
  echo "Cleaned dist/, dist-electron/, release/"
else
  echo "--- Step 1/5: Skip clean (--no-clean) + raise ulimit ---"
fi

ulimit -n 524288 2>/dev/null || ulimit -n 8192 2>/dev/null || true
echo "Open file limit: $(ulimit -n)"
echo ""

# ── Step 2: Build each requested platform with isolation ─────────────────
echo "--- Step 2/5: Build platforms ---"
echo ""

build_mac() {
  echo ">>> macOS (arm64 + x64)"
  if npm run dist:mac; then
    STATUS_MAC=1
    echo "<<< macOS OK"
  else
    STATUS_MAC=2
    ERRORS+=("macOS build failed (see electron-builder output above)")
    echo "<<< macOS FAILED, continuing"
  fi
  echo ""
}

build_win() {
  echo ">>> Windows (x64)"
  if [ "$HOST_OS" = "Darwin" ]; then
    echo "    Note: cross-compiling Windows from macOS requires Wine + mono."
    echo "    If this fails, install via: brew install --cask wine-stable && brew install mono"
  fi
  if npm run dist:win; then
    STATUS_WIN=1
    echo "<<< Windows OK"
  else
    STATUS_WIN=2
    ERRORS+=("Windows build failed (cross-compile dependency or signing issue)")
    echo "<<< Windows FAILED, continuing"
  fi
  echo ""
}

build_linux() {
  echo ">>> Linux (x64 AppImage)"
  if npm run dist:linux; then
    STATUS_LINUX=1
    echo "<<< Linux OK"
  else
    STATUS_LINUX=2
    ERRORS+=("Linux build failed")
    echo "<<< Linux FAILED, continuing"
  fi
  echo ""
}

[ "$DO_MAC" = "1" ]   && build_mac
[ "$DO_WIN" = "1" ]   && build_win
[ "$DO_LINUX" = "1" ] && build_linux

echo "Build phase complete."
echo ""

# ── Step 3: Locate artifacts (flexible naming) ────────────────────────────
echo "--- Step 3/5: Locate produced binaries ---"

# Try multiple naming patterns electron-builder may use across versions.
find_first() {
  for path in "$@"; do
    if [ -f "$path" ]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

DMG_ARM64=$(find_first \
  "$DIST_DIR/AIPointer-${VERSION}-arm64.dmg" \
  "$DIST_DIR/AIPointer ${VERSION}-arm64.dmg" \
  "$DIST_DIR/AIPointer-${VERSION}-arm64-mac.dmg" \
  || echo "")
DMG_X64=$(find_first \
  "$DIST_DIR/AIPointer-${VERSION}-x64.dmg" \
  "$DIST_DIR/AIPointer ${VERSION}.dmg" \
  "$DIST_DIR/AIPointer-${VERSION}.dmg" \
  || echo "")
ZIP_ARM64=$(find_first \
  "$DIST_DIR/AIPointer-${VERSION}-arm64-mac.zip" \
  "$DIST_DIR/AIPointer-${VERSION}-arm64.zip" \
  || echo "")
ZIP_X64=$(find_first \
  "$DIST_DIR/AIPointer-${VERSION}-x64-mac.zip" \
  "$DIST_DIR/AIPointer-${VERSION}-mac.zip" \
  "$DIST_DIR/AIPointer-${VERSION}-x64.zip" \
  || echo "")
EXE_WIN=$(find_first \
  "$DIST_DIR/AIPointer-Setup-${VERSION}.exe" \
  "$DIST_DIR/AIPointer Setup ${VERSION}.exe" \
  "$DIST_DIR/AIPointer-${VERSION}-Setup.exe" \
  || echo "")
APPIMAGE=$(find_first \
  "$DIST_DIR/AIPointer-${VERSION}-x86_64.AppImage" \
  "$DIST_DIR/AIPointer-${VERSION}.AppImage" \
  "$DIST_DIR/AIPointer ${VERSION}.AppImage" \
  || echo "")

echo "Looking for artifacts in $DIST_DIR..."
[ -n "$DMG_ARM64" ] && echo "  FOUND $DMG_ARM64"
[ -n "$DMG_X64" ]   && echo "  FOUND $DMG_X64"
[ -n "$ZIP_ARM64" ] && echo "  FOUND $ZIP_ARM64"
[ -n "$ZIP_X64" ]   && echo "  FOUND $ZIP_X64"
[ -n "$EXE_WIN" ]   && echo "  FOUND $EXE_WIN"
[ -n "$APPIMAGE" ]  && echo "  FOUND $APPIMAGE"
echo ""

# Verify expected files per platform that succeeded
mac_missing=0
if [ "$STATUS_MAC" = "1" ]; then
  [ -z "$DMG_ARM64" ] && { echo "  MISS arm64 DMG (mac build said OK but no file)"; mac_missing=$((mac_missing+1)); }
  [ -z "$DMG_X64"   ] && { echo "  MISS x64 DMG (mac build said OK but no file)"; mac_missing=$((mac_missing+1)); }
  if [ "$mac_missing" -gt 0 ]; then
    STATUS_MAC=2
    ERRORS+=("mac build reported OK but produced $mac_missing fewer artifacts than expected")
  fi
fi
if [ "$STATUS_WIN" = "1" ] && [ -z "$EXE_WIN" ]; then
  echo "  MISS Windows EXE (win build said OK but no file)"
  STATUS_WIN=2
  ERRORS+=("windows build reported OK but produced no EXE")
fi
if [ "$STATUS_LINUX" = "1" ] && [ -z "$APPIMAGE" ]; then
  echo "  MISS Linux AppImage (linux build said OK but no file)"
  STATUS_LINUX=2
  ERRORS+=("linux build reported OK but produced no AppImage")
fi
echo ""

# ── Step 4: Compute SHA-512 HEX + sizes for successful artifacts ─────────
echo "--- Step 4/5: Compute SHA-512 HEX ---"

sha_hex() { shasum -a 512 "$1" | awk '{print $1}'; }
size_bytes() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

DMG_ARM64_SHA=""; DMG_ARM64_SIZE=""
DMG_X64_SHA="";   DMG_X64_SIZE=""
ZIP_ARM64_SHA=""; ZIP_ARM64_SIZE=""
ZIP_X64_SHA="";   ZIP_X64_SIZE=""
EXE_WIN_SHA="";   EXE_WIN_SIZE=""
APPIMAGE_SHA="";  APPIMAGE_SIZE=""

[ -n "$DMG_ARM64" ] && { DMG_ARM64_SHA=$(sha_hex "$DMG_ARM64"); DMG_ARM64_SIZE=$(size_bytes "$DMG_ARM64"); }
[ -n "$DMG_X64"   ] && { DMG_X64_SHA=$(sha_hex "$DMG_X64");     DMG_X64_SIZE=$(size_bytes "$DMG_X64");     }
[ -n "$ZIP_ARM64" ] && { ZIP_ARM64_SHA=$(sha_hex "$ZIP_ARM64"); ZIP_ARM64_SIZE=$(size_bytes "$ZIP_ARM64"); }
[ -n "$ZIP_X64"   ] && { ZIP_X64_SHA=$(sha_hex "$ZIP_X64");     ZIP_X64_SIZE=$(size_bytes "$ZIP_X64");     }
[ -n "$EXE_WIN"   ] && { EXE_WIN_SHA=$(sha_hex "$EXE_WIN");     EXE_WIN_SIZE=$(size_bytes "$EXE_WIN");     }
[ -n "$APPIMAGE"  ] && { APPIMAGE_SHA=$(sha_hex "$APPIMAGE");   APPIMAGE_SIZE=$(size_bytes "$APPIMAGE");   }

check_hex_or_die() {
  local label="$1"; local v="$2"
  if [ -n "$v" ] && [ "${#v}" -ne 128 ]; then
    echo "FATAL: $label sha is ${#v} chars, expected 128 (hex). Refusing to write metadata."
    exit 1
  fi
}
check_hex_or_die "DMG_ARM64"  "$DMG_ARM64_SHA"
check_hex_or_die "DMG_X64"    "$DMG_X64_SHA"
check_hex_or_die "ZIP_ARM64"  "$ZIP_ARM64_SHA"
check_hex_or_die "ZIP_X64"    "$ZIP_X64_SHA"
check_hex_or_die "EXE_WIN"    "$EXE_WIN_SHA"
check_hex_or_die "APPIMAGE"   "$APPIMAGE_SHA"

[ -n "$DMG_ARM64_SHA" ] && echo "  arm64 dmg:    ${DMG_ARM64_SHA:0:20}..."
[ -n "$DMG_X64_SHA"   ] && echo "  x64 dmg:      ${DMG_X64_SHA:0:20}..."
[ -n "$ZIP_ARM64_SHA" ] && echo "  arm64 zip:    ${ZIP_ARM64_SHA:0:20}..."
[ -n "$ZIP_X64_SHA"   ] && echo "  x64 zip:      ${ZIP_X64_SHA:0:20}..."
[ -n "$EXE_WIN_SHA"   ] && echo "  windows exe:  ${EXE_WIN_SHA:0:20}..."
[ -n "$APPIMAGE_SHA"  ] && echo "  linux image:  ${APPIMAGE_SHA:0:20}..."
echo ""

# ── Pull CHANGELOG entry ─────────────────────────────────────────────────
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
CHANGELOG_TEXT=""
if [ -f "$CHANGELOG_FILE" ]; then
  CHANGELOG_RAW=$(awk "/^## \\[?${VERSION}\\]?/,/^## \\[?[0-9]/" "$CHANGELOG_FILE" \
    | sed "/^## \\[?[0-9]/d" \
    | head -50)
  if [ -n "$CHANGELOG_RAW" ]; then
    CHANGELOG_TEXT=$(echo "$CHANGELOG_RAW" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//' | head -c 500)
  fi
fi
if [ -z "$CHANGELOG_TEXT" ]; then
  CHANGELOG_TEXT="See aipointer.app for full release notes."
fi
CHANGELOG_JSON=$(printf '%s' "$CHANGELOG_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')

# ── Step 5: Write metadata ───────────────────────────────────────────────
echo "--- Step 5/5: Write metadata ---"

# Verify we have at least one successful build
if [ -z "$DMG_ARM64_SHA" ] && [ -z "$DMG_X64_SHA" ] && [ -z "$EXE_WIN_SHA" ] && [ -z "$APPIMAGE_SHA" ]; then
  echo "FATAL: no platform produced a usable artifact. Aborting metadata write."
  exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$META_ROOT_DIR" "$META_UPDATES_DIR"

# latest.json - custom auto-updater format
{
  echo "{"
  echo "  \"version\": \"${VERSION}\","
  echo "  \"date\": \"${TODAY_SHORT}\","
  echo "  \"releaseDate\": \"${TODAY_FULL}\","
  echo "  \"changelog\": \"${CHANGELOG_JSON}\","
  blocks=()
  if [ -n "$EXE_WIN_SHA" ]; then
    blocks+=("  \"windows\": {\n    \"url\": \"${UPDATES_URL_BASE}/$(basename "$EXE_WIN")\",\n    \"sha512\": \"${EXE_WIN_SHA}\",\n    \"size\": ${EXE_WIN_SIZE}\n  }")
  fi
  if [ -n "$DMG_ARM64_SHA" ]; then
    blocks+=("  \"mac_arm64\": {\n    \"url\": \"${UPDATES_URL_BASE}/$(basename "$DMG_ARM64")\",\n    \"sha512\": \"${DMG_ARM64_SHA}\",\n    \"size\": ${DMG_ARM64_SIZE}\n  }")
  fi
  if [ -n "$DMG_X64_SHA" ]; then
    blocks+=("  \"mac_intel\": {\n    \"url\": \"${UPDATES_URL_BASE}/$(basename "$DMG_X64")\",\n    \"sha512\": \"${DMG_X64_SHA}\",\n    \"size\": ${DMG_X64_SIZE}\n  }")
  fi
  if [ -n "$APPIMAGE_SHA" ]; then
    blocks+=("  \"linux\": {\n    \"url\": \"${UPDATES_URL_BASE}/$(basename "$APPIMAGE")\",\n    \"sha512\": \"${APPIMAGE_SHA}\",\n    \"size\": ${APPIMAGE_SIZE}\n  }")
  fi
  IFS=$'\n'
  total=${#blocks[@]}
  for i in "${!blocks[@]}"; do
    if [ $((i + 1)) -lt "$total" ]; then
      printf "%b,\n" "${blocks[$i]}"
    else
      printf "%b\n"  "${blocks[$i]}"
    fi
  done
  echo "}"
} > "$META_ROOT_DIR/latest.json"

if ! python3 -m json.tool "$META_ROOT_DIR/latest.json" > /dev/null 2>&1; then
  echo "FATAL: generated latest.json is not valid JSON."
  cat "$META_ROOT_DIR/latest.json"
  exit 1
fi
echo "  wrote latest.json"

# electron-builder style yml files (for potential future updater migration)
if [ -n "$DMG_ARM64_SHA" ] || [ -n "$DMG_X64_SHA" ]; then
  {
    echo "version: ${VERSION}"
    echo "files:"
    if [ -n "$ZIP_ARM64_SHA" ]; then
      echo "  - url: $(basename "$ZIP_ARM64")"
      echo "    sha512: ${ZIP_ARM64_SHA}"
      echo "    size: ${ZIP_ARM64_SIZE}"
    fi
    if [ -n "$DMG_ARM64_SHA" ]; then
      echo "  - url: $(basename "$DMG_ARM64")"
      echo "    sha512: ${DMG_ARM64_SHA}"
      echo "    size: ${DMG_ARM64_SIZE}"
    fi
    if [ -n "$ZIP_X64_SHA" ]; then
      echo "  - url: $(basename "$ZIP_X64")"
      echo "    sha512: ${ZIP_X64_SHA}"
      echo "    size: ${ZIP_X64_SIZE}"
    fi
    if [ -n "$DMG_X64_SHA" ]; then
      echo "  - url: $(basename "$DMG_X64")"
      echo "    sha512: ${DMG_X64_SHA}"
      echo "    size: ${DMG_X64_SIZE}"
    fi
    if [ -n "$ZIP_ARM64_SHA" ]; then
      primary_url=$(basename "$ZIP_ARM64")
      primary_sha="$ZIP_ARM64_SHA"
    elif [ -n "$DMG_ARM64_SHA" ]; then
      primary_url=$(basename "$DMG_ARM64")
      primary_sha="$DMG_ARM64_SHA"
    elif [ -n "$DMG_X64_SHA" ]; then
      primary_url=$(basename "$DMG_X64")
      primary_sha="$DMG_X64_SHA"
    fi
    echo "path: ${primary_url}"
    echo "sha512: ${primary_sha}"
    echo "releaseDate: '${TODAY_FULL}'"
  } > "$META_ROOT_DIR/latest-mac.yml"
  echo "  wrote latest-mac.yml"
fi

if [ -n "$EXE_WIN_SHA" ]; then
  cat > "$META_ROOT_DIR/latest.yml" <<EOF
version: ${VERSION}
files:
  - url: $(basename "$EXE_WIN")
    sha512: ${EXE_WIN_SHA}
    size: ${EXE_WIN_SIZE}
path: $(basename "$EXE_WIN")
sha512: ${EXE_WIN_SHA}
releaseDate: '${TODAY_FULL}'
EOF
  echo "  wrote latest.yml"
fi

if [ -n "$APPIMAGE_SHA" ]; then
  cat > "$META_ROOT_DIR/latest-linux.yml" <<EOF
version: ${VERSION}
files:
  - url: $(basename "$APPIMAGE")
    sha512: ${APPIMAGE_SHA}
    size: ${APPIMAGE_SIZE}
path: $(basename "$APPIMAGE")
sha512: ${APPIMAGE_SHA}
releaseDate: '${TODAY_FULL}'
EOF
  echo "  wrote latest-linux.yml"
fi

# Duplicate to metadata-updates/ for serving at /updates/ subpath
cp "$META_ROOT_DIR"/*.json "$META_UPDATES_DIR/" 2>/dev/null || true
cp "$META_ROOT_DIR"/*.yml  "$META_UPDATES_DIR/" 2>/dev/null || true

# ── Upload checklist ─────────────────────────────────────────────────────
{
  echo "============================================"
  echo "AIPointer v${VERSION} upload checklist"
  echo "Built: ${TODAY_FULL}"
  echo "============================================"
  echo ""
  echo "STEP 1 - Upload binaries from release/ to aipointer.app/updates/"
  ls -1 "$DIST_DIR" 2>/dev/null | grep -E '^AIPointer.*\.(dmg|zip|exe|AppImage|blockmap)$' | sed 's/^/  [ ] /'
  echo ""
  echo "STEP 2 - Upload metadata-root/ contents to aipointer.app site root"
  ls -1 "$META_ROOT_DIR" | sed 's/^/  [ ] /'
  echo ""
  echo "STEP 3 - Upload metadata-updates/ contents to aipointer.app/updates/"
  ls -1 "$META_UPDATES_DIR" | sed 's/^/  [ ] /'
  echo ""
  echo "STEP 4 - Verify after upload"
  echo "  curl -s ${UPDATES_URL_BASE}/latest.json | python3 -m json.tool | head -10"
  echo "  # expect: \"version\": \"${VERSION}\""
  if [ -n "$DMG_ARM64_SHA" ]; then
    echo ""
    echo "  curl -sL ${UPDATES_URL_BASE}/$(basename "$DMG_ARM64") | shasum -a 512 | awk '{print \$1}'"
    echo "  # expect: ${DMG_ARM64_SHA}"
  fi
  if [ -n "$EXE_WIN_SHA" ]; then
    echo ""
    echo "  curl -sL ${UPDATES_URL_BASE}/$(basename "$EXE_WIN") | shasum -a 512 | awk '{print \$1}'"
    echo "  # expect: ${EXE_WIN_SHA}"
  fi
  if [ -n "$APPIMAGE_SHA" ]; then
    echo ""
    echo "  curl -sL ${UPDATES_URL_BASE}/$(basename "$APPIMAGE") | shasum -a 512 | awk '{print \$1}'"
    echo "  # expect: ${APPIMAGE_SHA}"
  fi
  echo ""
  echo "STEP 5 - Cache headers on the server"
  echo "  Set Cache-Control: no-cache, must-revalidate for latest.json + latest*.yml"
  echo "  Set Cache-Control: public, max-age=31536000 for *.dmg, *.exe, *.AppImage, *.zip, *.blockmap"
} > "$RELEASE_DIR/UPLOAD-CHECKLIST.txt"

# ── Final report ─────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  AIPointer v${VERSION} build report"
echo "=============================================="
echo ""

status_label() {
  case "$1" in
    0) echo "skipped" ;;
    1) echo "OK" ;;
    2) echo "FAILED" ;;
  esac
}

printf "  macOS:    %s\n" "$(status_label $STATUS_MAC)"
printf "  Windows:  %s\n" "$(status_label $STATUS_WIN)"
printf "  Linux:    %s\n" "$(status_label $STATUS_LINUX)"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Errors:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  echo ""
fi

echo "Artifacts written:"
ls -1 "$DIST_DIR" 2>/dev/null | grep -E '^AIPointer.*\.(dmg|zip|exe|AppImage)$' | sed 's/^/  /'
echo ""
echo "Metadata written:"
ls -1 "$META_ROOT_DIR" 2>/dev/null | sed 's/^/  /'
echo ""
echo "Paths:"
echo "  Binaries:       $DIST_DIR/"
echo "  Metadata-root:  $META_ROOT_DIR/"
echo "  Metadata-/upd:  $META_UPDATES_DIR/"
echo "  Checklist:      $RELEASE_DIR/UPLOAD-CHECKLIST.txt"
echo ""
echo "Next steps:"
echo "  open $RELEASE_DIR"
echo "  cat $META_ROOT_DIR/latest.json"
echo "  cat $RELEASE_DIR/UPLOAD-CHECKLIST.txt"
echo ""

# Exit code: 0 if at least one platform succeeded, 1 if all failed
if [ "$STATUS_MAC" != "1" ] && [ "$STATUS_WIN" != "1" ] && [ "$STATUS_LINUX" != "1" ]; then
  echo "All requested platforms failed."
  exit 1
fi

exit 0
