ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := Fryzz
include $(THEOS)/makefiles/common.mk

IS_NEW_ABI := 1
APPLICATION_NAME := Fryzz
PACKAGE_NAME := xyris
Fryzz_USE_MODULES := 0

# HUDApp.mm исключён из Fryzz_FILES и компилируется в core/ subproject без Obscura
# (Obscura вызывает segfault Apple clang 17 на этом файле)
CORE_FILES := $(filter-out core/HUDApp.mm,$(wildcard core/*.mm core/*.m))
Fryzz_FILES += $(CORE_FILES)
Fryzz_FILES += $(wildcard esp/lib/*.mm) $(wildcard esp/lib/*.cpp)
Fryzz_FILES += $(wildcard esp/MenuView/*.cpp) $(wildcard esp/MenuView/*.mm)
Fryzz_FILES += platform_stub.c
platform_stub.c_CFLAGS = -fobjc-arc

# Subproject core/ компилирует HUDApp.mm без Obscura и даёт libHUDAppLib.a
SUBPROJECTS += core
Fryzz_LIBRARIES += HUDAppLib

# ════════════════════════════════════════════════════════════════════════
# Obscura — только ENC_FULL, без ENC_FULL_TIMES/ENC_DEEP_INLINE
# ════════════════════════════════════════════════════════════════════════
ifdef OBSCURA_LIB
OBSCURA_FLAGS := \
  -fpass-plugin=$(OBSCURA_LIB)          \
  -DENC_FULL                            \
  -I$(OBSCURA_INCLUDE)                  \
  -include $(OBSCURA_INCLUDE)/config.h
else
OBSCURA_FLAGS :=
endif

# ════════════════════════════════════════════════════════════════════════
# Компилятор — системный clang (Xcode)
# ════════════════════════════════════════════════════════════════════════
TARGET := iphone:clang:16.5:14.0
THEOS_IOS_SDK := $(wildcard $(THEOS)/sdks/iPhoneOS*.sdk)
ifneq ($(THEOS_IOS_SDK),)
Fryzz_LDFLAGS += -F$(THEOS_IOS_SDK)/System/Library/Frameworks
Fryzz_LDFLAGS += -F$(THEOS_IOS_SDK)/System/Library/PrivateFrameworks
endif

Fryzz_CFLAGS += -fobjc-arc                          \
  -Wno-unused-function                               \
  -Wno-deprecated-declarations                       \
  -Wno-unused-variable                               \
  -Wno-unused-value                                  \
  -Wno-module-import-in-extern-c                     \
  -Wno-unused-but-set-variable
Fryzz_CFLAGS += -Iinclude
Fryzz_CFLAGS += -include hud-prefix.pch
Fryzz_CFLAGS += $(OBSCURA_FLAGS)

Fryzz_CCFLAGS += -std=c++14
Fryzz_CCFLAGS += -DNOTIFY_LAUNCHED_HUD=\"ch.xxtou.notification.hud.launched\"
Fryzz_CCFLAGS += -DNOTIFY_DISMISSAL_HUD=\"ch.xxtou.notification.hud.dismissal\"
Fryzz_CCFLAGS += -DNOTIFY_RELOAD_HUD=\"ch.xxtou.notification.hud.reload\"
Fryzz_CCFLAGS += -DNOTIFY_RELOAD_APP=\"ch.xxtou.notification.app.reload\"

Fryzz_FRAMEWORKS         += CoreGraphics QuartzCore UIKit Foundation
Fryzz_PRIVATE_FRAMEWORKS += GraphicsServices IOKit SpringBoardServices
Fryzz_CODESIGN_FLAGS     += -Sent.plist

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@rm -rf packages Payload
	@mkdir -p Payload packages
	@cp -rp $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app Payload
	@cd . && zip -qr $(APPLICATION_NAME).tipa Payload
	@mv $(APPLICATION_NAME).tipa packages/$(APPLICATION_NAME).tipa
	@rm -rf Payload
