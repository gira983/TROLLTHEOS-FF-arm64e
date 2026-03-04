ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := Fryzz
include $(THEOS)/makefiles/common.mk

IS_NEW_ABI := 1
APPLICATION_NAME := Fryzz
PACKAGE_NAME := xyris
Fryzz_USE_MODULES := 0

# platform_stub.c компилируется БЕЗ обфускации — отдельно
Fryzz_FILES += $(wildcard core/*.mm core/*.m)
Fryzz_FILES += $(wildcard esp/lib/*.mm) $(wildcard esp/lib/*.cpp)
Fryzz_FILES += $(wildcard esp/MenuView/*.cpp) $(wildcard esp/MenuView/*.mm)

# platform_stub.c — без плагинов, чистая компиляция
Fryzz_FILES += platform_stub.c
platform_stub.c_CFLAGS = -fobjc-arc

# ════════════════════════════════════════════════════════════════════════
# УРОВЕНЬ 1 — Obscura: шифрование констант/офсетов
# ════════════════════════════════════════════════════════════════════════
ifdef OBSCURA_LIB
OBSCURA_FLAGS := \
  -fpass-plugin=$(OBSCURA_LIB)          \
  -DENC_FULL                            \
  -DENC_FULL_TIMES=2                    \
  -DENC_DEEP_INLINE                     \
  -DL2G_ENABLE                          \
  -I$(OBSCURA_INCLUDE)                  \
  -include $(OBSCURA_INCLUDE)/config.h

# HUDMainApplication.mm — отдельные флаги Obscura БЕЗ L2G и с 1 итерацией
# L2G_ENABLE продвинул 33k+ глобалов на HUDApp.mm и убивает OOM на большем файле
OBSCURA_FLAGS_LIGHT := \
  -fpass-plugin=$(OBSCURA_LIB)          \
  -DENC_FULL                            \
  -DENC_FULL_TIMES=1                    \
  -DENC_DEEP_INLINE                     \
  -I$(OBSCURA_INCLUDE)                  \
  -include $(OBSCURA_INCLUDE)/config.h
else
OBSCURA_FLAGS :=
OBSCURA_FLAGS_LIGHT :=
endif

# ════════════════════════════════════════════════════════════════════════
# УРОВЕНЬ 2 — Hikari: обфускация control flow, строк, ObjC классов
# ════════════════════════════════════════════════════════════════════════
ifdef HIKARI_LIB
HIKARI_FLAGS := -fpass-plugin=$(HIKARI_LIB)
export OLLVM_POLICY := $(CURDIR)/policy.json
else
HIKARI_FLAGS :=
endif

# ════════════════════════════════════════════════════════════════════════
# Theos использует свой clang — задаём его через TARGET
# brew llvm@17 совместим с обоими плагинами без segfault
# ════════════════════════════════════════════════════════════════════════
ifdef LLVM_BIN
# Переопределяем компилятор Theos через переменную которую он реально читает
THEOS_PLATFORM_CC  := $(LLVM_BIN)/clang
THEOS_PLATFORM_CXX := $(LLVM_BIN)/clang++
TARGET := iphone:$(LLVM_BIN)/clang:16.5:14.0
else
TARGET := iphone:clang:16.5:14.0
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
Fryzz_CFLAGS += $(HIKARI_FLAGS)

# ════════════════════════════════════════════════════════════════════════
# Per-file overrides: HUDMainApplication.mm — облегчённая обфускация
# Без L2G_ENABLE (главная причина OOM) + 1 итерация вместо 2
# ════════════════════════════════════════════════════════════════════════
core/HUDMainApplication.mm_CFLAGS = \
  -fobjc-arc                                         \
  -Wno-unused-function                               \
  -Wno-deprecated-declarations                       \
  -Wno-unused-variable                               \
  -Wno-unused-value                                  \
  -Wno-module-import-in-extern-c                     \
  -Wno-unused-but-set-variable                       \
  -Iinclude                                          \
  -include hud-prefix.pch                            \
  $(OBSCURA_FLAGS_LIGHT)                             \
  $(HIKARI_FLAGS)

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
