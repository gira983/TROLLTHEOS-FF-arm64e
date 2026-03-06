#import <objc/runtime.h>

// Лог в файл (определён в HUDApp.mm)
extern void writeLog(NSString *msg);
// Fallback если не линкуется
static void espLog(NSString *msg) {
#ifdef DEBUG
    static NSString *path = @"/var/mobile/Library/Caches/hud_debug.log";
    NSString *line = [NSString stringWithFormat:@"%@\n", msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
#endif
}
#import "mahoa.h"

// --- Obfuscated offsets (compile-time encrypted, runtime decrypted) ---
// Player fields
#define OFF_ROTATION        ENCRYPTOFFSET("0x53C")
#define OFF_FIRING          ENCRYPTOFFSET("0x750")
#define OFF_IPRIDATAPOOL    ENCRYPTOFFSET("0x68")
#define OFF_PLAYERID        ENCRYPTOFFSET("0x338")
#define OFF_CAMERA_TRANSFORM ENCRYPTOFFSET("0x318")
#define OFF_HEAD_NODE       ENCRYPTOFFSET("0x5B8")
#define OFF_HIP_NODE        ENCRYPTOFFSET("0x5C0")
#define OFF_LEFTANKLE_NODE  ENCRYPTOFFSET("0x5F0")
#define OFF_RIGHTANKLE_NODE ENCRYPTOFFSET("0x5F8")
#define OFF_RIGHTTOE_NODE   ENCRYPTOFFSET("0x608")
#define OFF_LEFTARM_NODE    ENCRYPTOFFSET("0x620")
#define OFF_LEFTFOREARM_NODE ENCRYPTOFFSET("0x648")
#define OFF_LEFTHAND_NODE   ENCRYPTOFFSET("0x638")
#define OFF_RIGHTARM_NODE   ENCRYPTOFFSET("0x628")
#define OFF_RIGHTFOREARM_NODE ENCRYPTOFFSET("0x640")
#define OFF_RIGHTHAND_NODE  ENCRYPTOFFSET("0x630")
// Match/game fields
#define OFF_MATCH           ENCRYPTOFFSET("0x90")
#define OFF_LOCALPLAYER     ENCRYPTOFFSET("0xB0")
#define OFF_CAMERA_MGR      ENCRYPTOFFSET("0xD8")
#define OFF_CAMERA_MGR2     ENCRYPTOFFSET("0x18")
#define OFF_MATRIX_BASE     ENCRYPTOFFSET("0xD8")
#define OFF_CAM_V1          ENCRYPTOFFSET("0x10")
#define OFF_PLAYERLIST      ENCRYPTOFFSET("0x120")
#define OFF_PLAYERLIST_ARR  ENCRYPTOFFSET("0x28")
#define OFF_PLAYERLIST_CNT  ENCRYPTOFFSET("0x18")
#define OFF_PLAYERLIST_ITEM ENCRYPTOFFSET("0x20")
// GameFacade
#define OFF_GAMEFACADE_TI   ENCRYPTOFFSET("0xA4D2968")
#define OFF_GAMEFACADE_ST   ENCRYPTOFFSET("0xB8")
// BodyPart
#define OFF_BODYPART_POS    ENCRYPTOFFSET("0x10")
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h> 
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

uint64_t Moudule_Base = -1;

// Глобальный ключ для objc_associated object — один адрес для set и get
static const char kSegHandlerKey = 0;

// --- ESP Config ---
static bool isBox = YES;
static bool isBone = YES;
static bool isHealth = YES;
static bool isName = YES;
static bool isDis = YES;
static bool isLine = NO;       // ESP Lines
static int  lineOrigin = 1;    // 0 = Top, 1 = Center, 2 = Bottom

// --- Aimbot Config ---
static bool isAimbot = NO;
static float aimFov = 150.0f; // Bán kính vòng tròn FOV
static float aimDistance = 200.0f; // Khoảng cách aim mặc định

// --- Advanced Aimbot Config ---


static int  aimMode = 1;           // 0 = Closest to Player, 1 = Closest to Crosshair
static int  aimTrigger = 1;        // 0 = Always, 1 = Only Shooting, 2 = Only Aiming
static int  aimTarget = 0;         // 0 = Head, 1 = Neck, 2 = Hip
static float aimSpeed = 1.0f;      // Aim smoothing 0.05 - 1.0
static bool isStreamerMode = NO;   // Stream Proof

@interface CustomSwitch : UIView
@property (nonatomic, assign, getter=isOn) BOOL on;
@property (nonatomic, copy) void (^onToggle)(BOOL on);
@end

@implementation CustomSwitch { UIView *_thumb; NSTimeInterval _lastToggleTime; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _lastToggleTime = 0;
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 22, 22)];
        _thumb.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _thumb.layer.cornerRadius = 11;
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)handleTap {
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastToggleTime < 0.3) return;
    _lastToggleTime = now;
    self.on = !self.on;
    if (self.onToggle) self.onToggle(self.on);
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.bounds.size.height/2];
    CGContextSetFillColorWithColor(ctx, (self.isOn ? [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor colorWithWhite:0.15 alpha:1.0]).CGColor);
    [path fill];
}
- (void)setOn:(BOOL)on {
    if (_on != on) { _on = on; [self setNeedsDisplay]; [self updateThumbPosition]; }
}
- (void)updateThumbPosition {
    [UIView animateWithDuration:0.2 animations:^{
        CGRect f = self->_thumb.frame;
        f.origin.x = self.isOn ? self.bounds.size.width - f.size.width - 2 : 2;
        self->_thumb.frame = f;
        self->_thumb.backgroundColor = self.isOn ? UIColor.whiteColor : [UIColor colorWithWhite:0.75 alpha:1.0];
    }];
}
@end

