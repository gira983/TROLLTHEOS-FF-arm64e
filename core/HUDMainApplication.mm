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

// Forward declarations for private classes to fix compilation errors
@interface UIEventDispatcher : NSObject
- (void)_installEventRunLoopSources:(CFRunLoopRef)runLoop;
@end

@interface UIEventFetcher : NSObject
- (void)setEventFetcherSink:(id)sink;
@end

@interface SBSAccessibilityWindowHostingController : NSObject
- (void)registerWindowWithContextID:(unsigned int)contextID atLevel:(double)level;
@end

@interface FBSOrientationUpdate : NSObject
@property (nonatomic, readonly) long long orientation;
@property (nonatomic, readonly) double duration;
@end

@interface FBSOrientationObserver : NSObject
- (void)setHandler:(void (^)(FBSOrientationUpdate *))handler;
- (void)invalidate;
@end

@interface UIApplication (Private)
- (void)terminateWithSuccess;
@end

@interface UIWindow (Private)
- (unsigned int)_contextId;
@end

#define SPAWN_AS_ROOT 0

extern "C" char **environ;

#if SPAWN_AS_ROOT
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern "C" int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern "C" int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern "C" int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);
#endif

OBJC_EXTERN BOOL IsHUDEnabled(void);
BOOL IsHUDEnabled(void)
{
    static char *executablePath = NULL;
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    executablePath = (char *)calloc(1, executablePathSize);
    _NSGetExecutablePath(executablePath, &executablePathSize);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if SPAWN_AS_ROOT
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    pid_t task_pid;
    const char *args[] = { executablePath, "-check", NULL };
    posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
    posix_spawnattr_destroy(&attr);

    int status;
    do {
        if (waitpid(task_pid, &status, 0) != -1) {}
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    return WEXITSTATUS(status) != 0;
}

OBJC_EXTERN void SetHUDEnabled(BOOL isEnabled);
void SetHUDEnabled(BOOL isEnabled)
{
#ifdef NOTIFY_DISMISSAL_HUD
    notify_post(NOTIFY_DISMISSAL_HUD);
#endif

    static char *executablePath = NULL;
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    executablePath = (char *)calloc(1, executablePathSize);
    _NSGetExecutablePath(executablePath, &executablePathSize);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if SPAWN_AS_ROOT
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    if (isEnabled)
    {
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);

        pid_t task_pid;
        const char *args[] = { executablePath, "-hud", NULL };
        posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        posix_spawnattr_destroy(&attr);
    }
    else
    {
        [NSThread sleepForTimeInterval:0.25];

        pid_t task_pid;
        const char *args[] = { executablePath, "-exit", NULL };
        posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        posix_spawnattr_destroy(&attr);
        
        int status;
        do {
            if (waitpid(task_pid, &status, 0) != -1) {}
        } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    }
}

#define KILOBITS 1000
#define MEGABITS 1000000
#define GIGABITS 1000000000
#define KILOBYTES (1 << 10)
#define MEGABYTES (1 << 20)
#define GIGABYTES (1 << 30)
#define UPDATE_INTERVAL 1.0
#define SHOW_ALWAYS 1
#define INLINE_SEPARATOR "\t"
#define IDLE_INTERVAL 3.0
static double FONT_SIZE = 8.0;
static uint8_t DATAUNIT = 0;
static uint8_t SHOW_UPLOAD_SPEED = 1;
static uint8_t SHOW_DOWNLOAD_SPEED = 1;
static uint8_t SHOW_DOWNLOAD_SPEED_FIRST = 1;
static uint8_t SHOW_SECOND_SPEED_IN_NEW_LINE = 0;
static const char *UPLOAD_PREFIX = "▲";
static const char *DOWNLOAD_PREFIX = "▼";

typedef struct {
    uint64_t inputBytes;
    uint64_t outputBytes;
} UpDownBytes;

