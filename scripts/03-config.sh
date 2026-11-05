#!/usr/bin/env bash
# 03 —— 生成 .config 并做"编译前体检"
#
# 体检的两件事，都是为了把错误挡在 3 小时编译之前：
#   1) 关键 CONFIG 符号是否真的被选中（被 kconfig 丢掉说明依赖不满足）
#   2) DEVICE_PACKAGES 里的每个包名是否真实存在（拼错的话到打包阶段才报错）
set -euo pipefail
. "$(dirname "$0")/lib.sh"

SKIP_CHECK=0
[ "${1:-}" = "--skip-check" ] && SKIP_CHECK=1

stage_banner "03 生成配置"

cd "$SRC_DIR"
cp -f "$PROJECT_DIR/configs/h69k_slim.seed" .config

# 允许用环境变量覆盖分区大小（32GB eMMC 想多留空间时用）
if [ -n "${ROOTFS_PARTSIZE:-}" ]; then
	sed -i "s/^CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE/" .config
fi
if [ -n "${KERNEL_PARTSIZE:-}" ]; then
	sed -i "s/^CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE/" .config
fi

log "make defconfig（展开默认值，同时生成 tmp/.packageinfo）"
make defconfig

[ $SKIP_CHECK -eq 1 ] && { log "跳过体检"; exit 0; }

# .packageinfo 是包名体检的数据源，个别版本 defconfig 不会顺手生成
[ -f tmp/.packageinfo ] || make prepare-tmpinfo

stage_banner "03b 体检：关键配置项"
REQUIRED="
CONFIG_TARGET_rockchip_armv8_DEVICE_hinlink_opc-h69k
CONFIG_TARGET_ROOTFS_EXT4FS
CONFIG_PACKAGE_u-boot-hinlink-h68k-rk3568
CONFIG_PACKAGE_h69k-defaults
CONFIG_PACKAGE_luci-app-fan-h69k
CONFIG_PACKAGE_luci-app-oled
CONFIG_PACKAGE_luci-app-package-manager
CONFIG_PACKAGE_luci-proto-qmi
CONFIG_PACKAGE_kmod-mt7921e
CONFIG_PACKAGE_kmod-hwmon-pwmfan
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan
"
FAILED=""
for s in $REQUIRED; do
	if grep -qx "$s=y" .config; then
		printf '  \033[1;32m✓\033[0m %s\n' "$s"
	else
		printf '  \033[1;31m✗\033[0m %s\n' "$s"
		FAILED="$FAILED $s"
	fi
done

stage_banner "03c 体检：DEVICE_PACKAGES 包名是否存在"
PKGINFO="$SRC_DIR/tmp/.packageinfo"
[ -f "$PKGINFO" ] || die "找不到 $PKGINFO（defconfig 没跑成功？）"

# 从我们自己的设备定义里取包名（避免被 armv8.mk 里其它设备干扰）
PKGS="$(awk '/^define Device\/hinlink_opc-h69k/,/^endef/' "$PROJECT_DIR/device/hinlink_opc-h69k.mk" \
	| awk '/DEVICE_PACKAGES/{f=1} f' \
	| tr -d '\\' | sed 's/DEVICE_PACKAGES :=//' | tr ' ' '\n' \
	| grep -Ev '^$|^endef$' || true)"

for p in $PKGS; do
	if grep -qx "Package: $p" "$PKGINFO"; then
		printf '  \033[1;32m✓\033[0m %s\n' "$p"
	else
		printf '  \033[1;31m✗\033[0m %s  (tmp/.packageinfo 里没有这个包)\n' "$p"
		FAILED="$FAILED pkg:$p"
	fi
done

# modemd-pro 是 Go 包：没有 golang feed 时会被标 @BROKEN，编译阶段才炸，这里提前拦住
if grep -A25 '^Package: modemd-pro$' "$PKGINFO" | grep -q '@BROKEN'; then
	printf '  \033[1;31m✗\033[0m modemd-pro 被标 @BROKEN（golang feed 缺失）\n'
	FAILED="$FAILED modemd-pro@BROKEN"
fi

# 侧栏菜单自检：这几项缺了，首次开机菜单会少块（只告警，不拦）
stage_banner "03d 自检：侧栏菜单依赖"
for s in CONFIG_PACKAGE_luci-mod-status CONFIG_PACKAGE_luci-mod-system CONFIG_PACKAGE_luci-mod-network; do
	grep -qx "$s=y" .config \
		&& printf '  \033[1;32m✓\033[0m %s\n' "$s" \
		|| printf '  \033[1;33m!\033[0m %s 未选中（对应菜单可能缺失）\n' "$s"
done

# 一次性报全部问题：一轮 CI 十几分钟，别让用户为第二个错误再等一轮
if [ -n "$FAILED" ]; then
	printf '\n\033[1;31m[FAIL]\033[0m 体检未通过，共 %d 项：\n' "$(echo $FAILED | wc -w)"
	for x in $FAILED; do echo "    - $x"; done
	die "按上面清单修正 configs/h69k_slim.seed 或 device/hinlink_opc-h69k.mk 后重跑。"
fi

log "03 完成，配置已通过体检"
