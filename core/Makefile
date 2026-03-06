# Subproject для компиляции HUDApp.mm без Obscura плагина
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = HUDAppLib
HUDAppLib_FILES = HUDApp.mm
HUDAppLib_CFLAGS = -fobjc-arc \
  -Wno-unused-function -Wno-deprecated-declarations \
  -Wno-unused-variable -Wno-unused-value \
  -Wno-module-import-in-extern-c -Wno-unused-but-set-variable \
  -I../include -include ../hud-prefix.pch
HUDAppLib_CCFLAGS = -std=c++14 \
  -DNOTIFY_LAUNCHED_HUD=\"ch.xxtou.notification.hud.launched\" \
  -DNOTIFY_DISMISSAL_HUD=\"ch.xxtou.notification.hud.dismissal\" \
  -DNOTIFY_RELOAD_HUD=\"ch.xxtou.notification.hud.reload\" \
  -DNOTIFY_RELOAD_APP=\"ch.xxtou.notification.app.reload\"

include $(THEOS_MAKE_PATH)/library.mk
