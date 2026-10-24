# B860AV2.1 WiFi：RTL8189FTV / 8189fs 驱动源码与板级供电适配

本仓库面向中兴 B860AV2.1（Amlogic GXL / S905L 类平台）板载 RTL8189FTV SDIO 无线网卡，提供可直接编译的完整主机侧驱动源码、可移植的构建入口、离线设备树叠加与无硬件检查脚本。使用者从本仓库取得源码，按自己机器的内核自行构建并安装。

- 芯片：SDIO `024c:f179`，RTL8189FTV；802.11b/g/n、2.4 GHz、1T1R、SDIO 接口（[Realtek 官方参数](https://www.realtek.com/Product/Index?id=600&cate_id=194)）。
- 驱动版本：`v5.11.6.0-2-gb9aa73b62.20211117`。
- 参考环境：Armbian noble、aarch64、`6.12.37-ophub`、GCC 14、P212 基础设备树。
- 配套项目：[b860av21-ir](https://github.com/YsLtr/b860av21-ir) 提供红外遥控 keymap，基于内核自带的 meson-ir。

## 一、来源

本仓库是 OpenIPC `realtek-wlan` 的下游分支，保留上游 Git 历史、原始版权头和各文件原有许可。

| 项目 | 内容 |
|---|---|
| 上游仓库 | [OpenIPC/realtek-wlan](https://github.com/OpenIPC/realtek-wlan)，分支 `rtl8189fs` |
| 基线提交 | `f0a677fd13944f5f6a8d256c29a46b301084121e` |
| 驱动版本 | Realtek RTL8189FS `v5.11.6.0`，见 [rtw_version.h](include/rtw_version.h) |

发布前把参考机部署的源码与基线提交跟踪的 **573 个文件**逐一做 SHA-256 比对，其中 3 个文件存在差异，全部已整合进本仓库源码：

| 文件 | 差异 |
|---|---|
| [Makefile](Makefile) | 关闭 `CONFIG_BR_EXT` 与 RK3188，启用 AML S905，省略 bridge-extension 对象 |
| [os_intfs.c](os_dep/linux/os_intfs.c) | 4 处 `net_device.dev_addr` 直写改为 `eth_hw_addr_set` |
| [ioctl_cfg80211.c](os_dep/linux/ioctl_cfg80211.c) | `change_beacon` 接收 `cfg80211_ap_update` 并读取其 `beacon` 成员 |

这些差异以源码内版本条件的方式一次性整合进源码，构建过程保持干净：`change_beacon` 以 Linux **6.7** 为分界；MAC 地址写入统一走 [rtw_compat.h](include/rtw_compat.h) 的共享 helper（Linux **5.15+** 用 `eth_hw_addr_set`），7 处直写全部经由它完成；`rtw_compat.h` 另提供 Linux 6.8+ 所需的 `strlcpy` 实现，保留完整返回值语义（截断与零长度同样返回源串长度）。新增的兼容、构建、检查代码标记 `GPL-2.0-only`，完整说明见 [UPSTREAM.md](UPSTREAM.md)。

## 二、内容

| 路径 | 作用 |
|---|---|
| `core/`、`hal/`、`os_dep/`、`include/`、`platform/` | 完整上游主机侧驱动源码；[hal8188f_fw.c](hal/rtl8188f/hal8188f_fw.c) 中的固件字节数组按原样保留原有 Realtek 版权与 GPLv2 头 |
| [Makefile](Makefile)、[Kconfig](Kconfig) | 厂商构建描述与配置入口；[Makefile.full](Makefile.full) / [Makefile.mini](Makefile.mini) 是上游附带的两种功能开关组合（MP 测试、EFUSE 配置文件、PHY 参数文件、proc 调试），供对照参考 |
| [build.sh](scripts/build.sh) | 外部模块 Kbuild 构建入口，支持 `KERNEL_SRC`、`CC`、`ARCH`、`CROSS_COMPILE`、`JOBS`，可在任意目录调用，只要求对检出目录有写权限 |
| [b860av21-wifi-power.dts](dts/b860av21-wifi-power.dts) | 设备树叠加源码，仅新增一个 `output-high` 的 GPIO hog |
| [build-dtb.sh](scripts/build-dtb.sh) | 用 dtc / fdtget / fdtoverlay 把叠加离线合并进 P212 基础 DTB |
| [driver-check.py](tests/driver-check.py) | 版本边界、`strlcpy` 返回值语义、构建参数转发与校验、源码 guard 的检查，需要主机 C 编译器 |
| [dtb-check.sh](tests/dtb-check.sh) | 设备树叠加的隔离检查：属性正确、保留既有输出文件、删除新节点后与基础树一致 |
| [VALIDATION.md](docs/VALIDATION.md)、[UPSTREAM.md](UPSTREAM.md)、[COPYING](COPYING) | 实机验证记录、来源与改动说明、GPLv2 全文 |

## 三、作用

驱动链路分两个相互独立的层面：

1. **设备树让芯片上电并被 SDIO 总线枚举。** 该板使能脚为 **GPIODV_27（控制器内偏移 76）**，由 [b860av21-wifi-power.dts](dts/b860av21-wifi-power.dts) 里的 gpio-hog 常高输出维持。叠加只增加这一个节点，SDIO 时钟、引脚复用与其他外设配置保持原样。
2. **8189fs 驱动负责已枚举芯片的无线功能。** 提供扫描、STA 连接、数据收发，以及断开/重载驱动与重启后的自动恢复。

同理，供电与枚举由设备树负责，无线协议栈由模块负责；两者可以分别完成、分别回滚。

## 四、使用方式

### 1. 确认 SDIO 枚举

```bash
for d in /sys/bus/sdio/devices/*; do
    [ -f "$d/vendor" ] || continue
    printf '%s: ' "$d"
    cat "$d/vendor" "$d/device"
done
```

读出 `0x024c` 与 `0xf179`，即表示芯片已被总线发现。芯片已枚举时直接进入编译与安装，设备树保持现状。

### 2. 从源码编译（普通用户）

```bash
git clone https://github.com/YsLtr/b860av21-wifi.git
cd b860av21-wifi
# 安装与目标内核完全匹配的 headers、make、bc 和编译器。
# ophub 的 headers 通常来自对应内核发行方的包。
# 参考环境使用 GCC 14（该内核所需的 -fmin-function-alignment=4 由 GCC 14 提供）。
CC=gcc-14 bash scripts/build.sh
modinfo ./8189fs.ko
```

指定目标 headers 与工具链：

```bash
KERNEL_SRC=/path/to/matching/kernel/build ARCH=arm64 \
CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc \
JOBS=4 bash scripts/build.sh
```

`build.sh` 以 `CONFIG_RTL8189FS=m`、`CONFIG_RTL8188F=y`、`CONFIG_SDIO_HCI=y`、`CONFIG_PLATFORM_AML_S905=y`、`CONFIG_BR_EXT=n` 直接调用外部模块 Kbuild，只执行构建步骤，安装与启用交由使用者按后文手工确认。交叉编译入口已提供，验证范围以参考组合（aarch64、GCC 14、`6.12.37-ophub`）为准。

### 3. 需要板级供电时构建设备树

叠加只增加经过实机验证的 GPIO hog。执行合并前准备好可启动的救援 SD 卡或串口：

```bash
sudo apt install device-tree-compiler
bash scripts/build-dtb.sh \
  /boot/dtb/amlogic/meson-gxl-s905x-p212.dtb \
  ./meson-gxl-s905x-p212-b860av21-wifi.dtb
```

脚本要求基础树为参考 P212 模型与 Amlogic GXL 外设 pinctrl 控制器；输出文件已存在时保留原文件；基础树已有同名 hog 时提示改用未修改的 DTB。生成结果与参考机在用的 WiFi DTB 经 `dtc -s -I dtb -O dts` 规范化后文本完全一致。

确认结果后人工安装并切换：

```bash
sudo install -m 0644 ./meson-gxl-s905x-p212-b860av21-wifi.dtb /boot/dtb/amlogic/
sudo cp -an /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.before-b860av21
sudoedit /boot/extlinux/extlinux.conf
```

把当前使用条目中的 `fdt` 行改为：

```text
fdt /dtb/amlogic/meson-gxl-s905x-p212-b860av21-wifi.dtb
```

其他条目与启动参数保持原样，并保留一个原 DTB 的救援启动条目。部分系统从 `uEnv.txt` 读取启动配置，按本机实际启动路径修改。

### 4. 安装模块

先比较模块与运行内核是否一致：

```bash
modinfo -F vermagic ./8189fs.ko
uname -r
# 查看现有模块实际位置（已安装时输出其完整路径）
modinfo -n 8189fs
find /lib/modules/"$(uname -r)" -type f -name '*8189fs.ko*'
```

首次安装场景（系统中还没有 8189fs 模块）按下面的路径安装：

```bash
sudo install -D -m 0644 ./8189fs.ko \
  /lib/modules/"$(uname -r)"/kernel/drivers/net/wireless/realtek/8189fs/8189fs.ko
sudo depmod -a
sudo modprobe 8189fs
```

驱动按 SDIO alias 自动加载；需要开机自动加载时，在 `/etc/modules-load.d/8189fs.conf` 写入单独一行 `8189fs`。已有模块已加载时，`modprobe` 沿用内存中的旧模块；在维护窗口内用有线或串口连接，现有模块执行 `modprobe -r 8189fs` 后再加载新模块，或按计划重启生效。若系统已装其他版本的 8189fs 模块，先把它备份到 `/lib/modules` 之外并记录完整原路径，让同名模块只保留一份。

### 5. 连接与验证

```bash
lsmod | grep 8189fs
modinfo -F version 8189fs
ip -br link
iw dev
nmcli device wifi list
# 交互输入密码，凭据只存在于本机
nmcli --ask device wifi connect 'YOUR_2G_SSID' ifname wlan0
iw dev wlan0 link
ip -4 addr show wlan0
# 指定无线接口，让测试流量确实经过无线
ping -I wlan0 -c 5 YOUR_GATEWAY_IP
journalctl -k -b | grep -Ei '8189|mmc|sdio|warning|error'
```

接口名按 `iw dev` / `nmcli` 的实际输出替换 `wlan0`。参考机同时出现 wlan0 与 wlan1 两个接口（同一张物理网卡），以实际可连接 STA 接口为准。有线与无线同网段时同时考虑路由 metric / 回包路径，`ping -I 无线接口` 的结果才反映无线数据通路。

重启后复查 SDIO ID、驱动版本、无线自动连接与内核警告。更换驱动前后使用相同的 AP、频段与测试方法。

### 6. 回滚

- **设备树**：恢复备份的 extlinux 配置或选择原 DTB 启动条目；需要恢复启动时用救援 SD 卡挂载启动分区恢复，确认恢复生效后再清理新增 DTB。
- **模块升级**：经有线/串口进入维护窗口，卸载新模块，按原路径放回备份模块，`depmod -a` 后重新加载。
- **首次安装撤销**：卸载 8189fs，清理本次新增的模块文件与自动加载配置，再执行 `depmod -a`。
- 设备树修改与模块安装是两步独立变更，排障时分别回滚。

## 五、边界、限制与禁止事项

本项目的适用范围与操作约束集中在本节。

### 硬件与能力边界

- 芯片规格为 2.4 GHz 802.11b/g/n，5 GHz 属于该硬件之外的能力，更换驱动无法获得。
- 本项目面向 B860AV2.1 + 板载 RTL8189FTV 的组合；其他 B860、B860H、CM211、HG680 型号的硬件与此不同，按自身板卡另行确认。
- 已实机验证：SDIO 枚举、模块加载、2.4 GHz 扫描与 STA 连接、网络传输、断开/重载驱动及多次重启后自动恢复。
- AP、P2P、休眠唤醒与长期压力测试未列为已验证能力；其他内核、板卡与交叉编译器组合按自行编译适配处理，验证记录见 [VALIDATION.md](docs/VALIDATION.md)。
- 板级供电采用已验证的常高 gpio-hog 方案，未实现电源时序管理或省电关断；后续要支持 runtime PM / suspend 时改用板级 regulator / mmc-pwrseq，并重新做硬件时序验证。
- 源码中多数 Realtek 头文件声明 GPLv2；导入的 crypto 文件保留各自的 BSD / public-domain 声明；固件字节数组保留原 Realtek 版权，本项目提供的是上游主机侧驱动源码，固件字节数组对应的生成源码不在本仓库范围内。

### 操作禁止项

- 不要盲扫 GPIO 寻找使能脚：其他引脚控制存储、电源或复位。实机曾显示的 `gpio-599` 是当次启动的 Linux 全局 GPIO 编号，不作为跨内核固定值。
- 不要假定设备名固定为 `mmc0:0001:1`；按当次 `/sys/bus/sdio/devices/*` 输出取实际名称。
- 芯片已枚举时不要改动设备树。
- 不要用 x86 headers 构建 ARM64 模块，也不要跨内核复制 `.ko` 或使用 `--force-vermagic`：内核内部驱动 API 不稳定，内核升级后按新内核重新编译。保留上游版权声明并遵守 GPLv2 及各文件许可。
- 不要把本叠加套用到其他盒子的整机 DTB 上；原设备树若已用偏移 76 的 regulator/hog，重复占用会冲突。整机 DTB 请按自己的板卡生成。
- 不要把主机专属的 root UUID、IP、MAC 等复制给他人。
- 已有可用模块时，先备份到 `/lib/modules` 之外的目录并记录完整原路径；不要让 depmod 在同名模块之间挑选。
- 不要通过正在使用的 WiFi 连接卸载驱动；在维护窗口内经有线或串口操作。
- 首次安装撤销时只清理本次新增的文件，其他驱动保持原样。
- 凭据只在本机交互输入，不要写入命令行、仓库或日志；报告问题时去掉密码、WiFi PSK、SSH 凭据、整份私人日志与未授权 ROM 镜像。
- 不要用缩短 systemd 超时或强制重启掩盖驱动/服务故障；默认系统服务或日志配置的问题归因到各自组件，安装本驱动时 journald、watchdog 与关机超时保持原配置。

### 验证与记录边界

- “可编译”指代码能针对匹配 headers 构建，`vermagic`、架构、内核配置与符号版本仍按目标内核核对。
- 本次发布的构建保留上游警告；缺少 `vmlinux` 时 BTF 生成跳过，属已知的非零警告构建。
- 构建通过、静态检查通过不等同于新模块已在目标机上替换并通过运行测试；发布过程替换模块的操作由每个使用者自行执行与记录。
- 普通 `ping 网关` 成功可能经过有线路径，无线数据通路以 `ping -I <无线接口>` 为准。
- 编译成功代表构建链路可用，性能结论来自更换驱动前后相同 AP、频段与方法下的对比。

## 六、报告问题

附板卡型号/PCB 照片、`uname -r`、SDIO ID、实际 DTB、编译器版本、构建命令及去敏后的内核错误。