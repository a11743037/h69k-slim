#!/usr/bin/env bash
#
# H69K（RK3568）精简 OpenWrt —— 一键构建
#
#   ./build.sh                 全流程：拉源码 -> 注入设备 -> 生成配置 -> 编译 -> 收集
#   ./build.sh 02 03           只跑指定阶段
#   JOBS=4 ./build.sh          限制并行数（内存 < 8GB 时用）
#   OWRT_REF=main ./build.sh   指定 OpenWrt 分支/标签
#   OWRT_COMMIT=<sha> ./build.sh   锁定到具体提交（可复现构建）
#   ROOTFS_PARTSIZE=4096 ./build.sh   根分区改成 4GB
#   WITH_DOCKER=0 ./build.sh          不带 Docker（镜像小约 200MB，编译快约 20 分钟）
#
set -euo pipefail
. "$(dirname "$0")/scripts/lib.sh"

usage() { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

STEPS=()
SKIP_CHECK=0
for a in "$@"; do
	case "$a" in
		-h|--help) usage ;;
		--skip-check) SKIP_CHECK=1 ;;
		0[1-5]) STEPS+=("$a") ;;
		*) die "不认识的参数：$a（用 --help 看用法）" ;;
	esac
done
[ ${#STEPS[@]} -gt 0 ] || STEPS=(01 02 03 04 05)

require_linux
mkdir -p "$DIST_DIR" "$BUILD_DIR"

# 从第一行就落日志：之前只在 04 阶段 tee，01/02/03 报错时 build.log 根本不存在，
# CI 里连日志都拿不到（"No files were found with the provided path: build/build.log"）。
exec > >(tee -a "$BUILD_DIR/build.log") 2>&1
log "日志：$BUILD_DIR/build.log"

log "工程：$PROJECT_DIR"
log "源码：$SRC_DIR（$OWRT_REF）  并行：$JOBS  阶段：${STEPS[*]}"

for s in "${STEPS[@]}"; do
	case "$s" in
		01) "$PROJECT_DIR/scripts/01-fetch.sh" ;;
		02) "$PROJECT_DIR/scripts/02-overlay.sh" ;;
		03) if [ $SKIP_CHECK -eq 1 ]; then
				"$PROJECT_DIR/scripts/03-config.sh" --skip-check
			else
				"$PROJECT_DIR/scripts/03-config.sh"
			fi ;;
		04) "$PROJECT_DIR/scripts/04-build.sh" ;;
		05) "$PROJECT_DIR/scripts/05-collect.sh" ;;
	esac
done

log "全部完成"
