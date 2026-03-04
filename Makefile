ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := Fryzz
include $(THEOS)/makefiles/common.mk

IS_NEW_ABI := 1
APPLICATION_NAME := Fryzz
PACKAGE_NAME := xyris
Fryzz_USE_MODULES := 0

Fryzz_FILES += $(wildcard core/*.mm core/*.m)
Fryzz_FILES += $(wildcard esp/lib/*.mm) $(wildcard esp/lib/*.cpp)
Fryzz_FILES += $(wildcard esp/MenuView/*.cpp) $(wildcard esp/MenuView/*.mm)

# platform_stub.c — без плагинов, чистая компиляция
Fryzz_FILES += platform_stub.c
platform_stub.c_CFLAGS = -fobjc-arc

# ════════════════════════════════════════════════════════════════════════
# Obscura флаги
# ВАЖНО: глобальные флаги БЕЗ L2G_ENABLE — он включается только
# для HUDApp.mm через per-file override ниже.
# Причина: Theos per-file _CFLAGS добавляются К глобальным, не заменяют.
# L2G на HUDMainApplication.mm убивает runner по OOM (Exit 137).
# ════════════════════════════════════════════════════════════════════════
ifdef OBSCURA_LIB
OBSCURA_FLAGS := \
  -fpass-plugin=$(OBSCURA_LIB)          \
  -DENC_FULL                            \
  -DENC_FULL_TIMES=2                    \
  -DENC_DEEP_INLINE                     \
  -I$(OBSCURA_INCLUDE)                  \
  -include $(OBSCURA_INCLUDE)/config.h
else
OBSCURA_FLAGS :=
endif

# ════════════════════════════════════════════════════════════════════════
# Hikari
# ════════════════════════════════════════════════════════════════════════
ifdef HIKARI_LIB
HIKARI_FLAGS := -fpass-plugin=$(HIKARI_LIB)
export OLLVM_POLICY := $(CURDIR)/policy.json
else
HIKARI_FLAGS :=
endif

# ════════════════════════════════════════════════════════════════════════
# Компилятор
# ════════════════════════════════════════════════════════════════════════
ifdef LLVM_BIN
THEOS_PLATFORM_CC  := $(LLVM_BIN)/clang
THEOS_PLATFORM_CXX := $(LLVM_BIN)/clang++
TARGET := iphone:$(LLVM_BIN)/clang:16.5:14.0
# brew clang не передаёт -isysroot линковщику автоматически.
# Явно указываем sysroot и путь к frameworks через LDFLAGS.
THEOS_SDK_PATH := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
ifneq ($(THEOS_SDK_PATH),)
Fryzz_LDFLAGS += -isysroot $(THEOS_SDK_PATH)
Fryzz_LDFLAGS += -F$(THEOS_SDK_PATH)/System/Library/Frameworks
Fryzz_LDFLAGS += -F$(THEOS_SDK_PATH)/System/Library/PrivateFrameworks
endif
else
TARGET := iphone:clang:16.5:14.0
endif

# ════════════════════════════════════════════════════════════════════════
# Глобальные флаги (без L2G_ENABLE)
# ════════════════════════════════════════════════════════════════════════
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
Fryzz_CFLAGS += $(HIKARI_FLAGS)

# ════════════════════════════════════════════════════════════════════════
# Per-file: HUDApp.mm получает L2G_ENABLE дополнительно
# На этом файле L2G успешно отработал (33k промоций, 765s, без OOM)
# ════════════════════════════════════════════════════════════════════════
ifdef OBSCURA_LIB
core/HUDApp.mm_CFLAGS = -DL2G_ENABLE
endif

Fryzz_CCFLAGS += -std=c++14
Fryzz_CCFLAGS += -DNOTIFY_LAUNCHED_HUD=\"ch.xxtou.notification.hud.launched\"
Fryzz_CCFLAGS += -DNOTIFY_DISMISSAL_HUD=\"ch.xxtou.notification.hud.dismissal\"
Fryzz_CCFLAGS += -DNOTIFY_RELOAD_HUD=\"ch.xxtou.notification.hud.reload\"
Fryzz_CCFLAGS += -DNOTIFY_RELOAD_APP=\"ch.xxtou.notification.app.reload\"

Fryzz_FRAMEWORKS         += CoreGraphics QuartzCore UIKit Foundation
Fryzz_PRIVATE_FRAMEWORKS += BackBoardServices GraphicsServices IOKit SpringBoardServices
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
