# H69K 精简 OpenWrt 构建工程

HINLINK OPC-H69K（RK3568 / 4GB LPDDR4X / 32GB eMMC / M.2 5G / M.2 MT7921 WiFi / 0.91″ OLED）
精简固件源码工程。构建产物是**整盘 .img**，用瑞芯微官方 RKDevTool 一次刷入即可使用。

参考实现：<https://github.com/ouyangzq/H29KorH69K-OPENWRT>（下称"参考仓库"）。
本工程在其基础上做减法：**去掉 99 个 LuCI 应用、180 个无线驱动、TFT 屏幕、RNDIS 等全部非必需项**，
并把它依赖的 6 处上游补丁削减到 **0 处**。

---

## ⚠️ 先读这段：工程里没有 `.img`，镜像要编出来

`dist/` 是空的、`build/` 也不存在 —— **这不是漏了**。这里只有源码 / 脚本 / 配置，
`.img` 必须经过一次完整编译才会产出，而编译需要：

- **Linux**（Ubuntu 22.04/24.04、WSL2、云主机都行；Windows 原生不行）
- 磁盘 **20~40GB**、内存 **8GB+**（4GB 请把 `JOBS` 降到 2）
- 时间 **1.5~3 小时**（首次；之后 ccache 命中会快很多）

我这台开发机是 Windows，`wsl.exe` 被安全策略列入程序黑名单、也没装 Docker，
所以**没法在这里直接生成 `.img` 给你**。下面三条路选一条，拿到的都是同一个文件。

### A. GitHub Actions（最省事，本机什么都不用装）

```bash
cd h69k-openwrt-slim
git init && git add . && git commit -m "h69k slim openwrt"
git branch -M main
git remote add origin https://github.com/<你的账号>/h69k-slim.git
git push -u origin main
```

推到 GitHub → 仓库页 **Actions** → 左侧 `build-h69k-slim` → **Run workflow**
（`with_docker` 填 1，想快就填 0）→ 2~4 小时后在同一页 **Artifacts** 下载
`h69k-slim-image.zip`，里面是 `.img.gz`，解压即得 `.img`。

### B. WSL2（本机跑）

前置检查（2026-11-05 在本机实测）：内存 15.4GB、8 核 16 线程 ✓；**C: 只剩 39.9GB，D: 有 361GB**，
所以发行版必须装到 D:；`C:\Windows\System32\wsl.exe` 只有系统存根，**没有任何发行版**，
WSL 可选功能大概率也没启用 —— 不是"装好了没开"，是**根本没装**。

三步（都需要你手动做，我做不了：`wsl.exe` 在安全黑名单里，启用功能要管理员权限）：

1. **解禁**：安全中心 → 命令安全 → 程序黑名单 → 移除 `wsl.exe`
2. **启用功能 + 装发行版到 D:**（管理员终端，执行完重启一次）

```
wsl --install -d Ubuntu --location D:\WSL\Ubuntu
```

   老版本 WSL 不认 `--location`，那就先 `wsl --install -d Ubuntu`，装完用
   `wsl --export Ubuntu D:\ubuntu.tar` + `wsl --import Ubuntu D:\WSL\Ubuntu D:\ubuntu.tar` 迁过去。

3. **装构建依赖并编译**（下面的命令我可以在 WSL 里直接替你跑）

```bash
# 千万别在 /mnt/d 下编，跨文件系统慢 3 倍以上
cp -r "/mnt/d/app/workbuddy工作空间/h69k/h69k-openwrt-slim" ~/h69k-slim
cd ~/h69k-slim
sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev rsync unzip \
  zlib1g-dev file wget libelf-dev ccache
JOBS=8 ./build.sh
```

8 核 16 线程 + 15GB 内存，`JOBS=8` 是最佳点（再高容易 OOM）。

