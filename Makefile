include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-icenetwork-esp
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=IceNetwork

LUCI_TITLE:=LuCI support for IceNetwork ESP
LUCI_DEPENDS:=+luci-base +rpcd +uhttpd-mod-ubus +openssl-util
LUCI_PKGARCH:=all

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
