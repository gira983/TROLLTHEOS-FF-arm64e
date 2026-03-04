ARCHS := arm64 arm64e
TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES := Fryzz
include $(THEOS)/makefiles/common.mk

IS_NEW_ABI := 1
APPLICATION_NAME := Fryzz
PACKAGE_NAME := xyris
Fryzz_USE_MODULES := 0

Fryzz_FILES += platform_stub.c
Fryzz_FILES += $(wildcard core/*.mm core/*.m)
Fryzz_FILES += $(wildcard esp/lib/*.mm) $(wildcard esp/lib/*.cpp)
Fryzz_FILES += $(wildcard esp/MenuView/*.cpp) $(wildcard esp/MenuView/*.mm)

# ════════════════════════════════════════════════════════════════════════
# УРОВЕНЬ 1 — Obscura
# Шифрует все числовые константы, офсеты и строки на уровне LLVM IR
# Переменные OBSCURA_LIB / OBSCURA_INCLUDE задаются из build.yml
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
else
OBSCURA_FLAGS :=
endif

# ════════════════════════════════════════════════════════════════════════
# УРОВЕНЬ 2 — Hikari (ollvm-pass)
# Обфускация control flow, строк, ObjC классов
#
# Подход: xcode_cc.sh заменяет CC — он:
#   1. Компилирует исходник в LLVM bitcode (clang -emit-llvm)
#   2. Запускает opt с Hikari.dylib (применяет все passes)
#   3. Компилирует bitcode обратно в .o (clang -c)
#
# Это лучший способ для arm64e — Apple clang остаётся в pipeline
# Переменные HIKARI_LIB / HIKARI_OPT задаются из build.yml
# ════════════════════════════════════════════════════════════════════════
ifdef HIKARI_LIB
export OLLVM_PASS    := $(HIKARI_LIB)
export OLLVM_OPT     := $(HIKARI_OPT)
export OLLVM_POLICY  := $(CURDIR)/policy.json
CC  := $(HOME)/xcode_cc.sh
CXX := $(HOME)/xcode_cc.sh
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