产物在 `~/h69k-slim/dist/`。Windows 侧用资源管理器打开 `\\wsl$\Ubuntu\home\<用户名>\h69k-slim\dist\` 拷出来。

### C. 云主机 / 实体 Linux

`git clone` 或 scp 上去，装完依赖直接 `./build.sh`。核多最快，8 核约 1 小时。

---

## 一、目标功能对照

| 需求 | 实现方式 | 关键包/文件 |
|---|---|---|
| 5G 拨号 | **modem-pro**（modemd 守护进程 + 四家厂商主机侧拨号器，自动建 `modem<N>` 接口） | `modemd-pro`、`luci-proto-modem-pro`、`uqmi`/`umbim`（退路）、`h69k-defaults` |
| 5G 界面 | modem-pro 自带面板：设备中心 / 5G 终端 / 短信 / 锁频 / 信号历史 | `luci-app-modemd-pro` |
| Wi-Fi 上网 | M.2 PCIe MT7921 + hostapd | `kmod-mt7921e`、`wpad-basic-mbedtls` |
| 自主导入插件 | APK 包管理 + LuCI 软件包页 + 3GB 可写根分区 + 离线 apk 目录 | `luci-app-package-manager`、`CONFIG_TARGET_ROOTFS_EXT4FS` |
| 温控 | 设备树四档 active trip（45/55/65/75℃，回差 4℃）+ SoC 过热关机 | `rk3568-opc-h69k.dts` 的 `&cpu_thermal`、`&tsadc` |
| 风扇正常启动 | pwm-fan 内核调速 + 用户态守护进程（可切手动曲线） | `kmod-hwmon-pwmfan`、`luci-app-fan-h69k` |
| 屏幕正常显示 | SSD1306 128×32 OLED @ i2c5 | `luci-app-oled`、dts 的 `&i2c5` |
| 侧栏菜单 | 状态/系统/5G终端/服务/Docker/网络 六项齐全 | 见 §5.7 |
| 外观 | Argon 派生主题（深色 + 彩色菜单图标） | `luci-theme-daocaoren` |

> 注意：H69K 的屏幕是 **i2c5 上的 SSD1306 OLED**，不是 H29K 的 SPI TFT。
> 所以参考仓库里那套 `tft-display + kmod-fb-tft-gc9307 + fbdev 白名单补丁` 在 H69K 上**整段不需要**，
> 这是精简里省掉的最大一块（也顺带省掉了改 `package/kernel/linux/modules/video.mk` 的补丁）。

---

## 二、方案要点（为什么这么做）

**1. 基线用 `main`，不用 25.12**

上游 OpenWrt 从 6.13 起才把 HINLINK rk3568 系列（H66K/H68K）和设备树公共文件
`rk3568-hinlink-opc.dtsi` 合进去。25.12 的内核是 6.12：

```
v6.12/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc.dtsi  -> 404
v6.18/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc.dtsi  -> 200
```

用 25.12 就得自己把公共 dtsi 回移并验证绑定兼容性，属于凭空造风险；
用 `main`（内核 6.18）则**公共 dtsi、H66K/H68K 设备定义、u-boot 变体全都在上游**，
我们只需要补一个 H69K 的 dts + 一段设备定义。要用稳定版：

```bash
OWRT_REF=v25.12.6 ./build.sh   # 需要自己补 dtsi，脚本会给出提示
```

**2. 零内核补丁**

`include/image.mk` 里 dtb 是这样编的（原文）：

```make
$(KDIR)/image-$(1).dtb: FORCE
	$(call Image/BuildDTB,$(strip $(2))/$(strip $(3)).dts,$$@)
