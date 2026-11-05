#!/usr/bin/env bash
# 02 —— 注入设备支持（设备树 / 设备定义 / 本地包）
set -euo pipefail
. "$(dirname "$0")/lib.sh"

stage_banner "02 注入 H69K 设备支持"

DTS_DIR="$SRC_DIR/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip"
ARMV8_MK="$SRC_DIR/target/linux/rockchip/image/armv8.mk"

[ -d "$SRC_DIR" ] || die "找不到源码目录 $SRC_DIR，请先执行 01-fetch.sh"

# --- 1. 设备树：放进 kernel 的 files/ overlay，image.mk 会用 cpp+dtc 直接编出 dtb ---
mkdir -p "$DTS_DIR"
cp -f "$PROJECT_DIR/overlay/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h69k.dts" "$DTS_DIR/"
log "设备树已就位：target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h69k.dts"

# --- 2. 设备定义：追加到 armv8.mk（幂等；追加而非打补丁，跨版本不会失效）---
if grep -q 'Device/hinlink_opc-h69k' "$ARMV8_MK"; then
	log "armv8.mk 已含 hinlink_opc-h69k，跳过"
else
	{
		printf '\n# ==== H69K slim overlay (scripts/02-overlay.sh) ====\n'
		cat "$PROJECT_DIR/device/hinlink_opc-h69k.mk"
	} >> "$ARMV8_MK"
	log "设备定义已追加到 armv8.mk"
fi

# --- 2b. 不要 Docker 时把它从设备定义里摘掉 ---
# 只在追加进来的那段里删（锚定整行，不会误伤上游其它设备）
if [ "${WITH_DOCKER:-1}" = "0" ]; then
	sed -i '/^	dockerd docker luci-app-dockerman \\$/d' "$ARMV8_MK"
	warn "WITH_DOCKER=0：已从设备定义里摘掉 dockerd / docker / luci-app-dockerman（镜像小约 200MB）"
fi

# --- 2c. 让 u-boot 包真正被编出来（否则镜像组装时缺 u-boot-rockchip.bin）---
# u-boot 的每个变体都是 HIDDEN 包（uboot-rockchip/Makefile 里 HIDDEN:=1）。
# hidden 符号在 .config 里写 =y 会被 kconfig 直接忽略，唯一入口是 BUILD_DEVICES
# 触发的 "DEFAULT := y if ..._DEVICE_<设备>"。我们复用的是 H68K 变体，设备不在它的
# 列表里，所以往 BUILD_DEVICES 里补一行。
UBOOT_MK="$SRC_DIR/package/boot/uboot-rockchip/Makefile"
if [ ! -f "$UBOOT_MK" ]; then
	warn "找不到 $UBOOT_MK，跳过（u-boot 可能编不出来）"
elif grep -q 'hinlink_opc-h69k' "$UBOOT_MK"; then
	log "u-boot 变体已包含 hinlink_opc-h69k，跳过"
else
	python3 - "$UBOOT_MK" <<'PY' || die "给 u-boot 补 BUILD_DEVICES 失败"
import sys
p = sys.argv[1]
lines = open(p, encoding='utf-8').read().split('\n')
try:
    start = next(i for i, l in enumerate(lines) if l.startswith('define U-Boot/hinlink-h68k-rk3568'))
except StopIteration:
    sys.exit('没找到 U-Boot/hinlink-h68k-rk3568 块（上游可能改名）')
for i in range(start, min(start + 12, len(lines))):
    if lines[i].strip() == 'hinlink_h68k':
        lines[i] = '    hinlink_h68k \\'
        lines.insert(i + 1, '    hinlink_opc-h69k')
        break
else:
    sys.exit('没找到 hinlink_h68k 那一行 BUILD_DEVICES')
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
print('  已把 hinlink_opc-h69k 加入 hinlink-h68k-rk3568 的 BUILD_DEVICES')
PY
fi

# --- 3. 本地包 ---
mkdir -p "$SRC_DIR/package/h69k"
for p in "$PROJECT_DIR"/packages/*/; do
	name="$(basename "$p")"
	rsync -a --delete "$p" "$SRC_DIR/package/h69k/$name/"
done
log "本地包已就位：$(ls "$SRC_DIR/package/h69k" | tr '\n' ' ')"

# --- 3b. modem-pro 缺件修复 ---
# 上游 commit 397e014 的 Makefile 要 INSTALL_BIN files/packaging/openwrt/files/etc/init.d/modemd，
# 但该文件在仓库里已缺失 -> 直接编会失败。这里按需补一份等价脚本。
# 判断放在文件层面：上游将来补回来后，这里自动不再介入。
MODEM_DIR="$SRC_DIR/package/h69k/modem-pro"
MODEM_INIT="$MODEM_DIR/files/packaging/openwrt/files/etc/init.d/modemd"
if [ -d "$MODEM_DIR" ]; then
	if [ -f "$MODEM_INIT" ]; then
		log "modem-pro 自带 init 脚本，跳过补齐"
	else
		install -D -m 0755 "$PROJECT_DIR/fixes/etc/init.d/modemd" "$MODEM_INIT"
		warn "modem-pro 上游缺 etc/init.d/modemd，已用 fixes/etc/init.d/modemd 补上"
	fi
else
	warn "没找到 $MODEM_DIR，跳过 modem-pro 相关处理（先跑 01）"
fi

# --- 3c. 去掉 +adb-enablemodem 依赖 ---
# adb-enablemodem 只是个小脚本，但它 DEPENDS:=+adb，而 adb 要从 AOSP 源码编译（体积大、国内拉取不稳）。
# modem-pro 作者自己的 README 也写明"已从依赖中去掉：它要求编 adb，需从 google 源拉源码"。
# 只有需要"用 adb 把被锁死的模组拉起来"时才要它：WITH_ADB=1 ./build.sh 02
if [ -d "$MODEM_DIR" ]; then
	if [ "${WITH_ADB:-0}" = "1" ]; then
		log "WITH_ADB=1，保留 +adb-enablemodem 依赖（会额外编译 adb）"
	elif grep -q '+adb-enablemodem' "$MODEM_DIR/Makefile"; then
		sed -i '/DEPENDS:=.*+adb-enablemodem/s/+adb-enablemodem //' "$MODEM_DIR/Makefile"
		log "已剔除 +adb-enablemodem 依赖（避免为它编译 adb；WITH_ADB=1 可保留）"
	fi
fi

# --- 4. 自检：设备树引用的 dtsi 是否存在于当前内核版本 ---
KVER="$(sed -n 's/^KERNEL_PATCHVER:=//p' "$SRC_DIR/target/linux/rockchip/Makefile" | tr -d '[:space:]')"
case "$KVER" in
6.1[2-7])
	warn "当前内核 $KVER 大概率没有 rk3568-hinlink-opc.dtsi（上游 6.18 才有）。"
	warn "若 04 步编译 dtb 报 'rk3568-hinlink-opc.dtsi: No such file'，请改用 OWRT_REF=main，"
	warn "或把 overlay/vendor/rk3568-hinlink-opc.dtsi 一并放入 $DTS_DIR。"
	;;
esac

log "02 完成"
