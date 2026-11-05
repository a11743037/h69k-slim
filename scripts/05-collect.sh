#!/usr/bin/env bash
# 05 —— 收集产物：解压出可直接给 RKDevTool 刷写的 .img，并附带离线插件目录
set -euo pipefail
. "$(dirname "$0")/lib.sh"

stage_banner "05 收集产物"
mkdir -p "$DIST_DIR/packages"

REV="$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
STAMP="$(date +%Y%m%d)"
NAME="h69k-slim-${STAMP}-${REV}"

IMG_GZ="$(ls -1 "$SRC_DIR"/bin/targets/rockchip/armv8/*sysupgrade.img.gz 2>/dev/null | head -1)"
[ -n "$IMG_GZ" ] || die "没找到 sysupgrade.img.gz。先确认 04 步编译成功，且 03 步 CONFIG_TARGET_IMAGES_GZIP=y"

log "解压 $(basename "$IMG_GZ")"
gunzip -c "$IMG_GZ" > "$DIST_DIR/${NAME}.img"
cp -f "$IMG_GZ" "$DIST_DIR/${NAME}.img.gz"

# 镜像里带的 ext4 根分区大小，刷完可直接写插件
ROOTFS_MB="$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=//p' "$SRC_DIR/.config" | tr -d '"' | head -1)"
printf 'rootfs=%sMB kernel=%sMB commit=%s\n' \
	"${ROOTFS_MB:-?}" \
	"$(sed -n 's/^CONFIG_TARGET_KERNEL_PARTSIZE=//p' "$SRC_DIR/.config" | tr -d '"' | head -1)" \
	"$REV" > "$DIST_DIR/${NAME}.buildinfo"

# 离线插件包（apk）：把本次编出来的所有包一起带走，断网也能装
if [ -d "$SRC_DIR/bin/packages" ]; then
	find "$SRC_DIR/bin/packages" -name '*.apk' -exec cp -f {} "$DIST_DIR/packages/" \; 2>/dev/null || true
	CNT="$(ls -1 "$DIST_DIR/packages" 2>/dev/null | wc -l | tr -d ' ')"
	log "已收集 $CNT 个 .apk 到 dist/packages/（可上传到 LuCI 软件包页安装）"
fi

( cd "$DIST_DIR" && sha256sum "${NAME}.img" "${NAME}.img.gz" > "${NAME}.sha256" )

stage_banner "完成"
cat <<EOF
镜像：$DIST_DIR/${NAME}.img        ← RKDevTool 用这个
压缩：$DIST_DIR/${NAME}.img.gz     ← 存档 / LuCI 里 sysupgrade 用
校验：$DIST_DIR/${NAME}.sha256

刷机（RKDevTool，只用「升级固件」页）：
  1. 断电，卡针按住 MASKROM 孔，插 Type-C 连电脑，再上电，2 秒后松手
  2. 工具底部出现「发现一个 MASKROM 设备」
  3. 擦除：固件 选 RKDevTool/Image/RK3568_MiniLoaderAll.bin  → 点「擦除 Flash」
  4. 刷机：固件 选 ${NAME}.img                          → 点「升级」   ← 这一步才是刷机
  5. 弹「升级完成」并自动重启 = 成功；首次启动 60~90 秒
     验证：网口拿到 192.168.1.x，浏览器开 http://192.168.1.1（root/password）

  ⚠️ 第 3 步的 loader 只是用来擦 Flash，别当固件刷；镜像里已含 idbloader + u-boot。
  ⚠️ 必须解压成 .img，工具不认 .img.gz；路径别带中文。
EOF