```

即 `cpp` + 内核自带 `dtc` **直接编译 `$(LINUX_DIR)/arch/arm64/boot/dts/rockchip/*.dts`**，
不经过内核 dts Makefile 的 `dtb-y` 列表。而 `target/linux/<board>/files/` 会被整体覆盖进内核树，
所以：**把 dts 丢进 `files/` 就够了，不需要往内核补丁目录写任何文件**。
参考仓库打的 `102/103`（加 dtb 行）在本工程里没有必要。

**3. 零 u-boot 补丁**

设备定义里 `UBOOT_DEVICE_NAME` 直接用上游已有的 `hinlink-h68k-rk3568`。
依据：厂商刷机包 `H6XK-Boot-Loader.bin` 对 H66K/H68K/H69K 通用，三块板同 SoC、同 DDR、同 RK809 PMIC。
参考仓库为此新增了 `generic-rk3568` 变体（要改 `package/boot/uboot-rockchip/Makefile`），本工程省掉。
若真机验证 `h68k` 的 u-boot 起不来，改 `device/hinlink_opc-h69k.mk` 一行即可换 `generic-rk3568`
（参考仓库的 `002-uboot-add-generic-rk35xx.patch` 可直接拿来用）。

**4. 设备定义用"追加"，不用补丁**

`armv8.mk` 只要求 `define Device/xxx` + `TARGET_DEVICES += xxx`，与位置无关。
固定 hunk 的 patch 会随上游增删设备而失效（参考仓库就被迫写了 `gen-patches.sh` 重新生成），
追加则永远有效，`02-overlay.sh` 里有幂等判断。

**5. 根分区用 ext4，不用 squashfs**

`pine64-img` 只造 `boot + rootfs` 两个分区，没有 `rootfs_data`。
squashfs 方案下用户拿不到可写 overlay（除非刷完手工 fdisk），而"自主导入插件"必须有空间。
所以：`CONFIG_TARGET_ROOTFS_EXT4FS=y` + `CONFIG_TARGET_ROOTFS_PARTSIZE=3072`，
根分区直接可写 3GB（放得下 Docker 引擎 + 几个镜像），`apk add` 立即可用；
剩余约 29GB eMMC 可后续建数据分区。

**6. 镜像格式就是整盘 raw image**

```
IMAGE/sysupgrade.img.gz = boot-common | boot-script | pine64-img | gzip
```

`pine64-img` 用 `gen_image_generic.sh` 生成 GPT（boot/rootfs 两分区，32MiB 对齐），
再把 `u-boot-rockchip.bin`（idbloader + u-boot）dd 到 **sector 64（32KiB）**。
gunzip 后就是一个从 LBA0 开始的完整可启动磁盘镜像 —— RKDevTool「升级固件」选它即可，
不需要再用 `rkImageMaker`/`afptool` 打 RKFW 私有包。

---

## 三、目录结构

```
h69k-openwrt-slim/
├── build.sh                     一键入口（5 个阶段，可单独跑某一阶段）
├── configs/
│   └── h69k_slim.seed           配置种子，只写与默认值不同的项，交给 make defconfig 展开
├── device/
│   └── hinlink_opc-h69k.mk      设备定义（追加进 target/linux/rockchip/image/armv8.mk）
├── overlay/
│   └── target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/
│       └── rk3568-opc-h69k.dts  H69K 设备树（风扇/温控/网口/OLED/5G）
├── packages/
│   ├── h69k-defaults/           出厂默认值：主机名/时区/无线开启/root 密码/网口
│   ├── luci-app-fan-h69k/       PWM 风扇（内核曲线 + 用户态守护进程 + LuCI 页）
│   ├── luci-app-oled/           SSD1306 OLED 显示（i2c5）
│   ├── modemband/               锁频工具（modemd-pro 的运行时依赖，参考仓库里那个）
├── fixes/
│   └── etc/init.d/modemd        上游缺件补齐（modem-pro 漏了 procd 脚本，见 §5.4）
│
│   ※ luci-theme-daocaoren 不放在本仓库：它 7.5MB / 65 个字体文件，
│     会让 HTTPS push 被网络重置。改由 01-fetch.sh 的 01d 步骤 sparse clone 拉取。
├── scripts/
│   ├── lib.sh                   环境变量与通用函数
│   ├── 01-fetch.sh              clone OpenWrt + feeds update/install
│   ├── 02-overlay.sh            注入 dts / 设备定义 / 本地包
│   ├── 03-config.sh             make defconfig + 编译前体检
│   ├── 04-build.sh              make -jN
│   └── 05-collect.sh            解压 .img + 收集 apk + sha256
├── .github/workflows/build.yml  云端构建（没 Linux 机器时用）
├── build/                       构建中间目录（源码树在这里，不进版本库）
└── dist/                        产物：.img / .img.gz / sha256 / packages/
```

---

## 四、实现步骤

### 前置：一台 Linux 构建机

- Ubuntu 22.04/24.04 或 WSL2 里的 Ubuntu
- 磁盘 ≥ 40GB（源码 + 工具链 + 产物），内存 ≥ 8GB（4GB 内存请 `JOBS=2`）

```bash
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev rsync unzip zlib1g-dev \
  file wget qemu-utils libelf-dev ccache
```

### Step 1 —— 拉源码与 feeds

```bash
./build.sh 01        # 或 OWRT_REF=main OWRT_COMMIT=<sha> ./build.sh 01
```

同时会 clone 三个第三方仓库到 `package/h69k/`：`modem-pro`（5G 守护进程 + 界面）、
`luci-proto-modem-pro`（`proto=modem_pro`）、以及从参考仓库 sparse clone 出来的
`luci-theme-daocaoren`（只取主题目录，7.5MB 不进本仓库）。版本都在 `scripts/lib.sh` 里
按提交号锁死；另外会确保 `golang` feed 存在（modemd 是 Go 程序，缺了它整包会被标 `@BROKEN`）。

关键点：`OWRT_COMMIT` 用于**锁定提交**。`main` 是滚动快照，不锁的话今天编出来的镜像
和明天编出来的不是同一个东西（对排查问题非常致命）。构建完成会在 `build/.upstream` 记下实际提交。

### Step 2 —— 注入设备支持

```bash
./build.sh 02
```

做四件事：拷 dts → 追加设备定义 → 拷三个本地包到 `package/h69k/` → 检查内核版本是否含公共 dtsi。

### Step 3 —— 生成配置并体检

```bash
./build.sh 03
```

`make defconfig` 之后跑两组检查，**这一步是为了把错误挡在 3 小时编译之前**：

1. 关键 `CONFIG_*` 是否真被选中（被 kconfig 丢掉 = 依赖不满足）
2. `DEVICE_PACKAGES` 里每个包名是否存在于 `tmp/.packageinfo`（拼错的话原本要到打包阶段才报错）

输出形如：

```
✓ CONFIG_TARGET_rockchip_armv8_DEVICE_hinlink_opc-h69k
✓ CONFIG_PACKAGE_uboot-rockchip-hinlink-h68k-rk3568
✓ kmod-mt7921e
✗ kmod-xxx  (tmp/.packageinfo 里没有这个包)
```

### Step 4 —— 编译

```bash
./build.sh 04        # 首次 1.5~3 小时
```

### Step 5 —— 收集产物

```bash
./build.sh 05
```

产出 `dist/h69k-slim-<日期>-<commit>.img`，以及 `dist/packages/*.apk`（离线插件）。

---

## 五、关键配置说明

### 5.1 设备树（最关键的三个地方）

**风扇 + 温控**（`overlay/.../rk3568-opc-h69k.dts`）：

```dts
fan: pwm-fan {
    compatible = "pwm-fan";
    cooling-levels = <0 90 120 165 210 255>;   /* 6 档，与 cooling-device 的档位索引对应 */
    #cooling-cells = <2>;
    pwms = <&pwm0 0 50000 0>;                  /* pwm0，周期 50us，极性 normal */
};
```

```dts
&cpu_thermal {
    trips { fan_trip1 { temperature = <45000>; hysteresis = <4000>; type = "active"; }; ... }
    cooling-maps {
        fan-map1 { trip = <&fan_trip1>; cooling-device = <&fan 0 1>; };
        ...
    };
};
```

⚠️ 两个踩过的坑：
- `cooling-maps` 的节点名**不能用 `map0`/`map1`**，基础 dtsi 已占用，`dtc` 会静默合并同名节点
- trip 节点名必须互不相同（参考仓库遇到过 10 档塌成 6 档的问题，`dtc` 不报 warning）

**OLED**：`&i2c5 { status = "okay"; };` —— 上游 dtsi 只开了 i2c0/i2c2，
而 `luci-app-oled` 的 uci-defaults 认 `board_name = hinlink,opc-h69k` 时写 `/dev/i2c-5`。

**关闭 i2c2**：上游 dtsi 把 i2c2 配成 i2c2m1，SCL/SDA 恰好是 PCIe 3.3V 与 SATA 5V 的使能脚，
本板无 i2c2 器件，必须 disable，否则和供电脚抢引脚。

### 5.2 设备定义（`device/hinlink_opc-h69k.mk`）

```make
$(Device/rk3568)
UBOOT_DEVICE_NAME := hinlink-h68k-rk3568
DEVICE_PACKAGES := h69k-defaults luci-app-fan-h69k luci-app-oled \
                   kmod-hwmon-pwmfan kmod-mt7921e wpad-basic-mbedtls ...
