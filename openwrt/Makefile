include $(TOPDIR)/rules.mk

PKG_NAME:=linksys-udp-st
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Linksys
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/linksys-udp-st
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Linksys UDP Speed Test Utility
  DEPENDS:=+kmod-nss-udp-st
  EXTRA_DEPENDS:=kmod-nss-udp-st (>= 23.05)
endef

define Package/linksys-udp-st/description
  A command-line wrapper for the NSS UDP Speed Test kernel module.
  Provides simplified interface for running UDP speed tests with JSON output.
  Supports start, status, and stop commands with automatic resource cleanup.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

TARGET_CFLAGS += -Wall -Wextra -Werror -Wno-unused-parameter
TARGET_CFLAGS += -D_GNU_SOURCE
TARGET_CFLAGS += -I$(PKG_BUILD_DIR)

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -o $(PKG_BUILD_DIR)/linksys-udp-st \
		$(PKG_BUILD_DIR)/linksys-udp-st.c \
		$(PKG_BUILD_DIR)/json_helper.c \
		$(PKG_BUILD_DIR)/module_ops.c
endef

define Package/linksys-udp-st/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/linksys-udp-st $(1)/usr/bin/
endef

$(eval $(call BuildPackage,linksys-udp-st))