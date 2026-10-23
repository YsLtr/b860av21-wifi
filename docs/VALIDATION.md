# 验证记录与边界

## 参考硬件

- 标签 B860AV2.1，Amlogic GXL / S905L 类平台。
- RTL8189FTV，SDIO vendor/device `024c:f179`。
- Armbian noble，aarch64，`6.12.37-ophub`。
- OpenIPC RTL8189FS v5.11.6.0，GCC 14。
- ophub P212 基础 DTB，仅增加 GPIODV_27 输出高的 hog。

参考机验证过 SDIO 枚举、模块加载、2.4 GHz 扫描连接、网络传输和多次重启后自动恢复。并未完成全部 AP/P2P/休眠/长期稳定性测试。

## 设备树可复现性

使用仓库的 DTS + `scripts/build-dtb.sh`，对参考机的原始 P212 DTB 离线合并。把生成结果和参考机正在使用的 WiFi DTB 分别用 `dtc -s -I dtb -O dts` 规范化，文本比较完全一致。未改写启动分区，也未切换设备树。

原始反编译输出的属性顺序可能不同，不代表内容不同。基础 DTB 自身存在 dtc 警告；不通过关闭验证来掩盖新增问题。

可在自己的 Linux 环境复查：

```bash
bash tests/dtb-check.sh /path/to/stock/meson-gxl-s905x-p212.dtb
```

检查新节点的 GPIO、输出电平属性；拒绝覆盖、重复应用；删除新节点后规范化树必须与基础树一致。

## 源码与构建

原已部署源码与固定 OpenIPC 上游提交逐文件比对，573 个上游跟踪文件中，仅 Makefile、os_intfs.c、ioctl_cfg80211.c 三处存在改动。仓库保留上游历史和版权，加入相应兼容处理及可移植构建入口。版本条件和同根源 MAC 地址写入处理可能使公布源码与此前部署版本不逐字节相同。

### 本次发布前实测结果

- 全量构建以非特权用户 `nobody` 在隔离临时目录运行，`JOBS=2`，GCC `14.2.0`，匹配的 `6.12.37-ophub` headers；退出码 **0**。
- `MODPOST`、链接完成，生成 `8189fs.ko`；版本 `v5.11.6.0-2-gb9aa73b62.20211117`。
- `vermagic`：`6.12.37-ophub SMP mod_unload aarch64`。
- SDIO alias：`sdio:c*v024CdF179*`；依赖：`cfg80211`。
- 构建仍有上游警告；缺少 `vmlinux` 导致 BTF 生成跳过，未影响模块链接。这不是零警告构建。
- `python3 tests/driver-check.py` 通过：兼容版本边界、strlcpy 返回值/截断/零长度、构建参数转发及校验、源码 guard。
- Shell 语法检查、`git diff --check`、设备树隔离测试通过。
- 不发布编译产物、私人日志或凭据；每个使用者按目标内核自行构建。

**构建通过、静态检查通过，不等于新生成模块已经在机器上替换并通过所有运行测试。** 本次发布过程不替换参考机现有模块，不卸载无线，不更改真实启动配置。

## 常见误判

- 普通 ping 成功可能走有线，验证无线要 `ping -I <无线接口>`。
- `modprobe` 返回成功不代表已替换内存中的旧模块。
- GPIO 全局编号、mmc 编号、wlan 编号不是固定硬件标识。
- 2.4 GHz 芯片不因 SSID 名字叫“5G”而支持 5 GHz。
- 默认系统服务或日志配置的问题不能直接归因于 WiFi 驱动。不要为安装本驱动修改 journald、watchdog 或系统关机超时。