static NSString* formattedSpeed(uint64_t bytes, BOOL isFocused)
{
    if (isFocused)
    {
        if (0 == DATAUNIT)
        {
            if (bytes < KILOBYTES) return @"0 KB";
            else if (bytes < MEGABYTES) return [NSString stringWithFormat:@"%.0f KB", (double)bytes / KILOBYTES];
            else if (bytes < GIGABYTES) return [NSString stringWithFormat:@"%.2f MB", (double)bytes / MEGABYTES];
            else return [NSString stringWithFormat:@"%.2f GB", (double)bytes / GIGABYTES];
        }
        else
        {
            if (bytes < KILOBITS) return @"0 Kb";
            else if (bytes < MEGABITS) return [NSString stringWithFormat:@"%.0f Kb", (double)bytes / KILOBITS];
            else if (bytes < GIGABITS) return [NSString stringWithFormat:@"%.2f Mb", (double)bytes / MEGABITS];
            else return [NSString stringWithFormat:@"%.2f Gb", (double)bytes / GIGABITS];
        }
    }
    else {
        if (0 == DATAUNIT)
        {
            if (bytes < KILOBYTES) return @"0 KB/s";
            else if (bytes < MEGABYTES) return [NSString stringWithFormat:@"%.0f KB/s", (double)bytes / KILOBYTES];
            else if (bytes < GIGABYTES) return [NSString stringWithFormat:@"%.2f MB/s", (double)bytes / MEGABYTES];
            else return [NSString stringWithFormat:@"%.2f GB/s", (double)bytes / GIGABYTES];
        }
        else
        {
            if (bytes < KILOBITS) return @"0 Kb/s";
            else if (bytes < MEGABITS) return [NSString stringWithFormat:@"%.0f Kb/s", (double)bytes / KILOBITS];
            else if (bytes < GIGABITS) return [NSString stringWithFormat:@"%.2f Mb/s", (double)bytes / MEGABITS];
            else return [NSString stringWithFormat:@"%.2f Gb/s", (double)bytes / GIGABITS];
        }
    }
}

static UpDownBytes getUpDownBytes()
{
    struct ifaddrs *ifa_list = 0, *ifa;
    UpDownBytes upDownBytes;
    upDownBytes.inputBytes = 0;
    upDownBytes.outputBytes = 0;
    if (getifaddrs(&ifa_list) == -1) return upDownBytes;
    for (ifa = ifa_list; ifa; ifa = ifa->ifa_next)
    {
        if (ifa->ifa_name == NULL || ifa->ifa_addr == NULL || ifa->ifa_data == NULL) continue;
        if (AF_LINK != ifa->ifa_addr->sa_family) continue;
        if (!(ifa->ifa_flags & IFF_UP) && !(ifa->ifa_flags & IFF_RUNNING)) continue;
        if (strncmp(ifa->ifa_name, "en", 2) && strncmp(ifa->ifa_name, "pdp_ip", 6)) continue;
        struct if_data *if_data = (struct if_data *)ifa->ifa_data;
        upDownBytes.inputBytes += if_data->ifi_ibytes;
        upDownBytes.outputBytes += if_data->ifi_obytes;
    }
    freeifaddrs(ifa_list);
    return upDownBytes;
}

static BOOL shouldUpdateSpeedLabel;
static uint64_t prevOutputBytes = 0, prevInputBytes = 0;
static NSAttributedString *attributedUploadPrefix = nil;
static NSAttributedString *attributedDownloadPrefix = nil;
static NSAttributedString *attributedInlineSeparator = nil;
static NSAttributedString *attributedLineSeparator = nil;

