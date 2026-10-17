#
#  DYYY
#
#  Copyright (c) 2024 huami. All rights reserved.
#  Channel: @huamidev
#  Created on: 2024/10/04
#
# 本地配置文件（可选）
-include Makefile.local

# 自动选取当前工具链可用的最新 iOS SDK。
TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

#export THEOS=/Users/huami/theos
#export THEOS_PACKAGE_SCHEME=roothide

# 根据参数选择打包方案
ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

# 在GitHub Actions中运行时的特殊配置
ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
OPTFLAG = -O3
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYYY

DYYY_SOURCE_DIRS = src/Hooks src/Core src/Settings src/UI src/Support
DYYY_FILES = \
    src/Hooks/DYYY.xm \
    src/Hooks/DYYYABTestHook.xm \
    src/Hooks/DYYYLongPressPanel.xm \
    src/Core/DYYYManager.m \
    src/Core/DYYYUtils.m \
    src/Core/DYYYVideoPlaybackGuard.m \
    src/Settings/DYYYSettingViewController.m \
    src/Settings/DYYYSettingsRegistry.m \
    src/Settings/DYYYSettingsCoordinator.m \
    src/Settings/DYYYSettingsHelper.m \
    src/UI/DYYYAboutDialogView.m \
    src/UI/DYYYBottomAlertView.m \
    src/UI/DYYYConfirmCloseView.m \
    src/UI/DYYYCustomInputView.m \
    src/UI/DYYYFilterSettingsView.m \
    src/UI/DYYYFloatClearButton.xm \
    src/UI/DYYYFloatSpeedButton.m \
    src/UI/DYYYIconOptionsDialogView.m \
    src/UI/DYYYKeywordListView.m \
    src/UI/DYYYOptionsSelectionView.m \
    src/UI/DYYYToast.m \
    src/Support/AWMSafeDispatchTimer.m \
    src/Support/CityManager.m
# 编译和链接同时启用完整 LTO，让优化器跨编译单元优化。
DYYY_CFLAGS = -fobjc-arc -w -flto=full $(addprefix -I,$(DYYY_SOURCE_DIRS))
DYYY_CCFLAGS = -std=gnu++26
$(foreach source,$(filter %.c %.m,$(DYYY_FILES)),$(eval $(source)_CFLAGS += -std=gnu23))
# 各架构保留独立 LTO 中间对象，供 Theos 生成调试符号。
DYYY_LDFLAGS = -O3 -flto=full -Wl,-dead_strip -Wl,-object_path_lto,$(THEOS_OBJ_DIR)/DYYY.lto.o -weak_framework AVFAudio
DYYY_FRAMEWORKS = CoreAudio PhotosUI
DYYY_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS=0
export ERROR_ON_WARNINGS=0
export LOGOS_DEFAULT_GENERATOR=internal

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(shell whoami),huami)
    THEOS_DEVICE_IP = 192.168.31.227
else
    THEOS_DEVICE_IP = 192.168.15.201
endif
THEOS_DEVICE_PORT = 22

# 清理 packages 目录
clean::
	@echo -e "\033[31m==>\033[0m Cleaning packages…"
	@rm -rf .theos packages

# 编译并自动安装
after-package::
	@echo -e "\033[32m==>\033[0m Packaging complete."
	@if [ "$(GITHUB_ACTIONS)" != "true" ] && [ "$(INSTALL)" = "1" ]; then \
        DEB_FILE=$$(ls -t packages/*.deb | head -1); \
        PACKAGE_NAME=$$(basename "$$DEB_FILE" | cut -d'_' -f1); \
        echo -e "\033[34m==>\033[0m Installing $$PACKAGE_NAME to device…"; \
        ssh root@$(THEOS_DEVICE_IP) "rm -rf /tmp/$${PACKAGE_NAME}.deb"; \
        scp "$$DEB_FILE" root@$(THEOS_DEVICE_IP):/tmp/$${PACKAGE_NAME}.deb; \
        ssh root@$(THEOS_DEVICE_IP) "dpkg -i --force-overwrite /tmp/$${PACKAGE_NAME}.deb && rm -f /tmp/$${PACKAGE_NAME}.deb"; \
	else \
        echo -e "\033[33m==>\033[0m Skipping installation (GitHub Actions environment or INSTALL!=1)"; \
	fi
