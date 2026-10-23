#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build only: run as an ordinary user in a writable checkout.
set -eu

[ "$#" -eq 0 ] || { echo 'Usage: [KERNEL_SRC=...] [CC=...] [ARCH=...] [CROSS_COMPILE=...] [JOBS=...] sh scripts/build.sh' >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kernel_src=${KERNEL_SRC:-/lib/modules/$(uname -r)/build}
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
case "$jobs" in ''|*[!0-9]*) echo 'JOBS must be a positive integer' >&2; exit 2;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be a positive integer' >&2; exit 2; }
[ -f "$kernel_src/Makefile" ] || { echo "Missing prepared kernel headers: $kernel_src" >&2; exit 2; }
# Kbuild does not support whitespace in source paths.
case "$root$kernel_src" in *[[:space:]]*) echo 'Kbuild source paths must not contain whitespace' >&2; exit 2;; esac

set -- -C "$kernel_src" "M=$root" "-j$jobs" \
    CONFIG_RTL8189FS=m CONFIG_RTL8188F=y CONFIG_SDIO_HCI=y \
    CONFIG_PLATFORM_AML_S905=y CONFIG_PLATFORM_ARM_RK3188=n CONFIG_BR_EXT=n \
    "CROSS_COMPILE=${CROSS_COMPILE:-}"
[ -z "${ARCH:-}" ] || set -- "$@" "ARCH=$ARCH"
if [ -n "${CC:-}" ]; then
    set -- "$@" "CC=$CC"
elif [ -z "${CROSS_COMPILE:-}" ] && [ -z "${ARCH:-}" -o "${ARCH:-}" = arm64 ] && [ "$(uname -m)" = aarch64 ]; then
    # The reference 6.12.37-ophub kernel needs GCC 14, not Ubuntu's default GCC 13.
    command -v gcc-14 >/dev/null 2>&1 || { echo 'Install gcc-14 or explicitly set CC to a kernel-compatible compiler' >&2; exit 2; }
    set -- "$@" CC=gcc-14
fi
exec make "$@" modules
