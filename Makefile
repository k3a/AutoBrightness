GO_EASY_ON_ME=1

include theos/makefiles/common.mk
export TARGET=iphone:latest:5.0
export ARCHS = armv7 arm64

SUBPROJECTS = autobrightnesssbsettingstoggle

TOOL_NAME = ambid
ambid_FILES = main.m
ambid_FRAMEWORKS = IOKit
# ambid_LDFLAGS = -lIOKit
ambid_CODESIGN_FLAGS = -Sentitlements.xml
LOCAL_INSTALL_PATH = "/usr/libexec/"

include $(THEOS_MAKE_PATH)/tool.mk
include $(FW_MAKEDIR)/aggregate.mk

test: distclean package install
	ssh root@ufoxy "launchctl unload /Library/LaunchDaemons/me.k3a.ambid.plist && launchctl load /Library/LaunchDaemons/me.k3a.ambid.plist"

distclean:
	rm *.deb || true
