ifdef BREW_CLANG
TARGET := iphone:$(BREW_CLANG):16.5:14.0
else
TARGET := iphone:clang:16.5:14.0
endif

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = CoreLib
CoreLib_FILES = $(wildcard *.mm *.m)
CoreLib_CFLAGS = -fobjc-arc \
  -Wno-unused-function -Wno-deprecated-declarations \
  -Wno-unused-variable -Wno-unused-value \
  -Wno-module-import-in-extern-c -Wno-unused-but-set-variable \
  -I../include -include ../hud-prefix.pch
CoreLib_CCFLAGS = -std=c++14 \
  -DNOTIFY_LAUNCHED_HUD=\"ch.xxtou.notification.hud.launched\" \
  -DNOTIFY_DISMISSAL_HUD=\"ch.xxtou.notification.hud.dismissal\" \
  -DNOTIFY_RELOAD_HUD=\"ch.xxtou.notification.hud.reload\" \
  -DNOTIFY_RELOAD_APP=\"ch.xxtou.notification.app.reload\"

include $(THEOS_MAKE_PATH)/library.mk