// ExpandedHitView: передаёт hitTest subviews даже если они выходят за bounds контейнера.
@interface ExpandedHitView : UIView
@end
@implementation ExpandedHitView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    for (UIView *sub in [self.subviews reverseObjectEnumerator]) {
        CGPoint local = [self convertPoint:point toView:sub];
        UIView *hit = [sub hitTest:local withEvent:event];
        if (hit) return hit;
    }
    return [self pointInside:point withEvent:event] ? self : nil;
}
@end


@interface MenuView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers;
@end

// Кастомный слайдер — обрабатывает touches с правильным конвертированием координат
@interface HUDSlider : UIView
@property (nonatomic) float minimumValue;
@property (nonatomic) float maximumValue;
@property (nonatomic) float value;
@property (nonatomic, strong) UIColor *minimumTrackTintColor;
@property (nonatomic, strong) UIColor *thumbTintColor;
@property (nonatomic, copy) void (^onValueChanged)(float value);
@end

@implementation HUDSlider {
    UIView *_track;
    UIView *_fill;
    UIView *_thumb;
    float _dragStartValue;
    CGFloat _dragStartX;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _minimumValue = 0;
        _maximumValue = 1;
        _value = 0;
        _minimumTrackTintColor = [UIColor systemBlueColor];
        _thumbTintColor = [UIColor whiteColor];
        self.userInteractionEnabled = YES;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width;
    CGFloat trackH = 4;
    
    _track = [[UIView alloc] initWithFrame:CGRectMake(10, (h - trackH)/2, w - 20, trackH)];
    _track.backgroundColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    _track.layer.cornerRadius = trackH/2;
    _track.userInteractionEnabled = NO;
    [self addSubview:_track];
    
    _fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, trackH)];
    _fill.layer.cornerRadius = trackH/2;
    _fill.userInteractionEnabled = NO;
    [_track addSubview:_fill];
    
    CGFloat thumbSize = 22;
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, thumbSize, thumbSize)];
    _thumb.layer.cornerRadius = thumbSize/2;
    _thumb.userInteractionEnabled = NO;
    [self addSubview:_thumb];
    
    [self updateAppearance];
    [self updateThumbPosition];
}

- (void)updateAppearance {
    _fill.backgroundColor = _minimumTrackTintColor ?: [UIColor systemBlueColor];
    _thumb.backgroundColor = _thumbTintColor ?: [UIColor whiteColor];
}

- (void)setValue:(float)value {
    _value = MAX(_minimumValue, MIN(_maximumValue, value));
    [self updateThumbPosition];
}

- (void)setMinimumTrackTintColor:(UIColor *)c { _minimumTrackTintColor = c; [self updateAppearance]; }
- (void)setThumbTintColor:(UIColor *)c { _thumbTintColor = c; [self updateAppearance]; }

- (void)updateThumbPosition {
    if (!_track) return;
    CGFloat range = _maximumValue - _minimumValue;
    CGFloat pct = (range > 0) ? (_value - _minimumValue) / range : 0;
    CGFloat trackW = _track.bounds.size.width;
    CGFloat x = pct * trackW;
    
    _fill.frame = CGRectMake(0, 0, x, _track.bounds.size.height);
    
    CGFloat thumbSize = _thumb.bounds.size.width;
    CGFloat thumbX = _track.frame.origin.x + x - thumbSize/2;
    CGFloat thumbY = (self.bounds.size.height - thumbSize)/2;
    _thumb.frame = CGRectMake(thumbX, thumbY, thumbSize, thumbSize);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    CGPoint loc = [touch locationInView:self];
    _dragStartX = loc.x;
    _dragStartValue = _value;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    CGPoint loc = [touch locationInView:self];
    
    CGFloat trackW = _track.bounds.size.width;
    CGFloat trackX = _track.frame.origin.x;
    CGFloat relX = loc.x - trackX;
    CGFloat pct = MAX(0, MIN(1, relX / trackW));
    
    float newVal = _minimumValue + pct * (_maximumValue - _minimumValue);
    _value = newVal;
    [self updateThumbPosition];
    
    if (_onValueChanged) _onValueChanged(_value);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesMoved:touches withEvent:event];
}

@end

// Скрывает view от ReplayKit/скриншотов через приватный CALayer ключ disableUpdateMask.
static BOOL __applyHideCapture(UIView *v, BOOL hidden) {
    static NSString *maskKey = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [[NSData alloc] initWithBase64EncodedString:@"ZGlzYWJsZVVwZGF0ZU1hc2s="
                                                            options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (data) maskKey = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    });
    if (!v || !maskKey || ![v.layer respondsToSelector:NSSelectorFromString(maskKey)]) return NO;
    NSInteger value = hidden ? ((1 << 1) | (1 << 4)) : 0;
    [v.layer setValue:@(value) forKey:maskKey];
    return YES;
}