static NSAttributedString* formattedAttributedString(BOOL isFocused)
{
    @autoreleasepool
    {
        if (!attributedUploadPrefix)
            attributedUploadPrefix = [[NSAttributedString alloc] initWithString:[[NSString stringWithUTF8String:UPLOAD_PREFIX] stringByAppendingString:@" "] attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:FONT_SIZE]}];
        if (!attributedDownloadPrefix)
            attributedDownloadPrefix = [[NSAttributedString alloc] initWithString:[[NSString stringWithUTF8String:DOWNLOAD_PREFIX] stringByAppendingString:@" "] attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:FONT_SIZE]}];
        if (!attributedInlineSeparator)
            attributedInlineSeparator = [[NSAttributedString alloc] initWithString:[NSString stringWithUTF8String:INLINE_SEPARATOR] attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}];
        if (!attributedLineSeparator)
            attributedLineSeparator = [[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}];

        NSMutableAttributedString* mutableString = [[NSMutableAttributedString alloc] init];
        UpDownBytes upDownBytes = getUpDownBytes();
        uint64_t upDiff, downDiff;
        if (isFocused) { upDiff = upDownBytes.outputBytes; downDiff = upDownBytes.inputBytes; }
        else {
            upDiff = (upDownBytes.outputBytes > prevOutputBytes) ? upDownBytes.outputBytes - prevOutputBytes : 0;
            downDiff = (upDownBytes.inputBytes > prevInputBytes) ? upDownBytes.inputBytes - prevInputBytes : 0;
        }
        prevOutputBytes = upDownBytes.outputBytes;
        prevInputBytes = upDownBytes.inputBytes;
        if (!SHOW_ALWAYS && (upDiff < 2 * KILOBYTES && downDiff < 2 * KILOBYTES)) { shouldUpdateSpeedLabel = NO; return nil; }
        else shouldUpdateSpeedLabel = YES;
        if (DATAUNIT == 1) { upDiff *= 8; downDiff *= 8; }
        if (SHOW_DOWNLOAD_SPEED_FIRST) {
            if (SHOW_DOWNLOAD_SPEED) {
                [mutableString appendAttributedString:attributedDownloadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(downDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
            if (SHOW_UPLOAD_SPEED) {
                if (SHOW_DOWNLOAD_SPEED) [mutableString appendAttributedString:(SHOW_SECOND_SPEED_IN_NEW_LINE ? attributedLineSeparator : attributedInlineSeparator)];
                [mutableString appendAttributedString:attributedUploadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(upDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
        } else {
            if (SHOW_UPLOAD_SPEED) {
                [mutableString appendAttributedString:attributedUploadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(upDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
            if (SHOW_DOWNLOAD_SPEED) {
                if (SHOW_UPLOAD_SPEED) [mutableString appendAttributedString:(SHOW_SECOND_SPEED_IN_NEW_LINE ? attributedLineSeparator : attributedInlineSeparator)];
                [mutableString appendAttributedString:attributedDownloadPrefix];
                [mutableString appendAttributedString:[[NSAttributedString alloc] initWithString:formattedSpeed(downDiff, isFocused) attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:FONT_SIZE]}]];
            }
        }
        return mutableString;
    }
}

#pragma mark - HUDRootViewController
@interface HUDRootViewController : UIViewController
- (void)resetLoopTimer;
- (void)stopLoopTimer;
@end

#pragma mark - HUDMainWindow
#import "UIAutoRotatingWindow.h"
@interface HUDMainWindow : UIAutoRotatingWindow
@end

#pragma mark - Darwin Notification
#define NOTIFY_UI_LOCKCOMPLETE "com.apple.springboard.lockcomplete"
#define NOTIFY_UI_LOCKSTATE    "com.apple.springboard.lockstate"
#define NOTIFY_LS_APP_CHANGED  "com.apple.LaunchServices.ApplicationsChanged"
#import "LSApplicationProxy.h"
#import "LSApplicationWorkspace.h"

static void LaunchServicesApplicationStateChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    BOOL isAppInstalled = NO;
    for (LSApplicationProxy *app in [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] allApplications]) {
        if ([app.applicationIdentifier isEqualToString:@"ch.xxtou.hudapp"]) { isAppInstalled = YES; break; }
    }
    if (!isAppInstalled) { [(UIApplication *)[UIApplication sharedApplication] terminateWithSuccess]; }
}

#import "SpringBoardServices.h"
static void SpringBoardLockStatusChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    HUDRootViewController *rootViewController = (__bridge HUDRootViewController *)observer;
    NSString *lockState = (__bridge NSString *)name;
    if ([lockState isEqualToString:@NOTIFY_UI_LOCKCOMPLETE]) { [rootViewController stopLoopTimer]; [rootViewController.view setHidden:YES]; }
    else if ([lockState isEqualToString:@NOTIFY_UI_LOCKSTATE]) {
        mach_port_t sbsPort = SBSSpringBoardServerPort();
        if (sbsPort == MACH_PORT_NULL) return;
        BOOL isLocked, isPasscodeSet;
        SBGetScreenLockStatus(sbsPort, &isLocked, &isPasscodeSet);
        if (!isLocked) { [rootViewController.view setHidden:NO]; [rootViewController resetLoopTimer]; }
        else { [rootViewController stopLoopTimer]; [rootViewController.view setHidden:YES]; }
    }
}

#pragma mark - HUDMainApplication
#import <pthread.h>
#import <mach/mach.h>
#import "pac_helper.h"

@interface HUDMainApplication : UIApplication
@end

@implementation HUDMainApplication
- (instancetype)init
{
    if (self = [super init])
    {
        notify_post(NOTIFY_LAUNCHED_HUD);
#ifdef NOTIFY_DISMISSAL_HUD
        {
            int token;
            notify_register_dispatch(NOTIFY_DISMISSAL_HUD, &token, dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);
                [UIView animateWithDuration:0.25f animations:^{ [[self.windows firstObject] setAlpha:0.0]; } completion:^(BOOL finished) { [self terminateWithSuccess]; }];
            });
        }
#endif
        do {
            UIEventDispatcher *dispatcher = (UIEventDispatcher *)[self valueForKey:@"eventDispatcher"];
            if (!dispatcher) break;
            if ([dispatcher respondsToSelector:@selector(_installEventRunLoopSources:)]) { [dispatcher _installEventRunLoopSources:CFRunLoopGetMain()]; }
            else {
                IMP runMethodIMP = class_getMethodImplementation([self class], @selector(_run));
                if (!runMethodIMP) break;
                uint32_t *runMethodPtr = (uint32_t *)make_sym_readable((void *)runMethodIMP);
                void (*orig_UIEventDispatcher__installEventRunLoopSources_)(id, SEL, CFRunLoopRef) = NULL;
                for (int i = 0; i < 0x140; i++) {
                    if (runMethodPtr[i] != 0xaa0003e2 || (runMethodPtr[i + 1] & 0xff000000) != 0xaa000000) continue;
                    uint32_t blInst = runMethodPtr[i + 2];
                    uint32_t *blInstPtr = &runMethodPtr[i + 2];
                    if ((blInst & 0xfc000000) != 0x94000000) continue;
                    int32_t blOffset = blInst & 0x03ffffff;
                    if (blOffset & 0x02000000) blOffset |= 0xfc000000;
                    blOffset <<= 2;
                    uint64_t blAddr = (uint64_t)blInstPtr + blOffset;
                    uint32_t cbzInst = *((uint32_t *)make_sym_readable((void *)blAddr));
                    if ((cbzInst & 0xff000000) != 0xb4000000) continue;
                    orig_UIEventDispatcher__installEventRunLoopSources_ = (void (*)(id, SEL, CFRunLoopRef))make_sym_callable((void *)blAddr);
                }
                if (!orig_UIEventDispatcher__installEventRunLoopSources_) break;
                orig_UIEventDispatcher__installEventRunLoopSources_(dispatcher, @selector(_installEventRunLoopSources:), CFRunLoopGetMain());
            }
            UIEventFetcher *fetcher = [[objc_getClass("UIEventFetcher") alloc] init];
            [dispatcher setValue:fetcher forKey:@"eventDispatcher"];
            if ([fetcher respondsToSelector:@selector(setEventFetcherSink:)]) [fetcher setEventFetcherSink:dispatcher];
            else [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
            [self setValue:fetcher forKey:@"eventFetcher"];
        } while (NO);
    }
    return self;
}
@end

#pragma mark - HUDMainApplicationDelegate
@interface HUDMainApplicationDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HUDMainApplicationDelegate {
    HUDRootViewController *_rootViewController;
    id _windowHostingController;
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    _rootViewController = [[HUDRootViewController alloc] init];
    self.window = [[HUDMainWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window setRootViewController:_rootViewController];
    [self.window setWindowLevel:10000010.0];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];
    _windowHostingController = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    unsigned int _contextId = [self.window _contextId];
    double windowLevel = [self.window windowLevel];
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_windowHostingController];
    [invocation setSelector:NSSelectorFromString(@"registerWindowWithContextID:atLevel:")];
    [invocation setArgument:&_contextId atIndex:2];
    [invocation setArgument:&windowLevel atIndex:3];
    [invocation invoke];
    return YES;
}
@end

