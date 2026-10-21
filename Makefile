.DEFAULT_GOAL := package
TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
FINALPACKAGE := 1
DEBUG := 0
DEBUGFLAG :=
OPTFLAG := -O3
THEOS_PACKAGE_SCHEME ?= $(SCHEME)

include $(THEOS)/makefiles/common.mk

TARGET_DSYMUTIL :=
TWEAK_NAME := DYYY

DYYY_SOURCE_DIRS := src/Hooks src/Core src/Settings src/UI src/Support
DYYY_FILES := \
    src/Hooks/DYYY.xm \
    src/Hooks/DYYYABTestHook.xm \
    src/Hooks/DYYYLongPressPanel.xm \
    src/Hooks/DYYYLoginBypass.xm \
    src/Core/DYYYLoginBypassManager.m \
    src/Core/DYYYLoginRepairHooks.m \
    src/Core/DYYYManager.m \
    src/Core/DYYYUtils.m \
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
    src/UI/DYYYToast.m \
    src/Support/AWMSafeDispatchTimer.m \
    src/Support/CityManager.m
DYYY_CFLAGS := -fobjc-arc -w -flto=full $(addprefix -I,$(DYYY_SOURCE_DIRS))
DYYY_CCFLAGS := -std=gnu++26
$(foreach source,$(filter %.c %.m,$(DYYY_FILES)),$(eval $(source)_CFLAGS += -std=gnu23))
DYYY_LDFLAGS := -O3 -flto=full -Wl,-dead_strip -weak_framework AVFAudio
DYYY_FRAMEWORKS := CoreAudio PhotosUI
DYYY_LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS_MAKE_PATH)/tweak.mk