@implementation MenuView {
    UIView *menuContainer;
    UIView *floatingButton;
    CGPoint _initialTouchPoint;
    
    UIView *mainTabContainer;
    UIView *aimTabContainer;
    UIView *settingTabContainer;
    UIView *extraTabContainer;
    UIView *_sidebar;

    UIView *previewView;
    UIView *previewContentContainer;
    
    UILabel *previewNameLabel;
    UILabel *previewDistLabel;
    UIView *healthBarContainer;
    UIView *boxContainer;
    
    uint64_t _lastMatchPtr;
    NSTimeInterval _lastValidFrame;
    UIView *skeletonContainer;
    
    float previewScale;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.drawingLayers = [NSMutableArray array];
        
        [self SetUpBase];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(appDidBecomeActive)
            name:UIApplicationDidBecomeActiveNotification
            object:nil];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        if (@available(iOS 15.0, *)) { self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(15, 20, 20); } else { self.displayLink.preferredFramesPerSecond = 20; }
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [self setupFloatingButton];
        [self setupMenuUI];
        [self layoutSubviews];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    if (!menuContainer || menuContainer.hidden) {
        if (floatingButton && !floatingButton.hidden) {
            CGRect fb = floatingButton.frame;
            CGRect hitZone = CGRectInset(fb, -5, -5);
            if (CGRectContainsPoint(hitZone, point)) return floatingButton;
        }
        return nil;
    }
    if (menuContainer && !menuContainer.hidden) {
        CGPoint pInMenu = [self convertPoint:point toView:menuContainer];
        if ([menuContainer pointInside:pInMenu withEvent:event]) {
            UIView *hit = [menuContainer hitTest:pInMenu withEvent:event];
            if (hit) return hit;
            return menuContainer;
        }
    }
    return nil;
}

- (void)setupFloatingButton {
    floatingButton = [[UIView alloc] initWithFrame:CGRectMake(50, 150, 54, 54)];
    floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0];
    floatingButton.layer.cornerRadius = 27;
    floatingButton.layer.borderWidth = 2;
    floatingButton.layer.borderColor = [UIColor whiteColor].CGColor;
    floatingButton.clipsToBounds = YES;
    floatingButton.userInteractionEnabled = YES;
    
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:floatingButton.bounds];
    iconLabel.text = @"M";
    iconLabel.textColor = [UIColor whiteColor];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    iconLabel.font = [UIFont boldSystemFontOfSize:22];
    iconLabel.userInteractionEnabled = NO;
    [floatingButton addSubview:iconLabel];
    
    UIPanGestureRecognizer *iconPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    iconPan.maximumNumberOfTouches = 1;
    iconPan.minimumNumberOfTouches = 1;
    [floatingButton addGestureRecognizer:iconPan];
    
    UITapGestureRecognizer *openTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showMenu)];
    openTap.numberOfTapsRequired = 1;
    openTap.numberOfTouchesRequired = 1;
    [openTap requireGestureRecognizerToFail:iconPan];
    [floatingButton addGestureRecognizer:openTap];
    
    [self addSubview:floatingButton];
}

- (void)addFeatureToView:(UIView *)view withTitle:(NSString *)title atY:(CGFloat)y initialValue:(BOOL)isOn andAction:(SEL)action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 150, 26)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13];
    [view addSubview:label];
    
    CGFloat swX = MIN(240, view.bounds.size.width - 65);
    CustomSwitch *customSwitch = [[CustomSwitch alloc] initWithFrame:CGRectMake(swX, y, 52, 26)];
    customSwitch.on = isOn;
    
    // Прямой вызов через блок, чтобы не зависеть от UIControl механизмов
    __weak typeof(self) weakSelf = self;
    customSwitch.onToggle = ^(BOOL on) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if ([weakSelf respondsToSelector:action]) {
            [weakSelf performSelector:action withObject:customSwitch];
        }
#pragma clang diagnostic pop
    };
    [view addSubview:customSwitch];
}

- (UILabel *)makeSectionLabel:(NSString *)title atY:(CGFloat)y width:(CGFloat)w {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, y, w, 16)];
    lbl.text = title;
    lbl.textColor = [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    lbl.font = [UIFont boldSystemFontOfSize:10];
    return lbl;
}