#pragma mark - HUDMainWindow
@implementation HUDMainWindow
- (instancetype)initWithFrame:(CGRect)frame { if (self = [super _initWithFrame:frame attached:NO]) { self.backgroundColor = [UIColor clearColor]; [self commonInit]; } return self; }
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *rootView = self.rootViewController.view;
    if (!rootView) return nil;
    UIView *hit = [self findInteractiveView:rootView point:point event:event];
    return hit;
}
- (UIView *)findInteractiveView:(UIView *)view point:(CGPoint)point event:(UIEvent *)event {
    if (view.hidden || view.alpha < 0.01 || !view.userInteractionEnabled) return nil;
    CGPoint localPoint = [self convertPoint:point toView:view];
    if (![view pointInside:localPoint withEvent:event]) return nil;
    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIView *hit = [self findInteractiveView:subview point:point event:event];
        if (hit) return hit;
    }
    if ([view isKindOfClass:NSClassFromString(@"MenuView")] || [view isKindOfClass:[UIControl class]]) return view;
    return nil;
}
@end

#pragma mark - HUDRootViewController
@implementation HUDRootViewController {
    NSMutableDictionary *_userDefaults;
    NSMutableArray <NSLayoutConstraint *> *_constraints;
    id _orientationObserver;
    UIView *_blurView;
    MenuView *menuView;
    UIView *_contentView;
    UILabel *_speedLabel;
    UIImageView *_lockedView;
    NSTimer *_timer;
    BOOL _isFocused;
    UIInterfaceOrientation _orientation;
}
- (void)registerNotifications {
    int token;
    notify_register_dispatch(NOTIFY_RELOAD_HUD, &token, dispatch_get_main_queue(), ^(int token) { [self reloadUserDefaults]; });
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, LaunchServicesApplicationStateChanged, CFSTR(NOTIFY_LS_APP_CHANGED), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, SpringBoardLockStatusChanged, CFSTR(NOTIFY_UI_LOCKCOMPLETE), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, SpringBoardLockStatusChanged, CFSTR(NOTIFY_UI_LOCKSTATE), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
#define USER_DEFAULTS_PATH @"/var/mobile/Library/Preferences/ch.xxtou.hudapp.plist"
- (void)loadUserDefaults:(BOOL)forceReload { if (forceReload || !_userDefaults) _userDefaults = [[NSDictionary dictionaryWithContentsOfFile:USER_DEFAULTS_PATH] mutableCopy] ?: [NSMutableDictionary dictionary]; }
- (void)reloadUserDefaults {
    [self loadUserDefaults:YES];
    NSInteger selectedMode = [self selectedMode];
    BOOL isCentered = (selectedMode == HUDPresetPositionTopCenter || selectedMode == HUDPresetPositionTopCenterMost);
    BOOL isCenteredMost = (selectedMode == HUDPresetPositionTopCenterMost);
    BOOL singleLineMode = [self singleLineMode], usesBitrate = [self usesBitrate], usesArrowPrefixes = [self usesArrowPrefixes], usesLargeFont = [self usesLargeFont] && !isCenteredMost;
    _blurView.layer.maskedCorners = (isCenteredMost ? kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner : kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
    _blurView.layer.cornerRadius = (usesLargeFont ? 4.5 : 4.0);
    _speedLabel.textAlignment = (isCentered ? NSTextAlignmentCenter : NSTextAlignmentLeft);
    _lockedView.image = isCentered ? [UIImage systemImageNamed:@"hand.raised.slash.fill"] : [UIImage systemImageNamed:@"lock.fill"];
    DATAUNIT = usesBitrate; SHOW_UPLOAD_SPEED = !singleLineMode; SHOW_DOWNLOAD_SPEED_FIRST = isCentered; SHOW_SECOND_SPEED_IN_NEW_LINE = !isCentered; FONT_SIZE = (usesLargeFont ? 9.0 : 8.0);
    UPLOAD_PREFIX = (usesArrowPrefixes ? "↑" : "▲"); DOWNLOAD_PREFIX = (usesArrowPrefixes ? "↓" : "▼");
    prevInputBytes = 0; prevOutputBytes = 0; attributedUploadPrefix = nil; attributedDownloadPrefix = nil;
    [self updateViewConstraints];
}
- (NSInteger)selectedMode { [self loadUserDefaults:NO]; NSNumber *mode = [_userDefaults objectForKey:@"selectedMode"]; return mode ? [mode integerValue] : HUDPresetPositionTopCenter; }
- (BOOL)singleLineMode { [self loadUserDefaults:NO]; NSNumber *mode = [_userDefaults objectForKey:@"singleLineMode"]; return mode ? [mode boolValue] : NO; }
- (BOOL)usesBitrate { [self loadUserDefaults:NO]; NSNumber *mode = [_userDefaults objectForKey:@"usesBitrate"]; return mode ? [mode boolValue] : NO; }
- (BOOL)usesArrowPrefixes { [self loadUserDefaults:NO]; NSNumber *mode = [_userDefaults objectForKey:@"usesArrowPrefixes"]; return mode ? [mode boolValue] : NO; }
- (BOOL)usesLargeFont { [self loadUserDefaults:NO]; NSNumber *mode = [_userDefaults objectForKey:@"usesLargeFont"]; return mode ? [mode boolValue] : NO; }
- (instancetype)init {
    if (self = [super init]) {
        _constraints = [NSMutableArray array];
        _orientationObserver = [[objc_getClass("FBSOrientationObserver") alloc] init];
        __weak HUDRootViewController *weakSelf = self;
        [(FBSOrientationObserver *)_orientationObserver setHandler:^(FBSOrientationUpdate *orientationUpdate) {
            HUDRootViewController *strongSelf = weakSelf;
            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf updateOrientation:(UIInterfaceOrientation)orientationUpdate.orientation animateWithDuration:orientationUpdate.duration]; });
        }];
        [self registerNotifications];
    }
    return self;
}
- (void)dealloc { [(FBSOrientationObserver *)_orientationObserver invalidate]; }
- (void)updateOrientation:(UIInterfaceOrientation)orientation animateWithDuration:(NSTimeInterval)duration {
    if (orientation == _orientation) return;
    _orientation = orientation;
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat angle = 0; CGRect targetBounds = screenBounds;
    if (orientation == UIInterfaceOrientationLandscapeLeft) { angle = -M_PI_2; targetBounds = CGRectMake(0, 0, screenBounds.size.height, screenBounds.size.width); }
    else if (orientation == UIInterfaceOrientationLandscapeRight) { angle = M_PI_2; targetBounds = CGRectMake(0, 0, screenBounds.size.height, screenBounds.size.width); }
    else if (orientation == UIInterfaceOrientationPortraitUpsideDown) { angle = M_PI; }
    [UIView animateWithDuration:duration animations:^{
        self->_contentView.bounds = targetBounds;
        self->_contentView.center = CGPointMake(screenBounds.size.width / 2.0, screenBounds.size.height / 2.0);
        self->_contentView.transform = CGAffineTransformMakeRotation(angle);
    }];
    [_contentView setNeedsLayout]; [_contentView layoutIfNeeded];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.userInteractionEnabled = YES; self.view.backgroundColor = [UIColor clearColor];
    _contentView = [[UIView alloc] initWithFrame:self.view.bounds]; _contentView.backgroundColor = [UIColor clearColor]; _contentView.userInteractionEnabled = YES; [self.view addSubview:_contentView];
    _blurView = [[UIView alloc] initWithFrame:_contentView.bounds]; _blurView.backgroundColor = [UIColor clearColor]; _blurView.userInteractionEnabled = YES; [_contentView addSubview:_blurView];
    _blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[ [_blurView.topAnchor constraintEqualToAnchor:_contentView.topAnchor], [_blurView.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor], [_blurView.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor], [_blurView.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor] ]];
    menuView = [[MenuView alloc] initWithFrame:_contentView.bounds]; menuView.userInteractionEnabled = YES; [_blurView addSubview:menuView];
    _speedLabel = [[UILabel alloc] initWithFrame:CGRectZero]; _speedLabel.translatesAutoresizingMaskIntoConstraints = NO; [_blurView addSubview:_speedLabel];
    _lockedView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]]; _lockedView.tintColor = [UIColor whiteColor]; _lockedView.translatesAutoresizingMaskIntoConstraints = NO; _lockedView.alpha = 0.0; [_blurView addSubview:_lockedView];
    [self reloadUserDefaults];
}
- (void)resetLoopTimer { [_timer invalidate]; _timer = [NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL target:self selector:@selector(updateSpeedLabel) userInfo:nil repeats:YES]; }
- (void)stopLoopTimer { [_timer invalidate]; _timer = nil; }
- (void)updateSpeedLabel { if (!shouldUpdateSpeedLabel) return; _speedLabel.attributedText = formattedAttributedString(_isFocused); }
- (void)updateViewConstraints {
    [NSLayoutConstraint deactivateConstraints:_constraints]; [_constraints removeAllObjects];
    NSInteger selectedMode = [self selectedMode]; BOOL isCentered = (selectedMode == HUDPresetPositionTopCenter || selectedMode == HUDPresetPositionTopCenterMost);
    [_constraints addObjectsFromArray:@[ [_speedLabel.topAnchor constraintEqualToAnchor:_contentView.topAnchor], [_speedLabel.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor] ]];
    if (isCentered) [_constraints addObject:[_speedLabel.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor]];
    else if (selectedMode == HUDPresetPositionTopLeft) [_constraints addObject:[_speedLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:10]];
    else [_constraints addObject:[_speedLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-10]];
    [_constraints addObjectsFromArray:@[ [_lockedView.centerXAnchor constraintEqualToAnchor:_blurView.centerXAnchor], [_lockedView.centerYAnchor constraintEqualToAnchor:_blurView.centerYAnchor] ]];
    [NSLayoutConstraint activateConstraints:_constraints]; [super updateViewConstraints];
}
@end
