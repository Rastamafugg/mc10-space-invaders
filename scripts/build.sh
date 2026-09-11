#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${MC10_BUILD_DIR:-$ROOT/build}"
SOURCE="$ROOT/src/main.s"
LOCAL_ASSEMBLER="$ROOT/.tools/crasm/usr/bin/crasm"
if [[ -n "${MC10_ASM:-}" ]]; then
    ASSEMBLER="$MC10_ASM"
elif command -v crasm >/dev/null 2>&1; then
    ASSEMBLER="crasm"
else
    ASSEMBLER="$LOCAL_ASSEMBLER"
fi
HEX="$BUILD_DIR/space-invaders.hex"
BIN="$BUILD_DIR/space-invaders.bin"
LISTING="$BUILD_DIR/space-invaders.lst"
MAP="$BUILD_DIR/space-invaders.map"
CASSETTE="$BUILD_DIR/space-invaders.c10"

usage() {
    printf '%s\n' "Usage: scripts/build.sh {build|check|clean}"
}

check_tools() {
    if [[ "$ASSEMBLER" == */* ]]; then
        test -x "$ASSEMBLER" || {
            printf 'build: assembler is not executable: %s\n' "$ASSEMBLER" >&2
            return 1
        }
    else
        command -v "$ASSEMBLER" >/dev/null 2>&1 || {
            printf 'build: assembler was not found in PATH: %s\n' "$ASSEMBLER" >&2
            return 1
        }
    fi
    command -v python3 >/dev/null 2>&1 || {
        printf '%s\n' 'build: python3 was not found in PATH' >&2
        return 1
    }
    test -f "$SOURCE" || {
        printf 'build: source is missing: %s\n' "$SOURCE" >&2
        return 1
    }
}

build() {
    check_tools
    mkdir -p "$BUILD_DIR"
    "$ASSEMBLER" -s -o "$HEX" "$SOURCE" > "$LISTING"
    python3 "$ROOT/scripts/hex_to_raw.py" \
        --input "$HEX" \
        --output "$BIN" \
        --map "$MAP"
    python3 "$ROOT/scripts/make_c10.py" \
        --input "$BIN" \
        --output "$CASSETTE" \
        --name SPACEINV \
        --load-address 0x5000 \
        --exec-address 0x5000
    printf 'build: wrote %s\n' "$BIN"
    python3 "$ROOT/scripts/verify_c10.py" "$CASSETTE"
    printf 'build: wrote %s\n' "$CASSETTE"
}

check() {
    check_tools
    printf 'build: prerequisites pass (%s)\n' "$ASSEMBLER"
}

clean() {
    if test -d "$BUILD_DIR"; then
        find "$BUILD_DIR" -type f -delete
        rmdir "$BUILD_DIR" 2>/dev/null || true
    fi
    printf '%s\n' 'build: generated artifacts removed'
}

case "${1:-build}" in
    build) build ;;
    check) check ;;
    clean) clean ;;
    *) usage >&2; exit 2 ;;
esac