```

- `DEVICE_DTS` **不写**：`image/Makefile` 里 `DEVICE_DTS = $(SOC)-$(lastword $(subst _, ,$(1)))`，
  设备名 `hinlink_opc-h69k` 正好推出 `rk3568-opc-h69k`，与 dts 文件名一致
- `SUPPORTED_DEVICES += hinlink,opc-h69k` 让 sysupgrade 认板子（`board_name` 取自 dts 的 compatible）

### 5.3 分区与镜像

```
CONFIG_TARGET_KERNEL_PARTSIZE=16      # boot 分区 16MB（FIT 内核 ~6MB）
CONFIG_TARGET_ROOTFS_PARTSIZE=3072    # 根分区 3GB，可写（Docker 要用）
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=n
CONFIG_TARGET_EXT4_RESERVED_PCT=1     # ext4 保留块 1%（默认 5%，白占 50MB）
```

### 5.4 5G 拨号 + 界面（modem-pro）

用的是参考仓库那套 **modem-pro**，三个包一个都不能少：

| 包 | 作用 | 缺了会怎样 |
|---|---|---|
| `modemd-pro` | Go 守护进程 + 四家厂商主机侧拨号器（移远/芯讯通/广和通/美格）+ `proto=quectel` + 默认 `config.toml` | 没有守护进程，界面全是空的 |
| `luci-app-modemd-pro` | 「设备中心 / 5G 终端」面板：实时速率、信号、运营商、短信、锁网锁频、信号历史、服务启停 | 菜单里看不到入口 |
| `luci-proto-modem-pro` | `proto=modem_pro`（一张接口同时跑 IPv4+IPv6） | netifd 报「不支持的协议类型」，`modem<N>` 建不起来 |

运行时依赖会自动带进来：`comgt(+directip+ncm)`、`modemband`、`umbim`、`uqmi`。

> `+adb-enablemodem` 被本工程**默认剔除**（`02-overlay.sh` 里 sed 掉）：它挂着 `+adb`，
> 而 `adb` 要从 AOSP 源码编译，体积大且国内拉取不稳；modem-pro 作者自己的 README 也写了这点。
> 万一你的模组必须先 adb 拉起来，用 `WITH_ADB=1 ./build.sh 02 03 04 05`。


**接线逻辑**（`/etc/modemd/config.toml` 默认值）：

```
auto_detect_vendor = true     自动识别模组厂商
auto_wan          = true      模组一上线就建 modem<N> 并挂进防火墙 wan 区
wan_mode          = "modem_pro"   一张接口，v4+v6 都在上面
auto_dial         = true
[server] listen   = "0.0.0.0:9527"   面板端口
```

- **APN**：在「5G 终端 → 拨号上网」里填（移动 `cmnet` / 联通 `3gnet` / 电信 `ctnet`），
  也可以在 `/etc/modemd/config.toml` 里改，改完 `/etc/init.d/modemd restart`
- **不要再手工建 `proto=qmi` 的接口**：QMI 模组只有一个数据承载，modemd 的拨号器已经占住了，
  再叠一个 uqmi 会互相打架（现象：`QMUXError 0xe`、`wwan0 link_state 0`、接口拿不到地址）。
  正因如此，`h69k-defaults` 里**已经删掉了**原先预置的 `network.wwan`。
- **退路**：`uqmi` / `umbim` / `luci-proto-qmi` / `luci-proto-mbim` 都还在镜像里，
  把 modemd 停掉（`/etc/init.d/modemd stop`）就能回到原生 QMI/MBIM 拨号。
- **端口暴露**：面板默认监听 `0.0.0.0:9527`，局域网内可直接访问 IP:9527。
  不想暴露就改成 `127.0.0.1:9527`（LuCI 页面走服务端代理，本机访问即可）。

#### ⚠️ 上游缺件修复（本工程唯一改上游的地方）

`modem-pro` 在 commit `397e014` 时，Makefile 第 213 行要安装
`files/packaging/openwrt/files/etc/init.d/modemd`，**但仓库里这个文件已经不存在了**
（只剩 `lib/netifd/proto/quectel.sh`）。直接编会在这里失败：

```
install: cannot stat '.../files/etc/init.d/modemd': No such file or directory
```

处理方式：本工程自带 `fixes/etc/init.d/modemd`（等价的 procd 脚本），
`02-overlay.sh` **只在文件缺失时才写入**；上游以后补回来，这里自动不再介入。
脚本按 `modemd -config /etc/modemd/config.toml` 启动，`respawn 3600 5 10`。

### 5.5 Wi-Fi

`kmod-mt7921e` + `wpad-basic-mbedtls`。机型包 `$(Device/hinlink_h6xk)` 本来就带 `kmod-mt7921e`，
说明 H66K/H68K/H69K 这一代默认就是 MT7921（M.2 PCIe）。

如果你的机器是 **AIC8800 SDIO** 版本（H29K 那种），需要额外三个包：
`kmod-aic8800-sdio`、`aic8800-sdio-firmware`、`aic8800-loader`（参考仓库有源码），
并注意它的驱动**不能** `AUTOLOAD`（会在 preinit 阶段卡死 → 看门狗复位）。

### 5.6 插件导入

镜像默认是 `CONFIG_USE_APK=y`（OpenWrt 25.12 起包管理换成 APK，`.ipk` 不再适用）：

| 方式 | 操作 |
|---|---|
| 在线源 | LuCI → 系统 → 软件包，直接 `apk update && apk add` |
| 离线包 | `dist/packages/*.apk` 上传到 LuCI 软件包页，或 `apk add --allow-untrusted /tmp/xxx.apk` |
| 自建源 | 把 `dist/packages` 丢到自己服务器，改 `/etc/apk/repositories.d/distfeeds.list` |

⚠️ **kmod 不能跨内核**：内核模块与 vermagic 绑定，只能装本次构建产出的 `.apk`。
纯脚本类应用（LuCI 应用、工具）则不受此限。

### 5.7 侧栏菜单与主题

需求里那张侧栏截图，逐项对应如下：

| 菜单 | 由谁提供 | 说明 |
|---|---|---|
| 状态 | `luci-mod-status` | `luci` 元包自带，无需单独选 |
| 系统 | `luci-mod-system` | 同上 |
| 5G终端 | `luci-app-modemd-pro` | modem-pro 的面板（§5.4） |
| 服务 | `luci-app-ttyd` 占位 | **LuCI 不会渲染没有子项的顶层菜单**，所以留一个网页终端页占位；你以后装的插件（ddns / upnp / 广告过滤 / 多拨…）都会自动落进这里，不用改任何配置 |
| Docker | `luci-app-dockerman` | 自带 `docker` / `dockerd` / `docker-compose` / `ttyd` |
| 网络 | `luci-mod-network` | `luci` 元包自带 |

主题 `luci-theme-daocaoren`（Argon 派生）：**不在本仓库里**，由 `01-fetch.sh` 的 `01d` 步骤
从参考仓库 sparse clone 拉取（只下这一个目录）。它的 `root/etc/uci-defaults/30_luci-theme-daocaoren`
会自己把 `luci.main.mediaurlbase` 指到 `/luci-static/daocaoren`，**不需要手工切主题**。

- 想要浅色/深色/自动：LuCI → 系统 → 系统 → 语言和界面（`/etc/config/daocaoren` 里是 `mode`）
- **万一白屏**（这个主题只带 Lua 视图，没有 ucode 模板，靠 `luci-compat` 的兼容层渲染）：

```sh
uci set luci.main.mediaurlbase=/luci-static/bootstrap && uci commit luci
/etc/init.d/uhttpd restart
```

**Docker 的三点注意**：

1. 根分区因此从 1GB 提到 **3GB**（`CONFIG_TARGET_ROOTFS_PARTSIZE=3072`），否则装完 dockerd 就没空间拉镜像了
2. `Docker Root Dir` 默认在根分区（`/opt/docker`），镜像多了会满；长期用建议挂外接盘或后续建数据分区
3. 不想要 Docker：`WITH_DOCKER=0 ./build.sh 02 03 04 05`，`02-overlay.sh` 会把那三个包从设备定义里摘掉，镜像小约 200MB

---

## 六、刷机（RKDevTool）

**一句话：进「升级固件」页，固件选 `h69k-slim-xxxx.img`，点「升级」。**

RKDevTool 有两个页签，只有第一个是"一键"：

| 页签 | 干什么 | 要不要用 |
|---|---|---|
| **升级固件** | 选**一个**镜像文件，工具自己按镜像里的分区表刷 | ✅ 用这个 |
| 高级功能 / 下载镜像 | 手工填地址（0x0 / 0x4000…）逐段刷 | ❌ 不用，除非工具不认镜像 |

步骤：

| # | 操作 | 选哪个文件 |
|---|---|---|
| 1 | 断电，卡针按住 MASKROM 孔 → 插 Type-C → 上电 → 2 秒后松手；工具底部出现「发现一个 MASKROM 设备」 | — |
| 2 | **擦除 Flash**（清掉原厂那张 29GB 单分区表） | `RKDevTool/Image/RK3568_MiniLoaderAll.bin` |
| 3 | **升级**（真正刷机） | `dist/h69k-slim-<日期>-<commit>.img` |
| 4 | 等进度条走完，弹「升级完成 / Download complete」，设备自动重启 | — |

⚠️ 三个必须注意：

- **第 3 步才是刷机**。第 2 步那个 loader 只是用来擦 Flash / 救砖的，**别把它当固件刷**——
  我们的 `.img` 里已经含 idbloader + u-boot（dd 在 sector 64），不需要再单独刷 loader。
- **必须解压**：工具要的是 `.img`，不是 `.img.gz`。CI 产物只有 `.img.gz`（3GB 原始镜像撞 artifact 上限），
  本地用 7-Zip / `gzip -d` 解开即可。
- 路径别带中文、别太深（老版本 RKDevTool 读中文路径会报"固件格式错误"）。

**怎么算刷机成功**（三条都满足）：

1. 工具进度条 100% 且弹「升级完成」，设备自动重启（不是又回到 MASKROM）
2. 网口接电脑，网卡拿到 `192.168.1.x`，浏览器能打开 `http://192.168.1.1`
3. 屏幕（OLED）亮起来显示 IP / 温度，风扇起转

首次启动 60~90 秒（ext4 根分区首次挂载 + 生成 SSH 密钥），**别在这期间断电**。

默认凭据：`root / password`，WiFi `H69K / password` —— **装好第一件事就改掉**。

**工具报「固件格式错误」怎么办**：说明这个版本的 RKDevTool 只认 RKFW 私有包。改走
「高级功能 → 下载镜像」：地址填 `0x0`，文件选同一个 `.img`，点「执行」，效果等价。

### 首次上机自检清单

```sh
cat /proc/device-tree/model              # HINLINK OPC-H69K Board
uname -r                                 # 6.18.x
cat /sys/class/thermal/thermal_zone0/temp     # 温度（毫摄氏度）
ls /sys/class/hwmon/hwmon*/name          # 应有 pwmfan
cat /sys/class/hwmon/hwmon*/pwm1         # 0~255，随温度变化
i2cdetect -y 5                           # 0x3c 处应有 SSD1306
ls /dev/cdc-wdm*                         # 有则 5G 模组已识别
ifstatus wwan | grep -E 'up|address'     # 拨号结果
iwinfo                                   # 无线是否起来
uci get luci.main.mediaurlbase           # 应为 /luci-static/daocaoren（主题生效）
ls /www/luci-static/daocaoren/css/       # 主题静态文件在
/etc/init.d/modemd status                # 5G 守护进程在跑
docker info | head -5                    # Docker 引擎起来了
```

风扇不转的分级排查：`pwm1_enable` 应为 2（内核温控接管）→ `cat pwm1` 是否随温度变 →
`dmesg | grep -i pwm` → 硬件上 `pwm0` 是否被别的功能复用。

---

## 七、已知限制

1. **`main` 是滚动快照**：不设 `OWRT_COMMIT` 时两次构建结果不同；在线 `apk` 源指向 snapshots，
   上游一变就对不上。长期使用请用 `OWRT_COMMIT` 锁定，并用 `dist/packages` 离线装。
2. **u-boot 复用 H68K 变体**：依据充分（同 SoC/DDR/PMIC、厂商 loader 通用），但**未在 H69K 真机验证**。
   起不来的表现是上电无输出、RKDevTool 仍能进 MASKROM，此时换 `generic-rk3568`（见 2.3）。
3. **镜像变大到约 3GB**：根分区 3GB 是为了装得下 Docker。raw `.img` 约 3GB，
   RKDevTool 写入 1~3 分钟。不要 Docker 就 `WITH_DOCKER=0`，并把种子里的
   `CONFIG_TARGET_ROOTFS_PARTSIZE` 改回 1024。
4. **modem-pro 与 dockerd 都是 Go 程序**：首次编译要构建 `golang/host`（约 +10 分钟、磁盘 +500MB），
   `modemd` 约 10MB、`dockerd` + `docker` 约 150MB。换来的是完整 5G 管理面板和容器能力。
5. **主题只有 Lua 视图**：`luci-theme-daocaoren` 没有 ucode 模板，在 ucode 版 LuCI 上靠
   `luci-compat` 兼容层渲染。真机若白屏，用 §5.7 那条命令切回 bootstrap 即可，不影响系统。
6. **不含**：SATA、HDMI、蓝牙、广告过滤、多拨、NAS/网络存储、VPN 服务端（截图里没框的那几项）。
7. **刷机不可逆**：刷之前把原厂固件包留在手上（HINLINK 官网 / 卖家提供），否则回不去原厂系统。

---

## 八、许可

本工程新增的文件（设备树、设备定义、脚本、h69k-defaults）按 GPL-2.0 发布。
`packages/luci-app-oled`、`packages/luci-app-fan-h69k`、`packages/luci-theme-daocaoren`、
`packages/modemband` 来自参考仓库移植，遵循其原始许可（GPL-3.0 / MIT），版权归原作者。
`luci-theme-daocaoren` 本身是 Argon（jerrykuku/luci-theme-argon, GPL-3.0）的派生作品。
`modemd-pro` / `luci-app-modemd-pro` / `luci-proto-modem-pro` 来自 ouyangzq/modem-pro（MIT），
构建时按 `scripts/lib.sh` 里锁定的提交号 clone，未修改源码。
