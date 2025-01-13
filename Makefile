include $(TOPDIR)/rules.mk

PKG_NAME:=linksys-udp-st
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/OFaustLinksys/linksys-udp-st.git
PKG_SOURCE_VERSION:=main
PKG_SOURCE_DATE:=2024-01-13

PKG_MAINTAINER:=Linksys
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/linksys-udp-st
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Linksys UDP Speed Test Utility
  DEPENDS:=+kmod-nss-udp-st
endef

define Package/linksys-udp-st/description
  A command-line wrapper for the NSS UDP Speed Test kernel module.
  Provides simplified interface for running UDP speed tests with JSON output.
  Supports start, status, and stop commands with automatic resource cleanup.
endef

define Build/Prepare
	$(PKG_UNPACK)
	$(Build/Patch)
endef

define Build/Compile
	# No compilation needed for shell script
endef

define Package/linksys-udp-st/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/linksys-udp-st.sh $(1)/usr/bin/linksys-udp-st
endef

$(eval $(call BuildPackage,linksys-udp-st))