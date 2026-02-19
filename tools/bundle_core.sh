#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_ROOT="$ROOT_DIR/assets/bundled/macos/arm64"
DEST_BIN_DIR="$DEST_ROOT/bin"
DEST_SHARE_DIR="$DEST_ROOT/share/proxmark3"

INPUT_PATH="${1:-}"
PM3_SCRIPT=""
PROXMARK_BIN=""
SHARE_DIR=""

if [[ -n "$INPUT_PATH" && -d "$INPUT_PATH" ]]; then
  if [[ -x "$INPUT_PATH/bin/pm3" ]]; then
    PM3_SCRIPT="$INPUT_PATH/bin/pm3"
  elif [[ -x "$INPUT_PATH/pm3" ]]; then
    PM3_SCRIPT="$INPUT_PATH/pm3"
  fi
elif [[ -n "$INPUT_PATH" && -f "$INPUT_PATH" ]]; then
  PM3_SCRIPT="$INPUT_PATH"
fi

if [[ -z "$PM3_SCRIPT" ]] && command -v pm3 >/dev/null 2>&1; then
  PM3_SCRIPT="$(command -v pm3)"
fi

if [[ -z "$PM3_SCRIPT" || ! -f "$PM3_SCRIPT" ]]; then
  cat <<EOF
Usage:
  $0 /path/to/pm3
  $0 /path/to/proxmark/install/prefix

This script bundles a complete core layout:
  - bin/pm3
  - bin/proxmark3 (if found)
  - share/proxmark3 (if found)
EOF
  exit 1
fi

SRC_BIN_DIR="$(cd "$(dirname "$PM3_SCRIPT")" && pwd)"

for candidate in \
  "$SRC_BIN_DIR/proxmark3" \
  "$SRC_BIN_DIR/../bin/proxmark3"
do
  if [[ -x "$candidate" ]]; then
    PROXMARK_BIN="$candidate"
    break
  fi
done

if [[ -z "$PROXMARK_BIN" ]] && command -v proxmark3 >/dev/null 2>&1; then
  PROXMARK_BIN="$(command -v proxmark3)"
fi

for candidate in \
  "$SRC_BIN_DIR/../share/proxmark3" \
  "/opt/homebrew/opt/proxmark3/share/proxmark3" \
  "/usr/local/opt/proxmark3/share/proxmark3"
do
  if [[ -d "$candidate" ]]; then
    SHARE_DIR="$candidate"
    break
  fi
done

rm -rf "$DEST_ROOT"
mkdir -p "$DEST_BIN_DIR"
cp "$PM3_SCRIPT" "$DEST_BIN_DIR/pm3"
chmod +x "$DEST_BIN_DIR/pm3"

if [[ -n "$PROXMARK_BIN" && -f "$PROXMARK_BIN" ]]; then
  cp "$PROXMARK_BIN" "$DEST_BIN_DIR/proxmark3"
  chmod +x "$DEST_BIN_DIR/proxmark3"
fi

if [[ -n "$SHARE_DIR" && -d "$SHARE_DIR" ]]; then
  mkdir -p "$DEST_ROOT/share"
  if command -v ditto >/dev/null 2>&1; then
    ditto "$SHARE_DIR" "$DEST_SHARE_DIR"
  else
    cp -R "$SHARE_DIR" "$DEST_SHARE_DIR"
  fi
fi

echo "Bundled core written to: $DEST_ROOT"
echo "  pm3 script : $DEST_BIN_DIR/pm3"
if [[ -f "$DEST_BIN_DIR/proxmark3" ]]; then
  echo "  proxmark3  : $DEST_BIN_DIR/proxmark3"
fi
if [[ -d "$DEST_SHARE_DIR" ]]; then
  echo "  share data : $DEST_SHARE_DIR"
fi
