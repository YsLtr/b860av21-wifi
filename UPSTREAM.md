# Driver origin and local changes

## Source baseline

- Repository: <https://github.com/OpenIPC/realtek-wlan>
- Branch: `rtl8189fs`
- Baseline commit: `f0a677fd13944f5f6a8d256c29a46b301084121e`
- Driver: Realtek RTL8189FS, version `v5.11.6.0` (see [version header](include/rtw_version.h)).
- The Git history is retained; this is not a binary-only driver release.

The reference B860AV2.1's deployed source was compared by SHA-256 against
**all 573 files** tracked by the baseline commit. It has no Git metadata.
Exactly three tracked files differed; none were missing:

| File | Observed deployed change |
| --- | --- |
| [Makefile](Makefile) | Disable `CONFIG_BR_EXT` and RK3188; enable AML S905; omit the bridge-extension object |
| [os_intfs.c](os_dep/linux/os_intfs.c) | Four direct `net_device.dev_addr` writes replaced with `eth_hw_addr_set` |
| [ioctl_cfg80211.c](os_dep/linux/ioctl_cfg80211.c) | `change_beacon` takes `cfg80211_ap_update` and reads its `beacon` member |

The deployed build also force-included a separate compatibility header providing
an actual `strlcpy` implementation for Linux 6.8 and later. Its implementation
is retained in [rtw_compat.h](include/rtw_compat.h): it returns the full source
length, including when the destination is truncated or has size zero. It is
**not** an alias to `strscpy`, which has different return semantics.

## Publication adjustments

The observed delta is integrated rather than applied by a destructive patch
script on each build:

- The Makefile force-includes the repository-local compatibility header. The
  bridge-extension object is conditional on `CONFIG_BR_EXT`, not deleted from
  the source tree. It stays disabled for the reference build because the old
  extension requires removed kernel interfaces (including `net/ipx.h`).
- `change_beacon` is guarded at Linux **6.7**, keeping the previous signature
  below that boundary.
- One shared MAC-address helper uses `eth_hw_addr_set` on Linux **5.15+** and
  the historical copy below that boundary. All seven direct net-device address
  writes use it, including the three additional upstream paths in
  [osdep_service.c](os_dep/osdep_service.c),
  [ioctl_linux.c](os_dep/linux/ioctl_linux.c), and
  [mlme_linux.c](os_dep/linux/mlme_linux.c). This avoids bypassing kernel
  address tracking, not merely the compiler's const qualifier.
- [build.sh](scripts/build.sh) invokes external-module Kbuild directly, avoiding
  the vendor Makefile's hard-coded Android toolchain and copy/install targets.
  It supports `KERNEL_SRC`, `CC`, `ARCH`, `CROSS_COMPILE`, and `JOBS`, works from
  any current directory, and requires only write access to the checkout.
  Native aarch64 builds default to GCC 14; cross builds leave compiler selection
  to Kbuild unless `CC` is explicitly provided. No install or service action is
  performed. Paths with whitespace are rejected because Kbuild does not support
  them.
- [driver-check.py](tests/driver-check.py) tests the compatibility helper at
  version boundaries, truncation/zero-size semantics, build-script argument
  forwarding and validation, and source guards. Run `python3 tests/driver-check.py`
  on Linux with a host C compiler (`HOSTCC` may override `cc`).

The reference target is **Linux 6.12.37-ophub, aarch64, GCC 14.2.0**.
Version guards preserve older API branches; they are not a claim that every
older/newer kernel or every vendor build configuration has been compiled or
tested. See [validation record](docs/VALIDATION.md) for actual checks. A fresh
module build is not proof that the new module was loaded or runtime-tested.
Rebuilding requires the matching prepared kernel headers/configuration and
Module.symvers; this project does not provide a reproducible kernel toolchain
or promise bit-for-bit identical modules across different build environments.

## Licensing and retained vendor material

[COPYING](COPYING) is the unmodified standard GNU GPL version 2 text, obtained
from the reference system's `/usr/share/common-licenses/GPL-2`.
Most Realtek source headers explicitly grant **GPL version 2**, not
"version 2 or later". Original copyright and license headers remain intact;
new compatibility/build/check code is marked `GPL-2.0-only`.

Some imported crypto files carry their own BSD/public-domain notices, including
[the AES implementation](core/crypto/aes-internal.c). Those notices continue to
apply; the top-level GPL text does not replace them or relicense those files.
The embedded firmware arrays in [hal8188f_fw.c](hal/rtl8188f/hal8188f_fw.c)
are retained byte-for-byte with their existing Realtek copyright/GPLv2 header.
This repository supplies the complete upstream **host driver source**, not the
source code used to generate the vendor firmware byte arrays. No new license
claim is made for vendor payloads, and no extracted Android APKs, unrelated
firmware blobs, private credentials, compiled modules, object files, or deployed
backup files are added by this work.
