# B860AV2.1 WiFi：RTL8189FTV / 8189fs

面向 **中兴 B860AV2.1、Amlogic GXL / S905L 类平台、板载 RTL8189FTV SDIO** 的可编译源码与板级适配。不是所有 B860、B860H、CM211、HG680 型号的通用安装包。

本项目保留 OpenIPC `realtek-wlan` 的上游历史，针对一台实机验证了驱动与供电配置。**不需要下载 Android 固件或提取专有 Android `.ko`**；完整驱动源码已在仓库内。

- 芯片：SDIO `024c:f179`，RTL8189FTV。
- 已验证：Armbian noble / aarch64，`6.12.37-ophub`，GCC 14，P212 基础设备树。
- 驱动版本：`v5.11.6.0-2-gb9aa73b62.20211117`。
- 硬件能力：[Realtek 官方参数](https://www.realtek.com/Product/Index?id=600&cate_id=194) 为 **802.11b/g/n、2.4 GHz、1T1R、SDIO**；不能通过更换驱动获得 5 GHz。
- IR 配套项目：[b860av21-ir](https://github.com/YsLtr/b860av21-ir)。IR 使用内核已有的 meson-ir，不包含在本驱动中。

## 范围与验证状态

| 内容 | 状态 |
|---|---|
| 原参考机的 SDIO 枚举、扫描、STA 连接、传输 | 已验证 |
| 断开/重新加载驱动及重启后自动连接 | 参考机已验证 |
| 公布源码针对 6.12.37-ophub 构建 | 见 [验证记录](docs/VALIDATION.md) |
| AP、P2P、休眠唤醒、长期压力测试 | 不作为已验证能力 |
| 其他内核 / 板卡 / 交叉编译器 | 可自行编译适配，不保证开箱即用 |

“开放源码可编译”不等于内核模块可以跨版本复制。内核升级后必须按新内核重新编译；Linux 内部驱动 API 并不稳定。保留上游版权声明并遵守 GPLv2 及各文件保留的许可，详见 [COPYING](COPYING) 和 [来源说明](UPSTREAM.md)。仓库包含完整的主机侧驱动源码；上游自带的固件字节数组原样保留，不代表提供生成这些固件的源码。

## 先理解两个独立层面

1. **设备树负责让芯片上电并被 SDIO 总线发现。** 这台 B860AV2.1 的使能脚是 **GPIODV_27，控制器内偏移 76**，不是 GPIOX_6。
2. **8189fs 驱动负责已枚举芯片的无线功能。** 只安装 `.ko` 无法修复缺少供电的设备树。

实机曾显示 `gpio-599`，那是当次启动的 Linux 全局 GPIO 编号，**不能作为跨内核固定值**。不要盲扫 GPIO：其他引脚可能控制存储、电源或复位。

```bash
for d in /sys/bus/sdio/devices/*; do
    [ -f "$d/vendor" ] || continue
    printf '%s: ' "$d"
    cat "$d/vendor" "$d/device"
done
```

应找到 `0x024c`、`0xf179`，不要假定设备始终叫 `mmc0:0001:1`。如果已经枚举，先不要改设备树。

## 从源码编译（无需 root）

```bash
git clone https://github.com/YsLtr/b860av21-wifi.git
cd b860av21-wifi
# 先安装与目标内核完全匹配的 headers、make、bc 和编译器。
# ophub 的 headers 未必在 Ubuntu apt 仓库中；使用对应内核发行方的包。
# 参考环境使用 GCC 14，默认 GCC 13 不支持 -fmin-function-alignment=4。
CC=gcc-14 bash scripts/build.sh
modinfo ./8189fs.ko
```

构建入口支持指定目标 headers 与工具链，详细默认值见 [build.sh](scripts/build.sh)：

```bash
KERNEL_SRC=/path/to/matching/kernel/build ARCH=arm64 \
CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc \
JOBS=4 bash scripts/build.sh
```

交叉编译参数仅提供入口，未在所有宿主/工具链组合上验证。不能用 x86 headers 构建 ARM64 模块。

## 板级供电：构建设备树（按需）

**先确认板型和引脚，准备可启动的救援 SD 卡或串口。错误 DTB 可能导致无法启动。** 本项目不自动编辑引导配置，不自动重启，不提供从其他盒子复制的整机 DTB。

我们提供 [设备树叠加源码](dts/b860av21-wifi-power.dts)。它只增加经过实机验证的 GPIO hog，保持现有 SDIO 时钟、引脚复用和其它外设配置不变。使用 `device-tree-compiler` 提供的 dtc / fdtget / fdtoverlay 离线合并，不依赖引导程序支持动态 overlay：

```bash
sudo apt install device-tree-compiler
bash scripts/build-dtb.sh \
  /boot/dtb/amlogic/meson-gxl-s905x-p212.dtb \
  ./meson-gxl-s905x-p212-b860av21-wifi.dtb
```

脚本拒绝覆盖现有文件，也拒绝非参考 P212 模型/不同 GPIO 控制器。它**不能识别真实 PCB 布线**，这些检查不能替代硬件确认。原设备树若已有使用偏移 76 的 regulator/hog，不要重复占用。

确认结果后再人工安装、备份并切换：

```bash
sudo install -m 0644 ./meson-gxl-s905x-p212-b860av21-wifi.dtb /boot/dtb/amlogic/
# 下例适用于实测 extlinux 启动路径；若备份已存在，保留原备份。
sudo cp -an /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.before-b860av21
sudoedit /boot/extlinux/extlinux.conf
```

只修改正在使用的启动条目中的 `fdt` 行：

```text
fdt /dtb/amlogic/meson-gxl-s905x-p212-b860av21-wifi.dtb
```

保留其它条目和启动参数。不要把主机专属的 root UUID、IP、MAC 等复制给别人。不同系统可能实际读取 `uEnv.txt` 而非 extlinux；必须先确认真实启动路径。建议保留一个原 DTB 的救援启动条目。

此 GPIO hog 是已验证的常高供电方案，不实现电源时序管理或省电关断。未来若添加 runtime PM / suspend 支持，应改为板级 regulator / mmc-pwrseq 并重新进行硬件时序验证。

## 安装模块（人工确认，避免覆盖现有可用驱动）

先比较 `modinfo -F vermagic ./8189fs.ko` 与 `uname -r`，还应匹配架构、内核配置及符号版本。不要使用 `--force-vermagic`。

```bash
# 查看现有模块实际位置（没有安装则可能报错）
modinfo -n 8189fs
find /lib/modules/"$(uname -r)" -type f -name '*8189fs.ko*'
```

**如果已有模块，先备份到 `/lib/modules` 之外，记录完整原路径，并处理重复模块。** 不要只复制到另一个目录，让 depmod 在多个同名模块之间挑选。

下面示例仅适用于确认没有旧 8189fs 模块的新安装：

```bash
sudo install -D -m 0644 ./8189fs.ko \
  /lib/modules/"$(uname -r)"/kernel/drivers/net/wireless/realtek/8189fs/8189fs.ko
sudo depmod -a
sudo modprobe 8189fs
```

驱动按 SDIO alias 自动加载；必要时可在 `/etc/modules-load.d/8189fs.conf` 写入单独一行 `8189fs`。如果旧模块已加载，`modprobe` 不会替换它；维护窗口内通过有线或串口连接，断开 WiFi 后 `modprobe -r 8189fs` 再加载，或人工重启。**不要通过正在使用的 WiFi 连接卸载它。**

## 连接和验证

```bash
lsmod | grep 8189fs
modinfo -F version 8189fs
ip -br link
iw dev
nmcli device wifi list
# 交互输入密码，不在命令行、仓库或日志中保存真实凭据。
# wlan0 只是示例，按 iw dev / nmcli 的实际接口名替换。
nmcli --ask device wifi connect 'YOUR_2G_SSID' ifname wlan0
iw dev wlan0 link
ip -4 addr show wlan0
# 指定无线接口，避免测试流量实际上走有线！
ping -I wlan0 -c 5 YOUR_GATEWAY_IP
journalctl -k -b | grep -Ei '8189|mmc|sdio|warning|error'
```

参考机出现 wlan0 / wlan1 两个接口，但不是两张物理网卡；不要照抄别人的 wlan1 示例。以实际可连接 STA 接口为准。若有线与无线同网段，同时考虑路由 metric / 回包路径；普通 `ping 网关` 成功不能单独证明无线数据通路正常。

重启后复查 SDIO ID、驱动、无线自动连接和内核警告。更换驱动前后必须使用相同 AP、频段和测试方法，编译成功不等于性能更好。

## 回滚

- DTB：恢复备份的 extlinux 配置或选择原 DTB 启动条目；若无法启动，使用救援 SD 卡挂载启动分区后恢复。确认恢复生效后才删除新增 DTB。
- 模块升级：用有线/串口连接，断开无线并卸载新模块，按原路径恢复备份模块，`depmod -a` 后重新加载。
- 首次安装撤销：卸载 8189fs，只删除本次新增的模块和自动加载配置，然后运行 `depmod -a`。不要删除其他驱动。
- 设备树修改和模块安装是两步独立变更；排障时分别回滚。不要用缩短 systemd 超时或强制重启来掩盖驱动/服务故障。

## 报告问题

附板卡型号/PCB 照片、`uname -r`、SDIO ID、实际 DTB、编译器版本、构建命令及去敏后的内核错误。**不要提交密码、WiFi PSK、主机 SSH 凭据、整份私人日志或未经授权的 ROM 镜像。**
