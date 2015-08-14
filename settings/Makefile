include theos/makefiles/common.mk

BUNDLE_NAME = AutoBrightness
AutoBrightness_FILES = AutoBrightness.mm ABSliderCell.mm
AutoBrightness_INSTALL_PATH = /Library/PreferenceBundles
AutoBrightness_FRAMEWORKS = UIKit CoreGraphics IOKit
AutoBrightness_PRIVATE_FRAMEWORKS = Preferences

CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/autobrightness.plist$(ECHO_END)
