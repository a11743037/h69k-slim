#!/usr/bin/env bash
# 01 —— 拉取 OpenWrt 源码、feeds、以及 modem-pro（5G 界面/守护进程）
set -euo pipefail
. "$(dirname "$0")/lib.sh"

stage_banner "01 获取 OpenWrt 源码（$OWRT_REF）"

mkdir -p "$BUILD_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
	log "clone $OWRT_REPO ($OWRT_REF) -> $SRC_DIR"
	git clone --depth 1 --branch "$OWRT_REF" "$OWRT_REPO" "$SRC_DIR"
else
	log "源码已存在，跳过 clone（如需换版本请删掉 $SRC_DIR）"
fi

if [ -n "$OWRT_COMMIT" ]; then
	log "切换到指定提交 $OWRT_COMMIT"
	git -C "$SRC_DIR" fetch --depth 1 origin "$OWRT_COMMIT"
	git -C "$SRC_DIR" checkout -q "$OWRT_COMMIT"
fi

REV="$(git -C "$SRC_DIR" rev-parse --short HEAD)"
KVER="$(sed -n 's/^KERNEL_PATCHVER:=//p' "$SRC_DIR/target/linux/rockchip/Makefile" | tr -d '[:space:]')"
log "当前源码：$REV，rockchip 内核系列：$KVER"
printf '%s %s\n' "$REV" "$KVER" > "$BUILD_DIR/.upstream"

stage_banner "01b 更新 feeds"
cd "$SRC_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

# modemd 是 Go 程序，必须有 golang feed（提供 golang/host 与 golang-package.mk）
[ -f "$SRC_DIR/feeds/packages/lang/golang/golang-package.mk" ] || {
	warn "没找到 golang feed，单独补装"
	./scripts/feeds install -p golang golang
}
[ -f "$SRC_DIR/feeds/packages/lang/golang/golang-package.mk" ] \
	|| die "golang feed 缺失：modemd-pro 会被标 @BROKEN，整个镜像编不出来"
log "feeds 就绪（含 golang）"

stage_banner "01c 获取 modem-pro / luci-proto-modem-pro"

# 不把 14MB 的 Go 源码 + 厂商 C 拨号器复制进本工程，直接 clone 到 package/h69k/，
# 本工程只记录两个提交号（研究/升级时改 lib.sh 里那两个变量即可）。
fetch_pkg() {
	local name="$1" repo="$2" commit="$3" dir="$SRC_DIR/package/h69k/$1"

	if [ ! -d "$dir/.git" ]; then
		log "clone $name @ ${commit:0:7}"
		git clone --quiet "$repo" "$dir"
	else
		log "$name 已存在，跳过 clone"
	fi

	if [ -n "$commit" ] && [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
		git -C "$dir" fetch --quiet --depth 1 origin "$commit"
		git -C "$dir" checkout -q "$commit"
	fi
	printf '%s %s\n' "$name" "$(git -C "$dir" rev-parse --short HEAD)" >> "$BUILD_DIR/.packages"
}

: > "$BUILD_DIR/.packages"
mkdir -p "$SRC_DIR/package/h69k"
fetch_pkg modem-pro            "$MODEM_PRO_REPO"  "$MODEM_PRO_COMMIT"
fetch_pkg luci-proto-modem-pro "$LUCI_PROTO_REPO" "$LUCI_PROTO_COMMIT"

log "第三方包版本："
sed 's/^/    /' "$BUILD_DIR/.packages"

stage_banner "01d 获取主题 $THEME_DIRNAME"

# 主题 7.5MB（65 个字体/图标文件），放在本仓库里会让 HTTPS push 被重置，
# 所以改为构建时从参考仓库 sparse clone 只取这一个目录。
THEME_DIR="$SRC_DIR/package/h69k/$THEME_DIRNAME"
if [ -d "$THEME_DIR" ]; then
	log "主题已存在，跳过"
else
	TMP="$BUILD_DIR/.tmp-theme"
	rm -rf "$TMP"
	git clone --quiet --depth 1 --filter=blob:none --sparse "$THEME_REPO" "$TMP" \
		|| die "拉取主题失败：$THEME_REPO（网络问题请重试）"
	git -C "$TMP" sparse-checkout set "$THEME_DIRNAME" >/dev/null 2>&1
	if [ -n "$THEME_COMMIT" ] && [ "$(git -C "$TMP" rev-parse HEAD)" != "$THEME_COMMIT" ]; then
		git -C "$TMP" fetch --quiet --depth 1 origin "$THEME_COMMIT" \
			&& git -C "$TMP" checkout -q "$THEME_COMMIT" || warn "主题未能切到 $THEME_COMMIT，使用默认分支"
	fi
	[ -d "$TMP/$THEME_DIRNAME" ] || die "参考仓库里没找到 $THEME_DIRNAME"
	cp -r "$TMP/$THEME_DIRNAME" "$THEME_DIR"
	rm -rf "$TMP"
	# 与本地维护版本保持一致：less/ 与 "cascade copy.css" 不参与构建
	rm -rf "$THEME_DIR/less"
	rm -f "$THEME_DIR/htdocs/luci-static/daocaoren/css/cascade copy.css"
	log "主题已就位：$(find "$THEME_DIR" -type f | wc -l) 个文件"
fi
printf 'theme %s\n' "$THEME_COMMIT" >> "$BUILD_DIR/.packages"

stage_banner "01d 获取主题 $THEME_DIRNAME"

# 主题 7.5MB（65 个字体/图标文件），放在本仓库里会让 HTTPS push 被重置，
# 所以改为构建时从参考仓库 sparse clone 只取这一个目录。
THEME_DIR="$SRC_DIR/package/h69k/$THEME_DIRNAME"
if [ -d "$THEME_DIR" ]; then
	log "主题已存在，跳过"
else
	TMP="$BUILD_DIR/.tmp-theme"
	rm -rf "$TMP"
	git clone --quiet --depth 1 --filter=blob:none --sparse "$THEME_REPO" "$TMP" \
		|| die "拉取主题失败：$THEME_REPO（网络问题请重试）"
	git -C "$TMP" sparse-checkout set "$THEME_DIRNAME" >/dev/null 2>&1
	if [ -n "$THEME_COMMIT" ] && [ "$(git -C "$TMP" rev-parse HEAD)" != "$THEME_COMMIT" ]; then
		git -C "$TMP" fetch --quiet --depth 1 origin "$THEME_COMMIT" \
			&& git -C "$TMP" checkout -q "$THEME_COMMIT" || warn "主题未能切到 $THEME_COMMIT，使用默认分支"
	fi
	[ -d "$TMP/$THEME_DIRNAME" ] || die "参考仓库里没找到 $THEME_DIRNAME"
	cp -r "$TMP/$THEME_DIRNAME" "$THEME_DIR"
	rm -rf "$TMP"
	# 与本地维护版本保持一致：less/ 与 "cascade copy.css" 不参与构建
	rm -rf "$THEME_DIR/less"
	rm -f "$THEME_DIR/htdocs/luci-static/daocaoren/css/cascade copy.css"
	log "主题已就位：$(find "$THEME_DIR" -type f | wc -l) 个文件"
fi
printf 'theme %s\n' "$THEME_COMMIT" >> "$BUILD_DIR/.packages"
