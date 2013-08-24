GO_EASY_ON_ME=1

include theos/makefiles/common.mk
export TARGET=iphone:latest:5.0
export ARCHS = armv7

SUBPROJECTS = autobrightnesssbsettingstoggle

TOOL_NAME = ambid
ambid_FILES = main.m
#ambid_FRAMEWORKS = UIKit
ambid_LDFLAGS = -lIOKit
LOCAL_INSTALL_PATH = "/usr/libexec/"

include $(THEOS_MAKE_PATH)/tool.mk
include $(FW_MAKEDIR)/aggregate.mk

test: distclean package install
	ssh root@ufoxy "launchctl unload /System/Library/LaunchDaemons/me.k3a.ambid.plist && launchctl load /System/Library/LaunchDaemons/me.k3a.ambid.plist"

distclean:
	rm *.deb || true