- (void)addSegmentTo:(UIView *)parent atY:(CGFloat)y title:(NSString *)title options:(NSArray *)options selectedRef:(int *)selectedRef tag:(NSInteger)baseTag {
    CGFloat padding = 10;
    CGFloat segW = (parent.bounds.size.width - padding * 2) / options.count;
    CGFloat segH = 28;
    CGFloat titleH = (title.length > 0) ? 14 : 0;

    if (title.length > 0) {
        UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(padding, y, parent.bounds.size.width - padding * 2, 12)];
        titleLbl.text = title;
        titleLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        titleLbl.font = [UIFont systemFontOfSize:10];
        titleLbl.userInteractionEnabled = NO;
        [parent addSubview:titleLbl];
    }

    UIView *segContainer = [[UIView alloc] initWithFrame:CGRectMake(padding, y + titleH, parent.bounds.size.width - padding * 2, segH)];
    segContainer.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.18 alpha:1.0];
    segContainer.layer.cornerRadius = 7;
    segContainer.clipsToBounds = YES;
    [parent addSubview:segContainer];

    for (int i = 0; i < (int)options.count; i++) {
        UIView *segBtn = [[UIView alloc] initWithFrame:CGRectMake(i * segW + 2, 2, segW - 4, segH - 4)];
        segBtn.backgroundColor = (*selectedRef == i) ? [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0] : [UIColor clearColor];
        segBtn.layer.cornerRadius = 5;
        segBtn.tag = baseTag * 100 + i;
        segBtn.userInteractionEnabled = NO;
        [segContainer addSubview:segBtn];

        UILabel *lbl = [[UILabel alloc] initWithFrame:segBtn.bounds];
        lbl.text = options[i];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.font = [UIFont boldSystemFontOfSize:10];
        lbl.textColor = (*selectedRef == i) ? [UIColor blackColor] : [UIColor colorWithWhite:0.7 alpha:1.0];
        lbl.userInteractionEnabled = NO;
        [segBtn addSubview:lbl];
    }

    NSInteger capturedBase = baseTag;
    UIView * __unsafe_unretained segRef = segContainer;
    int *ref = selectedRef;
    NSArray *capturedOptions = options;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] init];
    tap.cancelsTouchesInView = NO;
    objc_setAssociatedObject(tap, &kSegHandlerKey, ^(UITapGestureRecognizer *t) {
        CGPoint loc = [t locationInView:segRef];
        int idx = (int)(loc.x / (segRef.bounds.size.width / capturedOptions.count));
        if (idx < 0) idx = 0;
        if (idx >= (int)capturedOptions.count) idx = (int)capturedOptions.count - 1;
        *ref = idx;
        for (int j = 0; j < (int)capturedOptions.count; j++) {
            UIView *btn = [segRef viewWithTag:capturedBase * 100 + j];
            btn.backgroundColor = (j == idx) ? [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0] : [UIColor clearColor];
            UILabel *l = btn.subviews.firstObject;
            l.textColor = (j == idx) ? [UIColor blackColor] : [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [tap addTarget:self action:@selector(handleSegmentTapGesture:)];
    [segContainer addGestureRecognizer:tap];
}

- (void)setupMenuUI {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat menuWidth = MIN(550, screenW - 10);
    CGFloat menuHeight = MIN(370, screenH * 0.55);
    CGFloat scale = menuWidth / 550.0;
    
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, menuHeight)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 15;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    menuContainer.layer.borderWidth = 2;
    menuContainer.clipsToBounds = NO;
    menuContainer.hidden = YES;
    [self addSubview:menuContainer];

    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, 40)];
    headerView.backgroundColor = [UIColor clearColor];
    headerView.userInteractionEnabled = YES;
    [menuContainer addSubview:headerView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(menuWidth * 0.25, 5, menuWidth * 0.45, 30)];
    titleLabel.text = @"MENU TIPA";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:22];
    [headerView addSubview:titleLabel];
    
    UILabel *subTitle = [[UILabel alloc] initWithFrame:CGRectMake(menuWidth * 0.58, 12, menuWidth * 0.3, 20)];
    subTitle.text = @"Fryzz🥶";
    subTitle.textColor = [UIColor lightGrayColor];
    subTitle.font = [UIFont systemFontOfSize:10];
    [headerView addSubview:subTitle];
    
    NSArray *colors = @[[UIColor greenColor], [UIColor yellowColor], [UIColor redColor]];
    for (int i = 0; i < 3; i++) {
        UIView *circle = [[UIView alloc] initWithFrame:CGRectMake(menuWidth - 95 + (i * 25), 10, 18, 18)];
        circle.backgroundColor = colors[i];
        circle.layer.cornerRadius = 9;
        UILabel *btnIcon = [[UILabel alloc] initWithFrame:circle.bounds];
        btnIcon.textAlignment = NSTextAlignmentCenter;
        btnIcon.font = [UIFont boldSystemFontOfSize:12];
        btnIcon.textColor = [UIColor blackColor];
        if (i == 0) btnIcon.text = @"□";
        if (i == 1) btnIcon.text = @"-";
        if (i == 2) {
            btnIcon.text = @"X";
            circle.tag = 200;
            UITapGestureRecognizer *closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCloseTap:)];
            [circle addGestureRecognizer:closeTap];
        }
        [circle addSubview:btnIcon];
        [headerView addSubview:circle];
    }
    
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [headerView addGestureRecognizer:menuPan];
    
    CGFloat sidebarW = 75 * scale;
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectMake(menuWidth - sidebarW - 10, 50, sidebarW, 310 * scale)];
    sidebar.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    sidebar.layer.cornerRadius = 10;
    sidebar.userInteractionEnabled = YES;
    _sidebar = sidebar;
    [menuContainer addSubview:sidebar];
    
    NSArray *tabs = @[@"Main", @"AIM", @"Extra", @"Setting"];
    for (int i = 0; i < tabs.count; i++) {
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(3, 8 + (i * 50 * scale), sidebarW - 6, 35 * scale)];
        btn.backgroundColor = (i == 0) ? [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0] : [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        btn.layer.cornerRadius = 17.5;
        btn.userInteractionEnabled = YES;
        btn.tag = 100 + i;
        UILabel *btnLbl = [[UILabel alloc] initWithFrame:btn.bounds];
        btnLbl.text = tabs[i];
        btnLbl.textColor = [UIColor whiteColor];
        btnLbl.font = [UIFont boldSystemFontOfSize:11];
        btnLbl.textAlignment = NSTextAlignmentCenter;
        btnLbl.userInteractionEnabled = NO;
        [btn addSubview:btnLbl];
        UITapGestureRecognizer *tabTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTabTap:)];
        [btn addGestureRecognizer:tabTap];
        [sidebar addSubview:btn];
    }

    CGFloat tabW = menuWidth - sidebarW - 25;
    CGFloat tabH = menuHeight - 55;
    mainTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    mainTabContainer.backgroundColor = [UIColor clearColor];
    [menuContainer addSubview:mainTabContainer];

    UIView *previewBorder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 130, 250)];
    previewBorder.layer.borderColor = [UIColor whiteColor].CGColor;
    previewBorder.layer.borderWidth = 1;
    previewBorder.layer.cornerRadius = 10;
    [mainTabContainer addSubview:previewBorder];
    
    UILabel *pvTitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 5, 130, 20)];
    pvTitle.text = @"Preview";
    pvTitle.textColor = [UIColor whiteColor];
    pvTitle.textAlignment = NSTextAlignmentCenter;
    pvTitle.font = [UIFont boldSystemFontOfSize:14];
    [previewBorder addSubview:pvTitle];
    
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(10, 28, 110, 1)];
    line.backgroundColor = [UIColor whiteColor];
    [previewBorder addSubview:line];
    
    previewView = [[UIView alloc] initWithFrame:CGRectMake(0, 30, 130, 220)];
    previewView.backgroundColor = [UIColor blackColor];
    previewView.clipsToBounds = YES;
    [previewBorder addSubview:previewView];
    
    previewContentContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewView addSubview:previewContentContainer];
    
    [self drawPreviewElements];
    [self updatePreviewVisibility];

    UIView *featureBox = [[UIView alloc] initWithFrame:CGRectMake(140, 0, tabW - 145, tabH)];
    featureBox.layer.borderColor = [UIColor whiteColor].CGColor;
    featureBox.layer.borderWidth = 1;
    featureBox.layer.cornerRadius = 10;
    featureBox.backgroundColor = [UIColor blackColor];
    [mainTabContainer addSubview:featureBox];
    
    UILabel *ftTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    ftTitle.text = @"ESP Feature";
    ftTitle.textColor = [UIColor whiteColor];
    ftTitle.font = [UIFont boldSystemFontOfSize:16];
    [featureBox addSubview:ftTitle];
    
    UIView *ftLine = [[UIView alloc] initWithFrame:CGRectMake(15, 35, tabW - 155, 1)];
    ftLine.backgroundColor = [UIColor whiteColor];
    [featureBox addSubview:ftLine];
    
    [self addFeatureToView:featureBox withTitle:@"Box" atY:45 initialValue:isBox andAction:@selector(toggleBox:)];
    [self addFeatureToView:featureBox withTitle:@"Bone" atY:80 initialValue:isBone andAction:@selector(toggleBone:)];
    [self addFeatureToView:featureBox withTitle:@"Health" atY:115 initialValue:isHealth andAction:@selector(toggleHealth:)];
    [self addFeatureToView:featureBox withTitle:@"Name" atY:150 initialValue:isName andAction:@selector(toggleName:)];
    [self addFeatureToView:featureBox withTitle:@"Distance" atY:185 initialValue:isDis andAction:@selector(toggleDist:)];
    [self addFeatureToView:featureBox withTitle:@"Lines" atY:220 initialValue:isLine andAction:@selector(toggleLine:)];

    NSArray *lineOriginOpts = @[@"Top", @"Center", @"Bottom"];
    [self addSegmentTo:featureBox atY:256 title:@"" options:lineOriginOpts selectedRef:&lineOrigin tag:20];

    aimTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    aimTabContainer.backgroundColor = [UIColor blackColor];
    aimTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    aimTabContainer.layer.borderWidth = 1;
    aimTabContainer.layer.cornerRadius = 10;
    aimTabContainer.hidden = YES;
    [menuContainer addSubview:aimTabContainer];

    CGFloat aW = aimTabContainer.bounds.size.width;
    CGFloat ay = 6;
    UILabel *aimTitle = [self makeSectionLabel:@"AIMBOT" atY:ay width:aW];
    [aimTabContainer addSubview:aimTitle]; ay += 18;
    UIView *aimSep1 = [[UIView alloc] initWithFrame:CGRectMake(10, ay, aW - 20, 1)];
    aimSep1.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];
    [aimTabContainer addSubview:aimSep1]; ay += 6;
    [self addFeatureToView:aimTabContainer withTitle:@"Enable Aimbot" atY:ay initialValue:isAimbot andAction:@selector(toggleAimbot:)]; ay += 30;
    ay += 4;
    UIView *aimSep2 = [[UIView alloc] initWithFrame:CGRectMake(10, ay, aW - 20, 1)];
    aimSep2.backgroundColor = aimSep1.backgroundColor;
    [aimTabContainer addSubview:aimSep2]; ay += 6;
    UILabel *aimModeTitle = [self makeSectionLabel:@"AIM MODE" atY:ay width:aW];
    [aimTabContainer addSubview:aimModeTitle]; ay += 16;
    NSArray *aimModeOpts = @[@"Closest Player", @"Crosshair"];
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:aimModeOpts selectedRef:&aimMode tag:10]; ay += 32;
    NSArray *aimTargetOpts = @[@"Head", @"Neck", @"Hip"];
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:aimTargetOpts selectedRef:&aimTarget tag:11]; ay += 32;
    NSArray *aimTriggerOpts = @[@"Always", @"Shooting"];
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:aimTriggerOpts selectedRef:&aimTrigger tag:12];

    extraTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    extraTabContainer.backgroundColor = [UIColor blackColor];
    extraTabContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    extraTabContainer.layer.borderWidth = 1;
    extraTabContainer.layer.cornerRadius = 10;
    extraTabContainer.hidden = YES;
    [menuContainer addSubview:extraTabContainer];

    CGFloat eW = extraTabContainer.bounds.size.width;
    CGFloat ey = 10;
    UILabel *exTitle = [self makeSectionLabel:@"PARAMETERS" atY:ey width:eW];
    [extraTabContainer addSubview:exTitle]; ey += 22;
    UIView *exSep1 = [[UIView alloc] initWithFrame:CGRectMake(10, ey, eW - 20, 1)];
    exSep1.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];
    [extraTabContainer addSubview:exSep1]; ey += 10;
    UILabel *fovLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, ey, eW - 60, 14)];
    fovLbl.text = @"FOV Radius"; fovLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    fovLbl.font = [UIFont systemFontOfSize:10]; [extraTabContainer addSubview:fovLbl];
    UILabel *fovVal = [[UILabel alloc] initWithFrame:CGRectMake(eW - 45, ey, 40, 14)];
    fovVal.text = [NSString stringWithFormat:@"%.0f", aimFov];
    fovVal.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    fovVal.font = [UIFont systemFontOfSize:10]; fovVal.textAlignment = NSTextAlignmentRight;
    [extraTabContainer addSubview:fovVal]; ey += 16;
    HUDSlider *fovSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, ey, eW - 20, 36)];
    fovSlider.minimumValue = 10; fovSlider.maximumValue = 400; fovSlider.value = aimFov;
    fovSlider.minimumTrackTintColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
    fovSlider.thumbTintColor = [UIColor whiteColor]; fovSlider.tag = 300;
    UILabel * __unsafe_unretained fvRef = fovVal;
    fovSlider.onValueChanged = ^(float v){ aimFov = v; fvRef.text = [NSString stringWithFormat:@"%.0f", v]; };
    [extraTabContainer addSubview:fovSlider]; ey += 44;
    UILabel *distLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, ey, eW - 60, 14)];
    distLbl.text = @"Aim Distance"; distLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    distLbl.font = [UIFont systemFontOfSize:10]; [extraTabContainer addSubview:distLbl];
    UILabel *distVal = [[UILabel alloc] initWithFrame:CGRectMake(eW - 45, ey, 40, 14)];
    distVal.text = [NSString stringWithFormat:@"%.0f", aimDistance];
    distVal.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    distVal.font = [UIFont systemFontOfSize:10]; distVal.textAlignment = NSTextAlignmentRight;
    [extraTabContainer addSubview:distVal]; ey += 16;
    HUDSlider *distSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, ey, eW - 20, 36)];
    distSlider.minimumValue = 10; distSlider.maximumValue = 500; distSlider.value = aimDistance;
    distSlider.minimumTrackTintColor = [UIColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:1.0];
    distSlider.thumbTintColor = [UIColor whiteColor]; distSlider.tag = 301;
    UILabel * __unsafe_unretained dvRef = distVal;
    distSlider.onValueChanged = ^(float v){ aimDistance = v; dvRef.text = [NSString stringWithFormat:@"%.0f", v]; };
    [extraTabContainer addSubview:distSlider]; ey += 44;
    UILabel *spdLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, ey, eW - 60, 14)];
    spdLbl.text = @"Aim Speed"; spdLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    spdLbl.font = [UIFont systemFontOfSize:10]; [extraTabContainer addSubview:spdLbl];
    UILabel *spdVal = [[UILabel alloc] initWithFrame:CGRectMake(eW - 45, ey, 40, 14)];
    spdVal.text = [NSString stringWithFormat:@"%.2f", aimSpeed];
    spdVal.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    spdVal.font = [UIFont systemFontOfSize:10]; spdVal.textAlignment = NSTextAlignmentRight;
    [extraTabContainer addSubview:spdVal]; ey += 16;
    HUDSlider *spdSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, ey, eW - 20, 36)];
    spdSlider.minimumValue = 0.05; spdSlider.maximumValue = 1.0; spdSlider.value = aimSpeed;
    spdSlider.minimumTrackTintColor = [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:1.0];
    spdSlider.thumbTintColor = [UIColor whiteColor]; spdSlider.tag = 302;
    UILabel * __unsafe_unretained svRef = spdVal;
    spdSlider.onValueChanged = ^(float v){ aimSpeed = v; svRef.text = [NSString stringWithFormat:@"%.2f", v]; };
    [extraTabContainer addSubview:spdSlider];

    settingTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    settingTabContainer.backgroundColor = [UIColor blackColor];
    settingTabContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    settingTabContainer.layer.borderWidth = 1;
    settingTabContainer.layer.cornerRadius = 10;
    settingTabContainer.hidden = YES;
    [menuContainer addSubview:settingTabContainer];
    UILabel *stSectionTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 12, tabW - 30, 18)];
    stSectionTitle.text = @"SETTINGS";
    stSectionTitle.textColor = [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    stSectionTitle.font = [UIFont boldSystemFontOfSize:11];
    [settingTabContainer addSubview:stSectionTitle];
    UIView *stSep = [[UIView alloc] initWithFrame:CGRectMake(15, 33, tabW - 30, 1)];
    stSep.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];
    [settingTabContainer addSubview:stSep];
    [self addFeatureToView:settingTabContainer withTitle:@"Stream Proof" atY:40 initialValue:isStreamerMode andAction:@selector(toggleStreamerMode:)];
    UILabel *stDesc = [[UILabel alloc] initWithFrame:CGRectMake(15, 80, tabW - 30, 32)];
    stDesc.text = @"Hides the overlay from screen recordings & screenshots.";
    stDesc.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    stDesc.font = [UIFont systemFontOfSize:10];
    stDesc.numberOfLines = 2;
    [settingTabContainer addSubview:stDesc];
    [menuContainer bringSubviewToFront:sidebar];
}

