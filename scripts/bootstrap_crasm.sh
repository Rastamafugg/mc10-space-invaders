#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT/.tools"
PACKAGE_DIR="$TOOLS_DIR/crasm-package"
INSTALL_DIR="$TOOLS_DIR/crasm"

if test -x "$INSTALL_DIR/usr/bin/crasm"; then
    printf 'bootstrap: CRASM already available at %s\n' "$INSTALL_DIR/usr/bin/crasm"
    exit 0
fi

command -v apt-get >/dev/null 2>&1 || {
    printf '%s\n' 'bootstrap: apt-get is required on WSL/ Debian/Ubuntu' >&2
    exit 1
}
command -v dpkg-deb >/dev/null 2>&1 || {
    printf '%s\n' 'bootstrap: dpkg-deb is required on WSL/ Debian/Ubuntu' >&2
    exit 1
}

mkdir -p "$PACKAGE_DIR"
cd "$PACKAGE_DIR"
apt-get download crasm
PACKAGE="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name 'crasm_*.deb' -print -quit)"
test -n "$PACKAGE" || {
    printf '%s\n' 'bootstrap: apt-get did not download the crasm package' >&2
    exit 1
}
mkdir -p "$INSTALL_DIR"
dpkg-deb -x "$PACKAGE" "$INSTALL_DIR"
printf 'bootstrap: installed CRASM at %s\n' "$INSTALL_DIR/usr/bin/crasm"

