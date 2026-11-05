#
# HINLINK OPC-H69K —— 设备定义（精简版）
#
# 这段内容由 scripts/02-overlay.sh 追加到
#   target/linux/rockchip/image/armv8.mk   末尾
# 追加而不是打补丁：上游 armv8.mk 每个版本都在增删设备，固定 hunk 的补丁必然失效，
# 而 armv8.mk 只要求"定义 Device + TARGET_DEVICES +="，位置无关，追加永远有效。
#
# 说明：
#   DEVICE_DTS 不写 —— image/Makefile 里 DEVICE_DTS = $(SOC)-$(lastword $(subst _, ,$(1)))
#   对 hinlink_opc-h69k 正好推出 rk3568-opc-h69k，与 overlay 里的 dts 文件名一致。
#
#   5G 拨号走 modem-pro（modemd-pro + luci-app-modemd-pro + luci-proto-modem-pro），
#   为什么三个包缺一不可：
#     modemd-pro              守护进程 + 四家厂商拨号器 + proto=quectel
#     luci-app-modemd-pro     「5G 终端 / 设备中心」界面（用户要的那个好看面板）
#     luci-proto-modem-pro    proto=modem_pro，modemd 默认 wan_mode="modem_pro" 依赖它，
#                             缺了它 netifd 会报「不支持的协议类型」，接口建不起来
#   uqmi / umbim / comgt / luci-proto-qmi 保留，作为不用 modemd 时的原生拨号退路。
#
#   LuCI 菜单来源（对应需求里那张侧栏截图）：
#     状态 / 系统 / 网络   ← luci 元包（luci-mod-status / mod-system / mod-network）
#     5G终端               ← luci-app-modemd-pro
#     服务                 ← luci-app-ttyd（没有子项时顶层菜单不渲染，所以留一个终端页占位）
#     Docker               ← luci-app-dockerman（自带 docker / dockerd / docker-compose / ttyd）
#     整体外观             ← luci-theme-daocaoren（Argon 派生，自带 uci-defaults 自动设为默认主题）
#

define Device/hinlink_opc-h69k
  $(Device/rk3568)
  DEVICE_VENDOR := HINLINK
  DEVICE_MODEL := OPC-H69K
  DEVICE_ALT0_VENDOR := LinkStar
  DEVICE_ALT0_MODEL := OPC-H69K
  SUPPORTED_DEVICES += hinlink,opc-h69k
  # u-boot：直接复用上游同 SoC 的 H68K 变体。
  # 依据：厂商刷机包 H6XK-Boot-Loader.bin 对 H66K/H68K/H69K 通用，
  #       三块板 DDR 与 PMIC 相同；这样无需给 uboot-rockchip 打任何补丁。
  UBOOT_DEVICE_NAME := hinlink-h68k-rk3568
  DEVICE_PACKAGES := \
	h69k-defaults \
	luci-app-fan-h69k luci-app-oled \
	modemd-pro luci-app-modemd-pro luci-proto-modem-pro \
	luci-theme-daocaoren luci-app-ttyd \
	dockerd docker luci-app-dockerman \
	kmod-hwmon-pwmfan \
	kmod-mt7921e wpad-basic-mbedtls \
	kmod-r8125-rss kmod-r8169 \
	kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim kmod-usb-net-cdc-ncm \
	kmod-usb-serial-option kmod-usb-serial-wwan kmod-usb-wdm kmod-usb-acm \
	uqmi umbim comgt luci-proto-qmi luci-proto-mbim luci-proto-3g
endef
TARGET_DEVICES += hinlink_opc-h69k
