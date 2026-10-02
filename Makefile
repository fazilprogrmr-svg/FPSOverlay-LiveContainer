TARGET = iphone:clang:latest:15.0
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FPSOverlay

FPSOverlay_FILES = FPSOverlay.m
FPSOverlay_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
