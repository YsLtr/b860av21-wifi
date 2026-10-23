#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Offline only: never writes boot configuration or overwrites an existing DTB.
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 BASE-P212.dtb NEW-OUTPUT.dtb" >&2; exit 2; }
base=$1
out=$2
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in dtc fdtget fdtoverlay; do command -v "$tool" >/dev/null; done
[[ -f $base && ! -e $out && ! -L $out ]] || { echo 'Base missing or output already exists' >&2; exit 1; }
# Refuse arbitrary board trees: this wiring is NOT universal across B860 models.
[[ $(fdtget -t s "$base" / model) == 'Amlogic Meson GXL (S905X) P212 Development Board' ]] || {
    echo 'Expected the verified P212 base tree; inspect other trees manually.' >&2; exit 1;
}
bank=/soc/bus@c8834000/pinctrl@4b0/bank@4b0
[[ $(fdtget -t s "$base" /soc/bus@c8834000/pinctrl@4b0 compatible) == amlogic,meson-gxl-periphs-pinctrl ]]
[[ $(fdtget -t u "$base" "$bank" '#gpio-cells') == 2 ]]
if fdtget -l "$base" "$bank" | grep -qx wifi_pwr_hold; then
    echo 'Power hog already present; use the unmodified base DTB.' >&2; exit 1
fi
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
dtc -@ -I dts -O dtb -o "$tmp/power.dtbo" "$root/dts/b860av21-wifi-power.dts"
fdtoverlay -i "$base" -o "$tmp/result.dtb" "$tmp/power.dtbo"
[[ $(fdtget -t u "$tmp/result.dtb" "$bank/wifi_pwr_hold" gpios) == '76 0' ]]
[[ $(fdtget -t s "$tmp/result.dtb" "$bank/wifi_pwr_hold" line-name) == wifi_pwr ]]
# noclobber also protects against a destination appearing after the first check.
(set -o noclobber; cat "$tmp/result.dtb" > "$out")
echo "Created $out. No boot files changed. Read README.md before activating."
