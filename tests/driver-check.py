#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run on Linux with Python 3, a C compiler and /bin/sh; no kernel headers needed."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="b860-driver-check-") as directory:
    tmp = Path(directory)
    linux = tmp / "linux"
    linux.mkdir()
    (linux / "version.h").write_text("#define KERNEL_VERSION(a,b,c) (((a)<<16)+((b)<<8)+(c))\n")
    (linux / "string.h").write_text("#include <string.h>\n")
    (linux / "etherdevice.h").write_text('''#define ETH_ALEN 6
struct net_device { unsigned char dev_addr[6]; };
static int setter_calls;
static inline void eth_hw_addr_set(struct net_device *d, const void *a)
{ setter_calls++; memcpy(d->dev_addr, a, 6); }
''')
    test = tmp / "compat.c"
    test.write_text('''#include <assert.h>
#include "rtw_compat.h"
int main(void) {
    struct net_device d = {{0}};
    unsigned char mac[] = {2, 1, 2, 3, 4, 5};
    rtw_eth_hw_addr_set(&d, mac);
    assert(!memcmp(d.dev_addr, mac, 6));
    assert(setter_calls == (LINUX_VERSION_CODE >= KERNEL_VERSION(5,15,0)));
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,8,0)
    char buf[8] = "xxxxxxx";
    assert(strlcpy(buf, "hello", 0) == 5 && buf[0] == 'x');
    assert(strlcpy(buf, "hello", 1) == 5 && buf[0] == 0);
    assert(strlcpy(buf, "hello", 4) == 5 && !strcmp(buf, "hel"));
    assert(strlcpy(buf, "hello", 6) == 5 && !strcmp(buf, "hello"));
    assert(strlcpy(buf, "", sizeof(buf)) == 0 && buf[0] == 0);
#endif
    return 0;
}
''')
    for version in ((5, 14, 0), (5, 15, 0), (6, 7, 0), (6, 8, 0), (6, 12, 37)):
        code = (version[0] << 16) + (version[1] << 8) + version[2]
        executable = tmp / "compat"
        run(*shlex.split(os.environ.get("HOSTCC", "cc")), "-Wall", "-Wextra", "-Werror",
            f"-DLINUX_VERSION_CODE={code}", "-I" + str(tmp), "-I" + str(ROOT / "include"),
            str(test), "-o", str(executable))
        run(str(executable))

    # Capture the real script's argv, without compiling or installing anything.
    (tmp / "Makefile").touch()
    for name, body in {
        "make": '#!/bin/sh\nprintf "%s\\n" "$@"\n',
        "uname": '#!/bin/sh\nprintf "aarch64\\n"\n',
        "gcc-14": '#!/bin/sh\nexit 0\n',
    }.items():
        path = tmp / name
        path.write_text(body)
        path.chmod(0o755)
    env = dict(os.environ, PATH=str(tmp) + os.pathsep + os.environ["PATH"],
               KERNEL_SRC=str(tmp), JOBS="2")
    for key in ("CC", "ARCH", "CROSS_COMPILE"):
        env.pop(key, None)
    for overrides, expected, forbidden in (
        ({}, "CC=gcc-14", "CC=gcc"),
        ({"CC": "my-cc"}, "CC=my-cc", "CC=gcc-14"),
        ({"ARCH": "arm64", "CROSS_COMPILE": "aarch64-linux-gnu-"},
         "CROSS_COMPILE=aarch64-linux-gnu-", "CC=gcc-14"),
    ):
        result = subprocess.check_output(["sh", str(ROOT / "scripts/build.sh")],
                                         env=dict(env, **overrides), cwd=tmp, text=True).splitlines()
        assert expected in result and forbidden not in result, result
        assert "M=" + str(ROOT) in result and result[-1] == "modules", result
        assert "CONFIG_BR_EXT=n" in result and "-j2" in result
    for jobs in ("0", "00", "-1", "two"):
        bad = subprocess.run(["sh", str(ROOT / "scripts/build.sh")], env=dict(env, JOBS=jobs),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert bad.returncode == 2

cfg = (ROOT / "os_dep/linux/ioctl_cfg80211.c").read_text()
beacon = cfg.split("static int cfg80211_rtw_change_beacon", 1)[1].split("RTW_INFO", 1)[0]
assert beacon.count("KERNEL_VERSION(6, 7, 0)") == 2
assert "struct cfg80211_ap_update *params" in beacon and "&params->beacon" in beacon
assert "struct cfg80211_beacon_data *info)" in beacon
for path in (ROOT / "os_dep").rglob("*.c"):
    assert not re.search(r"(?:_rtw_)?memcpy\([^,;\n]*->dev_addr\s*,", path.read_text()), path
makefile = (ROOT / "Makefile").read_text()
assert "ifeq ($(CONFIG_BR_EXT), y)\nrtk_core += core/rtw_br_ext.o\nendif" in makefile
assert "-include $(src)/include/rtw_compat.h" in makefile
print("PASS: compatibility boundaries, strlcpy semantics, build argv, source guards")
