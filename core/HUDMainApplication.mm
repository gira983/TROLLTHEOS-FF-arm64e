#import <cstddef>
#import <cstdlib>
#import <dlfcn.h>
#import <spawn.h>
#import <unistd.h>
#import <notify.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <sys/wait.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <mach/vm_param.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "HUDPresetPosition.h"
#import "../esp/MenuView/esp.h"
#import "UIAutoRotatingWindow.h"

// Forward declarations for private classes
@interface SBSAccessibilityWindowHostingController : NSObject
- (void)registerWindowWithContextID:(unsigned int)contextID atLevel:(double)level;
@end

@interface UIWindow (Private)
- (unsigned int)_contextId;
@end

@interface HUDRootViewController : UIViewController
@end

@implementation HUDRootViewController
- (BOOL)_canShowWhileLocked { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = YES;
    
    // Создаем и добавляем MenuView
    MenuView *menu = [[MenuView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:menu];
}
@end

@interface HUDMainWindow : UIAutoRotatingWindow
@end

@implementation HUDMainWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = 10000000;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.hidden = NO;
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Ручной обход для arm64e
    UIView *hit = [self customHitTest:self.rootViewController.view point:point event:event];
    return hit;
}

- (UIView *)customHitTest:(UIView *)view point:(CGPoint)point event:(UIEvent *)event {
    if (!view || view.hidden || view.alpha < 0.01 || !view.userInteractionEnabled) return nil;

    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        CGPoint p = [view convertPoint:point toView:subview];
        UIView *hit = [self customHitTest:subview point:p event:event];
        if (hit) return hit;
    }

    if ([view pointInside:point withEvent:event]) {
        // Если это кнопка или свитч или само меню
        if ([view isKindOfClass:[UIButton class]] || [view isKindOfClass:[UISwitch class]] || [view isKindOfClass:[UISlider class]] || [view isKindOfClass:[MenuView class]]) {
            return view;
        }
        // Проверка по имени класса для MenuView subviews
        if ([NSStringFromClass([view class]) containsString:@"MenuView"]) return view;
    }
    return nil;
}
@end

@interface HUDMainApplication : UIApplication <UIApplicationDelegate>
@property (nonatomic, strong) HUDMainWindow *window;
@end

@implementation HUDMainApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    self.window = [[HUDMainWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[HUDRootViewController alloc] init];
    [self.window makeKeyAndVisible];
    
    // Регистрация в системе
    unsigned int contextId = [self.window _contextId];
    if (contextId) {
        Class hostingClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
        if (hostingClass) {
            id hostingController = [[hostingClass alloc] init];
            [hostingController registerWindowWithContextID:contextId atLevel:10000000];
        }
    }
}

@end

// Main entry point for the HUD process
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, NSStringFromClass([HUDMainApplication class]), NSStringFromClass([HUDMainApplication class]));
    }
}
