export TARGET = iphone:clang:latest:16.0
export ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FPSOverlay
FPSOverlay_FILES = FPSOverlay.m
FPSOverlay_FRAMEWORKS = UIKit QuartzCore
FPSOverlay_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/tweak.mk
