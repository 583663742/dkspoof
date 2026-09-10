# DKSpoof v2 - DingTalk 虚拟定位（三指双击 + 地图选点）
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = DingTalk

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = dkspoof

dkspoof_FILES = Tweak.xm SpoofPanel.mm
dkspoof_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -Wno-arc-retain-cycles -Wno-unused-function -nostdinc++ -isystem "$(THEOS_SDK_PATH)/usr/include/c++/v1"
dkspoof_FRAMEWORKS = CoreLocation MapKit UIKit
dkspoof_LDFLAGS = -L"$(THEOS_SDK_PATH)/usr/lib" -F"$(THEOS_VENDOR_LIBRARY_PATH)/iphone" -framework CydiaSubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