- (void)switchToTab:(NSInteger)tabIndex {
    mainTabContainer.hidden = YES;
    aimTabContainer.hidden = YES;
    extraTabContainer.hidden = YES;
    settingTabContainer.hidden = YES;
    mainTabContainer.userInteractionEnabled = YES;
    aimTabContainer.userInteractionEnabled = YES;
    extraTabContainer.userInteractionEnabled = YES;
    settingTabContainer.userInteractionEnabled = YES;
    for (UIView *sub in _sidebar.subviews) {
        if ([sub isKindOfClass:[UIView class]] && sub.tag >= 100 && sub.tag <= 103) {
            sub.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        }
    }
    UIView *activeBtn = [_sidebar viewWithTag:100 + tabIndex];
    activeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
    if (tabIndex == 0) { mainTabContainer.hidden = NO; }
    if (tabIndex == 1) { aimTabContainer.hidden = NO; }
    if (tabIndex == 2) { extraTabContainer.hidden = NO; }
    if (tabIndex == 3) { settingTabContainer.hidden = NO; }
}

- (void)drawPreviewElements {
    CGFloat w = previewView.frame.size.width;  
    CGFloat h = previewView.frame.size.height; 
    CGFloat cx = w / 2;
    CGFloat startY = 45; 
    CGFloat boxW = 80;
    CGFloat boxH = 140;
    CGFloat by = startY;
    boxContainer = [[UIView alloc] initWithFrame:CGRectMake(cx - boxW/2, by, boxW, boxH)];
    boxContainer.layer.borderColor = [UIColor greenColor].CGColor;
    boxContainer.layer.borderWidth = 1.5;
    [previewContentContainer addSubview:boxContainer];
    healthBarContainer = [[UIView alloc] initWithFrame:CGRectMake(cx - boxW/2 - 6, by, 3, boxH)];
    healthBarContainer.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [previewContentContainer addSubview:healthBarContainer];
    UIView *hp = [[UIView alloc] initWithFrame:CGRectMake(0, boxH*0.3, 3, boxH*0.7)];
    hp.backgroundColor = [UIColor greenColor];
    [healthBarContainer addSubview:hp];
    previewNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, by - 18, w, 15)];
    previewNameLabel.text = @"Player Name";
    previewNameLabel.textColor = [UIColor whiteColor];
    previewNameLabel.textAlignment = NSTextAlignmentCenter;
    previewNameLabel.font = [UIFont boldSystemFontOfSize:10];
    [previewContentContainer addSubview:previewNameLabel];
    skeletonContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    skeletonContainer.userInteractionEnabled = NO;
    [previewContentContainer addSubview:skeletonContainer];
    UIColor *skelColor = [UIColor whiteColor];
    CGFloat skelThick = 1.0;
    CGFloat headRad = 8;
    CGFloat headY = by + 10;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(cx - headRad, headY, headRad*2, headRad*2)];
    head.layer.borderColor = skelColor.CGColor;
    head.layer.borderWidth = skelThick;
    head.layer.cornerRadius = headRad;
    [skeletonContainer addSubview:head];
    CGPoint pNeck = CGPointMake(cx, headY + headRad);
    CGPoint pPelvis = CGPointMake(cx, by + 65);
    CGPoint pShoulderL = CGPointMake(cx - 15, by + 30);
    CGPoint pShoulderR = CGPointMake(cx + 15, by + 30);
    CGPoint pElbowL = CGPointMake(cx - 20, by + 50);
    CGPoint pElbowR = CGPointMake(cx + 20, by + 50);
    CGPoint pHandL = CGPointMake(cx - 20, by + 70);
    CGPoint pHandR = CGPointMake(cx + 20, by + 70);
    CGPoint pKneeL = CGPointMake(cx - 12, by + 95);
    CGPoint pKneeR = CGPointMake(cx + 12, by + 95);
    CGPoint pFootL = CGPointMake(cx - 15, by + 125);
    CGPoint pFootR = CGPointMake(cx + 15, by + 125);
    [self addLineFrom:pNeck to:pPelvis color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pShoulderL to:pShoulderR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:CGPointMake(cx, by+30) to:pShoulderL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pShoulderL to:pElbowL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pElbowL to:pHandL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:CGPointMake(cx, by+30) to:pShoulderR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pShoulderR to:pElbowR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pElbowR to:pHandR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pPelvis to:pKneeL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pKneeL to:pFootL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pPelvis to:pKneeR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pKneeR to:pFootR color:skelColor width:skelThick inView:skeletonContainer];
    previewDistLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, by + boxH + 5, w, 15)];
    previewDistLabel.text = @"Distance";
    previewDistLabel.textColor = [UIColor whiteColor];
    previewDistLabel.textAlignment = NSTextAlignmentCenter;
    previewDistLabel.font = [UIFont systemFontOfSize:10];
    [previewContentContainer addSubview:previewDistLabel];
}

