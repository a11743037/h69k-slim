#!/usr/bin/env bash
# 04 —— 编译（首次 1.5~3 小时，视 CPU 与网络）
set -euo pipefail
. "$(dirname "$0")/lib.sh"

stage_banner "04 编译"
cd "$SRC_DIR"

log "预下载源码包（失败不影响编译，编译时会自动重试）"
make -j"$JOBS" download || warn "部分源码包下载失败，交给编译阶段的重试"

log "开始编译，-j$JOBS（日志已由 build.sh 全局 tee 到 $BUILD_DIR/build.log）"
if ! make -j"$JOBS"; then
	die "编译失败。查 $BUILD_DIR/build.log，常见原因：
   1) dtb 报 'rk3568-hinlink-opc.dtsi: No such file' -> 内核版本不含该 dtsi，改用 OWRT_REF=main
   2) 包名不存在 -> 看 03 步体检输出
   3) 内存不足（<8GB）-> 把 JOBS 降到 2~4 再试"
fi

log "04 完成，产物在 bin/targets/rockchip/armv8/"
ls -lh "$SRC_DIR"/bin/targets/rockchip/armv8/ 2>/dev/null | sed 's/^/    /'
