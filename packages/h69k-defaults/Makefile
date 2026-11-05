#
# h69k-defaults —— H69K 精简固件的出厂默认设置（纯文件包）
#
include $(TOPDIR)/rules.mk

PKG_NAME:=h69k-defaults
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=h69k-slim
PKG_LICENSE:=GPL-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/h69k-defaults
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=HINLINK OPC-H69K factory defaults (hostname / wifi / 5G / root password)
  DEPENDS:=+luci-proto-qmi +uqmi
  PKGARCH:=all
endef

define Package/h69k-defaults/description
  H69K 精简固件首次启动的一次性设置：
    - 主机名、时区 CST-8、国内 NTP
    - 无线默认开启，SSID=H69K，WPA2 密码 password
    - root 密码 password（首次登录请立即修改）
    - 两个网口：eth0 = LAN，eth1 = WAN(DHCP)
  5G 接口不在这里建：由 modemd（modem-pro）自动创建，APN 在其「5G 终端」页面改。
  全部带一次性标记，用户改过之后不会被再覆盖。
endef

# 纯文件包必须显式清空 Build/Compile，否则会去空目录里跑 make
define Build/Compile
endef

define Package/h69k-defaults/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/zzz-h69k-defaults $(1)/etc/uci-defaults/
	$(INSTALL_BIN) ./files/etc/uci-defaults/89-resize-rootfs $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/h69k-defaults $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/h69k-factory $(1)/usr/libexec/
endef

$(eval $(call BuildPackage,h69k-defaults))