- (void)updatePreviewVisibility {
    boxContainer.hidden = !isBox;
    skeletonContainer.hidden = !isBone;
    healthBarContainer.hidden = !isHealth;
    previewNameLabel.hidden = !isName;
    previewDistLabel.hidden = !isDis;
    if (isBox && isBone) { [previewContentContainer bringSubviewToFront:boxContainer]; }
}

- (void)handleSegmentTapGesture:(UITapGestureRecognizer *)t {
    void (^handler)(UITapGestureRecognizer *) = objc_getAssociatedObject(t, &kSegHandlerKey);
    if (handler) handler(t);
}

- (void)addLineFrom:(CGPoint)p1 to:(CGPoint)p2 color:(UIColor *)color width:(CGFloat)width inView:(UIView *)view {
    CGFloat angle = atan2(p2.y - p1.y, p2.x - p1.x);
    CGFloat dist = hypot(p2.x - p1.x, p2.y - p1.y);
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, dist, width)];
    line.center = CGPointMake((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
    line.transform = CGAffineTransformMakeRotation(angle);
    line.backgroundColor = color;
    line.userInteractionEnabled = NO;
    [view addSubview:line];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) {
        CGRect newFrame = self.superview.bounds;
        if (!CGSizeEqualToSize(self.frame.size, newFrame.size)) {
            self.frame = newFrame;
            if (menuContainer && !menuContainer.hidden) {
                menuContainer.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
            }
        }
    }
    if (floatingButton) {
        CGPoint btnCenter = floatingButton.center;
        CGFloat halfW = floatingButton.bounds.size.width / 2;
        CGFloat halfH = floatingButton.bounds.size.height / 2;
        if (btnCenter.x < halfW) btnCenter.x = halfW;
        if (btnCenter.x > self.bounds.size.width - halfW) btnCenter.x = self.bounds.size.width - halfW;
        if (btnCenter.y < halfH) btnCenter.y = halfH;
        if (btnCenter.y > self.bounds.size.height - halfH) btnCenter.y = self.bounds.size.height - halfH;
        floatingButton.center = btnCenter;
    }
}

