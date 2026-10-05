TARGET = iphone:clang:latest:15.0
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1
VERSION = 7.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FPSOverlay

FPSOverlay_FILES = FPSOverlay.m
FPSOverlay_FRAMEWORKS = UIKit QuartzCore

.PHONY: all build release

all: build

build:
	@echo "[FPSOverlay] Building tweak..."
	$(MAKE) FINALPACKAGE=1

release: build
	@mkdir -p release
	@cp -f .theos/obj/arm64/FPSOverlay.dylib release/FPSOverlay.dylib
	@ls -lh release/FPSOverlay.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
