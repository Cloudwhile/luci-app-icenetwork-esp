#!/usr/bin/env sh
set -eu

if [ "${1-}" = "" ]; then
  echo "Usage: $0 <openwrt-root>"
  exit 1
fi

OPENWRT_ROOT="$1"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET_PATH="$OPENWRT_ROOT/package/luci-app-icenetwork-esp"

if [ ! -d "$OPENWRT_ROOT" ]; then
  echo "OpenWrt root does not exist: $OPENWRT_ROOT"
  exit 1
fi

if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
  rm -rf "$TARGET_PATH"
fi

ln -s "$REPO_ROOT" "$TARGET_PATH"
echo "Linked package to: $TARGET_PATH"