- (void)showMenu {
    menuContainer.hidden = NO;
    floatingButton.hidden = YES;
    menuContainer.transform = CGAffineTransformMakeScale(0.1, 0.1);
    [self centerMenu];
    [UIView animateWithDuration:0.3 animations:^{
        self->menuContainer.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [self centerMenu];
    }];
    [self updatePreviewVisibility];
}

- (void)hideMenu {
    [UIView animateWithDuration:0.3 animations:^{
        self->menuContainer.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        self->menuContainer.hidden = YES;
        self->floatingButton.hidden = NO;
        self->menuContainer.transform = CGAffineTransformIdentity;
    }];
}

- (void)centerMenu {
    menuContainer.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
}

- (void)handleTabTap:(UITapGestureRecognizer *)gr {
    NSInteger tag = gr.view.tag;
    if (tag >= 100 && tag <= 103) {
        [self switchToTab:(int)(tag - 100)];
    }
}

- (void)handleCloseTap:(UITapGestureRecognizer *)gr { [self hideMenu]; }

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *viewToMove = (gesture.view == floatingButton) ? floatingButton : menuContainer;
    CGPoint translation = [gesture translationInView:self];
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        viewToMove.center = CGPointMake(viewToMove.center.x + translation.x, viewToMove.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:self];
    }
}

