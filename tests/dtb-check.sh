#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Offline test, takes an existing stock P212 DTB; never touches /boot.
set -euo pipefail
[[ $# == 1 ]] || { echo "Usage: $0 STOCK-P212.dtb" >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
bash "$root/scripts/build-dtb.sh" "$1" "$tmp/new.dtb"
bank=/soc/bus@c8834000/pinctrl@4b0/bank@4b0
[[ $(fdtget -t u "$tmp/new.dtb" "$bank/wifi_pwr_hold" gpios) == '76 0' ]]
fdtget -p "$tmp/new.dtb" "$bank/wifi_pwr_hold" | grep -qx output-high
fdtget -p "$tmp/new.dtb" "$bank/wifi_pwr_hold" | grep -qx gpio-hog
if bash "$root/scripts/build-dtb.sh" "$1" "$tmp/new.dtb"; then
    echo 'FAIL: existing output overwritten' >&2; exit 1
fi
if bash "$root/scripts/build-dtb.sh" "$tmp/new.dtb" "$tmp/twice.dtb"; then
    echo 'FAIL: duplicate application accepted' >&2; exit 1
fi
cp "$tmp/new.dtb" "$tmp/removed.dtb"
fdtput -r "$tmp/removed.dtb" "$bank/wifi_pwr_hold"
dtc -s -I dtb -O dts "$1" -o "$tmp/base.dts"
dtc -s -I dtb -O dts "$tmp/removed.dtb" -o "$tmp/removed.dts"
cmp "$tmp/base.dts" "$tmp/removed.dts"
echo 'PASS: only the intended GPIO hog added; overwrites and duplicate application refused'
