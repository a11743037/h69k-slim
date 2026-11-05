#!/usr/bin/env bash
# 公共环境与工具函数（被 build.sh 与 scripts/*.sh source）
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_DIR

: "${BUILD_DIR:=$PROJECT_DIR/build}"
: "${SRC_DIR:=$BUILD_DIR/openwrt}"
: "${DIST_DIR:=$PROJECT_DIR/dist}"
: "${OWRT_REPO:=https://github.com/openwrt/openwrt}"
: "${OWRT_REF:=main}"
: "${OWRT_COMMIT:=}"
: "${JOBS:=$(nproc 2>/dev/null || echo 4)}"

# 5G 界面/守护进程（modem-pro）：按提交号锁定，升级只需改这两行
: "${MODEM_PRO_REPO:=https://github.com/ouyangzq/modem-pro}"
: "${MODEM_PRO_COMMIT:=397e014b4fe4e5c6a5213fcccbf438590f495a05}"
: "${LUCI_PROTO_REPO:=https://github.com/ouyangzq/luci-proto-modem-pro}"
: "${LUCI_PROTO_COMMIT:=55e682c5e78a5b8447e44315cade04dbca98dbd1}"

# 主题（Argon 派生，7.5MB 字体+图标）：不放进本仓库，构建时 sparse clone 拉取。
# 原因：这个网络环境里 HTTPS push 大文件会被重置（8MB 推不上去），仓库压到 500KB 才稳。
: "${THEME_REPO:=https://github.com/ouyangzq/H29KorH69K-OPENWRT}"
: "${THEME_COMMIT:=8910dc75db7169157565eb6556ba4b33d6489377}"
: "${THEME_DIRNAME:=luci-theme-daocaoren}"

export BUILD_DIR SRC_DIR DIST_DIR OWRT_REPO OWRT_REF OWRT_COMMIT JOBS
export MODEM_PRO_REPO MODEM_PRO_COMMIT LUCI_PROTO_REPO LUCI_PROTO_COMMIT
export THEME_REPO THEME_COMMIT THEME_DIRNAME

if [ -t 1 ]; then
	C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_END=$'\033[0m'
else
	C_OK=; C_WARN=; C_ERR=; C_END=
fi

log()  { printf '%s==>%s %s\n' "$C_OK" "$C_END" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_END" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_END" "$*" >&2; exit 1; }

require_linux() {
	case "$(uname -s)" in
		Linux) ;;
		*) die "构建必须在 Linux 上跑（WSL2 也可以）。当前系统：$(uname -s)。
   Windows 下请用 WSL2：wsl --install -d Ubuntu，然后在该 Ubuntu 里执行本脚本。
   或用仓库自带的 GitHub Actions 工作流在云端构建。" ;;
	esac
	for t in git make gcc g++ python3 rsync unzip gawk; do
		command -v "$t" >/dev/null 2>&1 || die "缺少依赖：$t（Ubuntu: sudo apt install build-essential git python3 rsync unzip gawk libncurses-dev）"
	done
}

stage_banner() {
	printf '\n%s──────── %s ────────%s\n' "$C_OK" "$*" "$C_END"
}
