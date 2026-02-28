ARCHS := arm64 arm64e
TARGET := iphone:clang:16.5:14.0

INSTALL_TARGET_PROCESSES := Fryzz

include $(THEOS)/makefiles/common.mk

IS_NEW_ABI := 1

APPLICATION_NAME := Xyris
PACKAGE_NAME := xyris

Xyris_USE_MODULES := 0
Xyris_FILES += platform_stub.c
Xyris_FILES += $(wildcard core/*.mm core/*.m)
Xyris_FILES += $(wildcard esp/lib/*.mm) $(wildcard esp/lib/*.cpp) $(wildcard esp/MenuView/*.cpp) $(wildcard esp/MenuView/*.mm)

Xyris_CFLAGS += -fobjc-arc \
-Wno-unused-function \
-Wno-deprecated-declarations \
-Wno-unused-variable \
-Wno-unused-value \
-Wno-module-import-in-extern-c \
-Wno-unused-but-set-variable

Xyris_CFLAGS += -Iinclude
Xyris_CFLAGS += -include hud-prefix.pch
# Xyris_CFLAGS += -I/usr/lib/llvm-16/lib/clang/16.0.0/include
# Xyris_CFLAGS += -resource-dir /usr/lib/llvm-16/lib/clang/16.0.0

Xyris_CCFLAGS += -std=c++14
# Xyris_CCFLAGS += -resource-dir /usr/lib/llvm-16/lib/clang/16.0.0
Xyris_CCFLAGS += -DNOTIFY_LAUNCHED_HUD=\"ch.xxtou.notification.hud.launched\"
Xyris_CCFLAGS += -DNOTIFY_DISMISSAL_HUD=\"ch.xxtou.notification.hud.dismissal\"
Xyris_CCFLAGS += -DNOTIFY_RELOAD_HUD=\"ch.xxtou.notification.hud.reload\"
Xyris_CCFLAGS += -DNOTIFY_RELOAD_APP=\"ch.xxtou.notification.app.reload\"

Xyris_FRAMEWORKS += CoreGraphics QuartzCore UIKit Foundation
Xyris_PRIVATE_FRAMEWORKS += BackBoardServices GraphicsServices IOKit SpringBoardServices

Xyris_CODESIGN_FLAGS += -Sent.plist

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@rm -rf packages Payload
	@mkdir -p Payload packages
	@cp -rp $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app Payload
	@cd . && zip -qr $(APPLICATION_NAME).tipa Payload
	@mv $(APPLICATION_NAME).tipa packages/$(APPLICATION_NAME).tipa
	@rm -rf Payload