// --- Toggle Handlers ---
- (void)toggleBox:(CustomSwitch *)sender { isBox = sender.isOn; boxContainer.hidden = !isBox; espLog(@"Toggle Box"); }
- (void)toggleBone:(CustomSwitch *)sender { isBone = sender.isOn; skeletonContainer.hidden = !isBone; espLog(@"Toggle Bone"); }
- (void)toggleHealth:(CustomSwitch *)sender { isHealth = sender.isOn; healthBarContainer.hidden = !isHealth; espLog(@"Toggle Health"); }
- (void)toggleName:(CustomSwitch *)sender { isName = sender.isOn; previewNameLabel.hidden = !isName; espLog(@"Toggle Name"); }
- (void)toggleDist:(CustomSwitch *)sender { isDis = sender.isOn; previewDistLabel.hidden = !isDis; espLog(@"Toggle Dist"); }
- (void)toggleLine:(CustomSwitch *)sender { isLine = sender.isOn; espLog(@"Toggle Line"); }
- (void)toggleAimbot:(CustomSwitch *)sender { isAimbot = sender.isOn; espLog(@"Toggle Aimbot"); }
- (void)toggleStreamerMode:(CustomSwitch *)sender {
    isStreamerMode = sender.isOn;
    __applyHideCapture(menuContainer, isStreamerMode);
    __applyHideCapture(floatingButton, isStreamerMode);
    espLog(@"Toggle StreamerMode");
}

- (void)updateFrame {
    // ESP Rendering Logic...
}

- (void)SetUpBase {
    // Offset Decryption Logic...
}

- (void)appDidBecomeActive {
    [self SetUpBase];
}

@end
