#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARBALL="${1:-/mnt/data/zig-x86_64-linux-0.17.0-dev.87+9b177a7d2.tar.xz}"
BUILD_DIR="$ROOT_DIR/.zig-local"
TARGET="${SBAN_TARGET:-x86_64-linux-gnu}"
REQUESTED_MODE="${SBAN_BUILD_MODE:-auto}"
if [ ! -f "$TARBALL" ]; then
  echo "missing zig tarball: $TARBALL" >&2
  exit 1
fi
mkdir -p "$BUILD_DIR"
if ! find "$BUILD_DIR" -type f -name zig | grep -q .; then
  tar -xf "$TARBALL" -C "$BUILD_DIR"
fi
ZIG_BIN="$(find "$BUILD_DIR" -type f -name zig | head -n 1)"
if [ -z "$ZIG_BIN" ]; then
  echo "failed to locate zig binary after extracting $TARBALL" >&2
  exit 1
fi
cd "$ROOT_DIR"
try_build() {
  local optimize="$1"
  rm -rf zig-out
  "$ZIG_BIN" build -Dtarget="$TARGET" -Doptimize="$optimize" >/tmp/sban_build.log 2>&1 || return 1
  [ -x "$ROOT_DIR/zig-out/bin/zig_sban" ] || return 1
  "$ROOT_DIR/zig-out/bin/zig_sban" inspect >/tmp/sban_build_smoke.log 2>&1 || return 1
}
select_mode() {
  if [ "$REQUESTED_MODE" != "auto" ]; then
    printf '%s\n' "$REQUESTED_MODE"
    return 0
  fi
  for mode in ReleaseSafe ReleaseSmall Debug; do
    if try_build "$mode"; then
      printf '%s\n' "$mode"
      return 0
    fi
  done
  return 1
}
MODE="$(select_mode)"
if [ "$REQUESTED_MODE" != "auto" ]; then
  try_build "$MODE"
fi
echo "using_zig=$ZIG_BIN"
echo "target=$TARGET"
echo "optimize=$MODE"
echo "stable_bin=$ROOT_DIR/zig-out/bin/zig_sban"
