#import "esp.h"
#import <objc/runtime.h>

extern void writeLog(NSString *msg);
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

#define OFF_ROTATION         ENCRYPTOFFSET("0x53C")
#define OFF_FIRING           ENCRYPTOFFSET("0x750")
#define OFF_IPRIDATAPOOL     ENCRYPTOFFSET("0x68")
#define OFF_PLAYERID         ENCRYPTOFFSET("0x338")
#define OFF_CAMERA_TRANSFORM ENCRYPTOFFSET("0x318")
#define OFF_HEAD_NODE        ENCRYPTOFFSET("0x5B8")
#define OFF_HIP_NODE         ENCRYPTOFFSET("0x5C0")
#define OFF_LEFTANKLE_NODE   ENCRYPTOFFSET("0x5F0")
#define OFF_RIGHTANKLE_NODE  ENCRYPTOFFSET("0x5F8")
#define OFF_RIGHTTOE_NODE    ENCRYPTOFFSET("0x608")
#define OFF_LEFTARM_NODE     ENCRYPTOFFSET("0x620")
#define OFF_LEFTFOREARM_NODE ENCRYPTOFFSET("0x648")
#define OFF_LEFTHAND_NODE    ENCRYPTOFFSET("0x638")
#define OFF_RIGHTARM_NODE    ENCRYPTOFFSET("0x628")
#define OFF_RIGHTFOREARM_NODE ENCRYPTOFFSET("0x640")
#define OFF_RIGHTHAND_NODE   ENCRYPTOFFSET("0x630")
#define OFF_MATCH            ENCRYPTOFFSET("0x90")
#define OFF_LOCALPLAYER      ENCRYPTOFFSET("0xB0")
#define OFF_CAMERA_MGR       ENCRYPTOFFSET("0xD8")
#define OFF_CAMERA_MGR2      ENCRYPTOFFSET("0x18")
#define OFF_MATRIX_BASE      ENCRYPTOFFSET("0xD8")
#define OFF_CAM_V1           ENCRYPTOFFSET("0x10")
#define OFF_PLAYERLIST       ENCRYPTOFFSET("0x120")
#define OFF_PLAYERLIST_ARR   ENCRYPTOFFSET("0x28")
#define OFF_PLAYERLIST_CNT   ENCRYPTOFFSET("0x18")
#define OFF_PLAYERLIST_ITEM  ENCRYPTOFFSET("0x20")
#define OFF_GAMEFACADE_TI    ENCRYPTOFFSET("0xA4D2968")
#define OFF_GAMEFACADE_ST    ENCRYPTOFFSET("0xB8")
#define OFF_BODYPART_POS     ENCRYPTOFFSET("0x10")

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

uint64_t Moudule_Base = (uint64_t)-1;

static const char kSegHandlerKey = 0;

static bool isBox    = YES;
static bool isBone   = YES;
static bool isHealth = YES;
static bool isName   = YES;
static bool isDis    = YES;
static bool isLine   = NO;
static int  lineOrigin = 1;

static bool  isAimbot     = NO;
static float aimFov       = 150.0f;
static float aimDistance  = 200.0f;
static int   aimMode      = 1;
static int   aimTrigger   = 1;
static int   aimTarget    = 0;
static float aimSpeed     = 1.0f;
static bool  isStreamerMode = NO;

// ---------------------------------------------------------------
#pragma mark - CustomSwitch
// ---------------------------------------------------------------
@interface CustomSwitch : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@end

@implementation CustomSwitch { UIView *_thumb; BOOL _touchActive; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 22, 22)];
        _thumb.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _thumb.layer.cornerRadius = 11;
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    return [self pointInside:point withEvent:event] ? self : nil;
}

// ФИКС залипания: анимация alpha + сброс в cancelled
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touchActive = YES;
    [UIView animateWithDuration:0.05 animations:^{ self.alpha = 0.75f; }];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint pt = [touches.anyObject locationInView:self];
    if (pt.x < -10 || pt.x > self.bounds.size.width + 10 ||
        pt.y < -10 || pt.y > self.bounds.size.height + 10) {
        _touchActive = NO;
        [UIView animateWithDuration:0.1 animations:^{ self.alpha = 1.0f; }];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [UIView animateWithDuration:0.1 animations:^{ self.alpha = 1.0f; }];
    if (_touchActive) {
        CGPoint pt = [touches.anyObject locationInView:self];
        if ([self pointInside:pt withEvent:event]) [self toggle];
    }
    _touchActive = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touchActive = NO;
    [UIView animateWithDuration:0.1 animations:^{ self.alpha = 1.0f; }];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                   cornerRadius:self.bounds.size.height / 2];
    CGContextSetFillColorWithColor(ctx,
        (self.isOn
            ? [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0]
            : [UIColor colorWithWhite:0.15 alpha:1.0]).CGColor);
    [path fill];
}

- (void)setOn:(BOOL)on {
    if (_on != on) { _on = on; [self setNeedsDisplay]; [self updateThumbPosition]; }
}

- (void)toggle {
    self.on = !self.on;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)updateThumbPosition {
    [UIView animateWithDuration:0.2 animations:^{
        CGRect f = self->_thumb.frame;
        f.origin.x = self.isOn ? self.bounds.size.width - f.size.width - 2 : 2;
        self->_thumb.frame = f;
        self->_thumb.backgroundColor = self.isOn
            ? UIColor.whiteColor
            : [UIColor colorWithWhite:0.75 alpha:1.0];
    }];
}
@end

// ---------------------------------------------------------------
#pragma mark - ExpandedHitView
// ---------------------------------------------------------------
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

// ---------------------------------------------------------------
#pragma mark - HUDSlider
// ---------------------------------------------------------------
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
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _minimumValue = 0; _maximumValue = 1; _value = 0;
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
    _track = [[UIView alloc] initWithFrame:CGRectMake(10, (h-trackH)/2, w-20, trackH)];
    _track.backgroundColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    _track.layer.cornerRadius = trackH/2;
    _track.userInteractionEnabled = NO;
    [self addSubview:_track];
    _fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, trackH)];
    _fill.layer.cornerRadius = trackH/2;
    _fill.userInteractionEnabled = NO;
    [_track addSubview:_fill];
    CGFloat ts = 22;
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ts, ts)];
    _thumb.layer.cornerRadius = ts/2;
    _thumb.userInteractionEnabled = NO;
    [self addSubview:_thumb];
    [self updateAppearance];
    [self updateThumbPosition];
}

- (void)updateAppearance {
    _fill.backgroundColor  = _minimumTrackTintColor ?: [UIColor systemBlueColor];
    _thumb.backgroundColor = _thumbTintColor ?: [UIColor whiteColor];
}

- (void)setValue:(float)v {
    _value = MAX(_minimumValue, MIN(_maximumValue, v));
    [self updateThumbPosition];
}
- (void)setMinimumTrackTintColor:(UIColor *)c { _minimumTrackTintColor = c; [self updateAppearance]; }
- (void)setThumbTintColor:(UIColor *)c        { _thumbTintColor = c;        [self updateAppearance]; }

- (void)updateThumbPosition {
    if (!_track) return;
    CGFloat range = _maximumValue - _minimumValue;
    CGFloat pct   = (range > 0) ? (_value - _minimumValue) / range : 0;
    CGFloat trkW  = _track.bounds.size.width;
    CGFloat x     = pct * trkW;
    _fill.frame   = CGRectMake(0, 0, x, _track.bounds.size.height);
    CGFloat ts    = _thumb.bounds.size.width;
    _thumb.frame  = CGRectMake(_track.frame.origin.x + x - ts/2,
                               (self.bounds.size.height - ts)/2, ts, ts);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)handleTouch:(UITouch *)touch {
    CGPoint loc  = [touch locationInView:self];
    CGFloat trkW = _track.bounds.size.width;
    CGFloat trkX = _track.frame.origin.x;
    CGFloat pct  = MAX(0, MIN(1, (loc.x - trkX) / trkW));
    _value = _minimumValue + pct * (_maximumValue - _minimumValue);
    [self updateThumbPosition];
    if (_onValueChanged) _onValueChanged(_value);
}
@end

// ---------------------------------------------------------------
#pragma mark - Stream Proof helper
// ---------------------------------------------------------------
static BOOL __applyHideCapture(UIView *v, BOOL hidden) {
    static NSString *maskKey = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *d = [[NSData alloc] initWithBase64EncodedString:@"ZGlzYWJsZVVwZGF0ZU1hc2s="
                                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (d) maskKey = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    });
    if (!v || !maskKey || ![v.layer respondsToSelector:NSSelectorFromString(maskKey)]) return NO;
    [v.layer setValue:@(hidden ? ((1<<1)|(1<<4)) : 0) forKey:maskKey];
    return YES;
}

// ---------------------------------------------------------------
#pragma mark - MenuView interface
// ---------------------------------------------------------------
@interface MenuView ()
@property (nonatomic, strong) CADisplayLink         *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers;
@end

// ---------------------------------------------------------------
#pragma mark - MenuView implementation
// ---------------------------------------------------------------
@implementation MenuView {
    UIView  *menuContainer;
    UIView  *floatingButton;

    UIView  *mainTabContainer;
    UIView  *aimTabContainer;
    UIView  *settingTabContainer;
    UIView  *extraTabContainer;
    UIView  *_sidebar;

    UIView  *previewView;
    UIView  *previewContentContainer;
    UILabel *previewNameLabel;
    UILabel *previewDistLabel;
    UIView  *healthBarContainer;
    UIView  *boxContainer;
    UIView  *skeletonContainer;

    float   previewScale;

    // ФИКС перезахода в игру
    pid_t          _lastGamePid;
    NSTimeInterval _lastReconnectAttempt;
}

// ---------------------------------------------------------------
#pragma mark - Init
// ---------------------------------------------------------------
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.drawingLayers   = [NSMutableArray array];
        _lastGamePid         = -1;
        _lastReconnectAttempt = 0;

        [self SetUpBase];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        if (@available(iOS 15.0, *)) {
            self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(15, 20, 20);
        } else {
            self.displayLink.preferredFramesPerSecond = 20;
        }
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [self setupFloatingButton];
        [self setupMenuUI];
        [self layoutSubviews];
    }
    return self;
}

// ---------------------------------------------------------------
#pragma mark - ФИКС 1: SetUpBase — reconnect при перезаходе в игру
// ---------------------------------------------------------------
- (void)SetUpBase {
    pid_t currentPid = GetGameProcesspid((char*)ENCRYPT("freefireth"));
    if (currentPid == -1) {
        Moudule_Base  = (uint64_t)-1;
        get_task      = MACH_PORT_NULL;
        _lastGamePid  = -1;
        return;
    }
    if (currentPid != _lastGamePid) {
        get_task = MACH_PORT_NULL;
        kern_return_t kr = task_for_pid(mach_task_self(), currentPid, &get_task);
        if (kr != KERN_SUCCESS || get_task == MACH_PORT_NULL) {
            Moudule_Base = (uint64_t)-1;
            _lastGamePid = -1;
            return;
        }
        _lastGamePid  = currentPid;
        Moudule_Base  = (uint64_t)GetGameModule_Base((char*)ENCRYPT("freefireth"));
    }
}

// ---------------------------------------------------------------
#pragma mark - ФИКС 2: updateFrame — защита от краша + reconnect
// ---------------------------------------------------------------
- (void)updateFrame {
    if (!self.window) return;

    NSTimeInterval now = CACurrentMediaTime();
    if (Moudule_Base == (uint64_t)-1 || get_task == MACH_PORT_NULL) {
        if (now - _lastReconnectAttempt > 2.0) {
            _lastReconnectAttempt = now;
            [self SetUpBase];
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    for (CALayer *l in self.drawingLayers) [l removeFromSuperlayer];
    [self.drawingLayers removeAllObjects];

    @try {
        if (isAimbot) {
            float sx = self.bounds.size.width  / 2;
            float sy = self.bounds.size.height / 2;
            CAShapeLayer *cl = [CAShapeLayer layer];
            UIBezierPath *p  = [UIBezierPath bezierPathWithArcCenter:CGPointMake(sx, sy)
                                                              radius:aimFov
                                                          startAngle:0
                                                            endAngle:2*M_PI
                                                           clockwise:YES];
            cl.path        = p.CGPath;
            cl.fillColor   = [UIColor clearColor].CGColor;
            cl.strokeColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.5].CGColor;
            cl.lineWidth   = 1.0;
            [self.drawingLayers addObject:cl];
        }
        [self renderESPToLayers:self.drawingLayers];
    } @catch (NSException *e) {
        espLog([NSString stringWithFormat:@"[ESP] exception: %@", e]);
    }

    for (CALayer *l in self.drawingLayers) [self.layer addSublayer:l];
    [CATransaction commit];
}

// ---------------------------------------------------------------
#pragma mark - hitTest
// ---------------------------------------------------------------
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    if (!menuContainer || menuContainer.hidden) {
        if (floatingButton && !floatingButton.hidden) {
            CGPoint p = [self convertPoint:point toView:floatingButton];
            if ([floatingButton pointInside:p withEvent:event]) return floatingButton;
        }
        return nil;
    }
    CGPoint pInMenu = [self convertPoint:point toView:menuContainer];
    if ([menuContainer pointInside:pInMenu withEvent:event]) {
        UIView *hit = [menuContainer hitTest:pInMenu withEvent:event];
        return hit ?: menuContainer;
    }
    return nil;
}

// ---------------------------------------------------------------
#pragma mark - Floating button
// ---------------------------------------------------------------
- (void)setupFloatingButton {
    floatingButton = [[UIView alloc] initWithFrame:CGRectMake(50, 150, 54, 54)];
    floatingButton.backgroundColor    = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0];
    floatingButton.layer.cornerRadius = 27;
    floatingButton.layer.borderWidth  = 2;
    floatingButton.layer.borderColor  = [UIColor whiteColor].CGColor;
    floatingButton.clipsToBounds      = YES;
    floatingButton.userInteractionEnabled = YES;

    UILabel *icon = [[UILabel alloc] initWithFrame:floatingButton.bounds];
    icon.text = @"M"; icon.textColor = [UIColor whiteColor];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.font = [UIFont boldSystemFontOfSize:22];
    icon.userInteractionEnabled = NO;
    [floatingButton addSubview:icon];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.minimumNumberOfTouches = 1;
    [floatingButton addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showMenu)];
    tap.numberOfTapsRequired  = 1;
    tap.numberOfTouchesRequired = 1;
    [tap requireGestureRecognizerToFail:pan];
    [floatingButton addGestureRecognizer:tap];

    [self addSubview:floatingButton];
}

// ---------------------------------------------------------------
#pragma mark - UI helpers
// ---------------------------------------------------------------
- (void)addFeatureToView:(UIView *)view withTitle:(NSString *)title atY:(CGFloat)y
            initialValue:(BOOL)isOn andAction:(SEL)action {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 150, 26)];
    lbl.text = title; lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:13];
    [view addSubview:lbl];

    CGFloat swX = MIN(240, view.bounds.size.width - 65);
    CustomSwitch *sw = [[CustomSwitch alloc] initWithFrame:CGRectMake(swX, y, 52, 26)];
    sw.on = isOn;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [view addSubview:sw];
}

- (UILabel *)makeSectionLabel:(NSString *)title atY:(CGFloat)y width:(CGFloat)w {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, y, w, 16)];
    l.text = title;
    l.textColor = [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    l.font = [UIFont boldSystemFontOfSize:10];
    return l;
}

- (void)addSegmentTo:(UIView *)parent atY:(CGFloat)y title:(NSString *)title
             options:(NSArray *)options selectedRef:(int *)selectedRef tag:(NSInteger)baseTag {
    CGFloat pad = 10, segW = (parent.bounds.size.width - pad*2) / options.count, segH = 28;
    CGFloat titleH = (title.length > 0) ? 14 : 0;

    if (title.length > 0) {
        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, parent.bounds.size.width-pad*2, 12)];
        tl.text = title; tl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        tl.font = [UIFont systemFontOfSize:10]; tl.userInteractionEnabled = NO;
        [parent addSubview:tl];
    }

    UIView *seg = [[UIView alloc] initWithFrame:CGRectMake(pad, y+titleH, parent.bounds.size.width-pad*2, segH)];
    seg.backgroundColor  = [UIColor colorWithRed:0.12 green:0.12 blue:0.18 alpha:1.0];
    seg.layer.cornerRadius = 7; seg.clipsToBounds = YES;
    [parent addSubview:seg];

    for (int i = 0; i < (int)options.count; i++) {
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(i*segW+2, 2, segW-4, segH-4)];
        btn.backgroundColor = (*selectedRef == i)
            ? [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0]
            : [UIColor clearColor];
        btn.layer.cornerRadius = 5; btn.tag = baseTag*100+i; btn.userInteractionEnabled = NO;
        UILabel *l = [[UILabel alloc] initWithFrame:btn.bounds];
        l.text = options[i]; l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:10];
        l.textColor = (*selectedRef == i) ? [UIColor blackColor] : [UIColor colorWithWhite:0.7 alpha:1.0];
        l.userInteractionEnabled = NO;
        [btn addSubview:l]; [seg addSubview:btn];
    }

    NSInteger cb = baseTag; UIView * __unsafe_unretained sr = seg;
    int *ref = selectedRef; NSArray *opts = options;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] init];
    tap.cancelsTouchesInView = NO;
    objc_setAssociatedObject(tap, &kSegHandlerKey, ^(UITapGestureRecognizer *t) {
        CGPoint loc = [t locationInView:sr];
        int idx = (int)(loc.x / (sr.bounds.size.width / opts.count));
        idx = MAX(0, MIN((int)opts.count-1, idx));
        *ref = idx;
        for (int j = 0; j < (int)opts.count; j++) {
            UIView *b = [sr viewWithTag:cb*100+j];
            b.backgroundColor = (j == idx)
                ? [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0]
                : [UIColor clearColor];
            UILabel *l = b.subviews.firstObject;
            l.textColor = (j == idx) ? [UIColor blackColor] : [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [tap addTarget:self action:@selector(handleSegmentTapGesture:)];
    [seg addGestureRecognizer:tap];
}

// ---------------------------------------------------------------
#pragma mark - setupMenuUI
// ---------------------------------------------------------------
- (void)setupMenuUI {
    CGFloat screenW  = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH  = [UIScreen mainScreen].bounds.size.height;
    CGFloat menuW    = MIN(550, screenW - 10);
    CGFloat menuH    = MIN(370, screenH * 0.55);
    CGFloat scale    = menuW / 550.0;

    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuW, menuH)];
    menuContainer.backgroundColor    = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 15;
    menuContainer.layer.borderColor  = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    menuContainer.layer.borderWidth  = 2;
    menuContainer.clipsToBounds      = NO;
    menuContainer.hidden             = YES;
    [self addSubview:menuContainer];

    // Header
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuW, 40)];
    hdr.backgroundColor = [UIColor clearColor]; hdr.userInteractionEnabled = YES;
    [menuContainer addSubview:hdr];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(menuW*0.25, 5, menuW*0.45, 30)];
    title.text = @"MENU TIPA"; title.textColor = [UIColor whiteColor];
    title.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:22];
    [hdr addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(menuW*0.58, 12, menuW*0.3, 20)];
    sub.text = @"Fryzz🥶"; sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:10]; [hdr addSubview:sub];

    NSArray *colors = @[[UIColor greenColor],[UIColor yellowColor],[UIColor redColor]];
    for (int i = 0; i < 3; i++) {
        UIView *c = [[UIView alloc] initWithFrame:CGRectMake(menuW-95+(i*25), 10, 18, 18)];
        c.backgroundColor = colors[i]; c.layer.cornerRadius = 9;
        UILabel *ic = [[UILabel alloc] initWithFrame:c.bounds];
        ic.textAlignment = NSTextAlignmentCenter;
        ic.font = [UIFont boldSystemFontOfSize:12]; ic.textColor = [UIColor blackColor];
        if (i==0) ic.text=@"□"; if (i==1) ic.text=@"-"; if (i==2) { ic.text=@"X"; c.tag=200; UITapGestureRecognizer *ct=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleCloseTap:)]; [c addGestureRecognizer:ct]; }
        [c addSubview:ic]; [hdr addSubview:c];
    }
    UIPanGestureRecognizer *mp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [hdr addGestureRecognizer:mp];

    // Sidebar
    CGFloat sbW = 75 * scale;
    UIView *sb  = [[UIView alloc] initWithFrame:CGRectMake(menuW-sbW-10, 50, sbW, 310*scale)];
    sb.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    sb.layer.cornerRadius = 10; sb.userInteractionEnabled = YES; _sidebar = sb;
    [menuContainer addSubview:sb];

    NSArray *tabs = @[@"Main",@"AIM",@"Extra",@"Setting"];
    for (int i = 0; i < (int)tabs.count; i++) {
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(3, 8+(i*50*scale), sbW-6, 35*scale)];
        btn.backgroundColor    = (i==0) ? [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0]
                                         : [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        btn.layer.cornerRadius = 17.5; btn.userInteractionEnabled = YES; btn.tag = 100+i;
        UILabel *bl = [[UILabel alloc] initWithFrame:btn.bounds];
        bl.text = tabs[i]; bl.textColor = [UIColor whiteColor];
        bl.font = [UIFont boldSystemFontOfSize:11]; bl.textAlignment = NSTextAlignmentCenter;
        bl.userInteractionEnabled = NO; [btn addSubview:bl];
        UITapGestureRecognizer *tt = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTabTap:)];
        [btn addGestureRecognizer:tt]; [sb addSubview:btn];
    }

    CGFloat tabW = menuW - sbW - 25;
    CGFloat tabH = menuH - 55;

    // --- MAIN TAB ---
    mainTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    mainTabContainer.backgroundColor = [UIColor clearColor];
    [menuContainer addSubview:mainTabContainer];

    UIView *pvBorder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 130, 250)];
    pvBorder.layer.borderColor  = [UIColor whiteColor].CGColor;
    pvBorder.layer.borderWidth  = 1; pvBorder.layer.cornerRadius = 10;
    [mainTabContainer addSubview:pvBorder];

    UILabel *pvT = [[UILabel alloc] initWithFrame:CGRectMake(0, 5, 130, 20)];
    pvT.text = @"Preview"; pvT.textColor = [UIColor whiteColor];
    pvT.textAlignment = NSTextAlignmentCenter; pvT.font = [UIFont boldSystemFontOfSize:14];
    [pvBorder addSubview:pvT];

    UIView *pvLine = [[UIView alloc] initWithFrame:CGRectMake(10, 28, 110, 1)];
    pvLine.backgroundColor = [UIColor whiteColor]; [pvBorder addSubview:pvLine];

    previewView = [[UIView alloc] initWithFrame:CGRectMake(0, 30, 130, 220)];
    previewView.backgroundColor = [UIColor blackColor]; previewView.clipsToBounds = YES;
    [pvBorder addSubview:previewView];
    previewContentContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewView addSubview:previewContentContainer];
    [self drawPreviewElements];
    [self updatePreviewVisibility];

    UIView *ftBox = [[UIView alloc] initWithFrame:CGRectMake(140, 0, tabW-145, tabH)];
    ftBox.layer.borderColor = [UIColor whiteColor].CGColor; ftBox.layer.borderWidth = 1;
    ftBox.layer.cornerRadius = 10; ftBox.backgroundColor = [UIColor blackColor];
    [mainTabContainer addSubview:ftBox];

    UILabel *ftT = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    ftT.text = @"ESP Feature"; ftT.textColor = [UIColor whiteColor];
    ftT.font = [UIFont boldSystemFontOfSize:16]; [ftBox addSubview:ftT];

    UIView *ftL = [[UIView alloc] initWithFrame:CGRectMake(15, 35, tabW-155, 1)];
    ftL.backgroundColor = [UIColor whiteColor]; [ftBox addSubview:ftL];

    [self addFeatureToView:ftBox withTitle:@"Box"      atY:45  initialValue:isBox    andAction:@selector(toggleBox:)];
    [self addFeatureToView:ftBox withTitle:@"Bone"     atY:80  initialValue:isBone   andAction:@selector(toggleBone:)];
    [self addFeatureToView:ftBox withTitle:@"Health"   atY:115 initialValue:isHealth andAction:@selector(toggleHealth:)];
    [self addFeatureToView:ftBox withTitle:@"Name"     atY:150 initialValue:isName   andAction:@selector(toggleName:)];
    [self addFeatureToView:ftBox withTitle:@"Distance" atY:185 initialValue:isDis    andAction:@selector(toggleDist:)];
    [self addFeatureToView:ftBox withTitle:@"Lines"    atY:220 initialValue:isLine   andAction:@selector(toggleLine:)];
    [self addSegmentTo:ftBox atY:256 title:@"" options:@[@"Top",@"Center",@"Bottom"] selectedRef:&lineOrigin tag:20];

    // --- AIM TAB ---
    aimTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15,50,tabW,tabH)];
    aimTabContainer.backgroundColor = [UIColor blackColor];
    aimTabContainer.layer.borderColor = [UIColor whiteColor].CGColor; aimTabContainer.layer.borderWidth = 1;
    aimTabContainer.layer.cornerRadius = 10; aimTabContainer.hidden = YES;
    [menuContainer addSubview:aimTabContainer];

    CGFloat aW = aimTabContainer.bounds.size.width, ay = 6;
    [aimTabContainer addSubview:[self makeSectionLabel:@"AIMBOT" atY:ay width:aW]]; ay+=18;
    UIView *as1=[[UIView alloc]initWithFrame:CGRectMake(10,ay,aW-20,1)];
    as1.backgroundColor=[UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];
    [aimTabContainer addSubview:as1]; ay+=6;
    [self addFeatureToView:aimTabContainer withTitle:@"Enable Aimbot" atY:ay initialValue:isAimbot andAction:@selector(toggleAimbot:)]; ay+=30;
    ay+=4;
    UIView *as2=[[UIView alloc]initWithFrame:CGRectMake(10,ay,aW-20,1)];
    as2.backgroundColor=as1.backgroundColor; [aimTabContainer addSubview:as2]; ay+=6;
    [aimTabContainer addSubview:[self makeSectionLabel:@"AIM MODE" atY:ay width:aW]]; ay+=16;
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:@[@"Closest Player",@"Crosshair"] selectedRef:&aimMode tag:10]; ay+=32;
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:@[@"Head",@"Neck",@"Hip"] selectedRef:&aimTarget tag:11]; ay+=32;
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:@[@"Always",@"Shooting"] selectedRef:&aimTrigger tag:12];

    // --- EXTRA TAB ---
    extraTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15,50,tabW,tabH)];
    extraTabContainer.backgroundColor = [UIColor blackColor];
    extraTabContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    extraTabContainer.layer.borderWidth = 1; extraTabContainer.layer.cornerRadius = 10;
    extraTabContainer.hidden = YES; [menuContainer addSubview:extraTabContainer];

    CGFloat eW = extraTabContainer.bounds.size.width, ey = 10;
    [extraTabContainer addSubview:[self makeSectionLabel:@"PARAMETERS" atY:ey width:eW]]; ey+=22;
    UIView *es1=[[UIView alloc]initWithFrame:CGRectMake(10,ey,eW-20,1)];
    es1.backgroundColor=[UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];
    [extraTabContainer addSubview:es1]; ey+=10;

    // FOV slider
    UILabel *fL=[[UILabel alloc]initWithFrame:CGRectMake(15,ey,eW-60,14)];
    fL.text=@"FOV Radius";fL.textColor=[UIColor colorWithWhite:0.6 alpha:1.0];fL.font=[UIFont systemFontOfSize:10];[extraTabContainer addSubview:fL];
    UILabel *fV=[[UILabel alloc]initWithFrame:CGRectMake(eW-45,ey,40,14)];
    fV.text=[NSString stringWithFormat:@"%.0f",aimFov];fV.textColor=[UIColor colorWithWhite:0.5 alpha:1.0];fV.font=[UIFont systemFontOfSize:10];fV.textAlignment=NSTextAlignmentRight;[extraTabContainer addSubview:fV];ey+=16;
    HUDSlider *fS=[[HUDSlider alloc]initWithFrame:CGRectMake(10,ey,eW-20,36)];
    fS.minimumValue=10;fS.maximumValue=400;fS.value=aimFov;
    fS.minimumTrackTintColor=[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
    fS.thumbTintColor=[UIColor whiteColor];fS.tag=300;
    UILabel *__unsafe_unretained fvR=fV;
    fS.onValueChanged=^(float v){aimFov=v;fvR.text=[NSString stringWithFormat:@"%.0f",v];};
    [extraTabContainer addSubview:fS];ey+=44;

    // Distance slider
    UILabel *dL=[[UILabel alloc]initWithFrame:CGRectMake(15,ey,eW-60,14)];
    dL.text=@"Aim Distance";dL.textColor=[UIColor colorWithWhite:0.6 alpha:1.0];dL.font=[UIFont systemFontOfSize:10];[extraTabContainer addSubview:dL];
    UILabel *dV=[[UILabel alloc]initWithFrame:CGRectMake(eW-45,ey,40,14)];
    dV.text=[NSString stringWithFormat:@"%.0f",aimDistance];dV.textColor=[UIColor colorWithWhite:0.5 alpha:1.0];dV.font=[UIFont systemFontOfSize:10];dV.textAlignment=NSTextAlignmentRight;[extraTabContainer addSubview:dV];ey+=16;
    HUDSlider *dS=[[HUDSlider alloc]initWithFrame:CGRectMake(10,ey,eW-20,36)];
    dS.minimumValue=10;dS.maximumValue=500;dS.value=aimDistance;
    dS.minimumTrackTintColor=[UIColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:1.0];
    dS.thumbTintColor=[UIColor whiteColor];dS.tag=301;
    UILabel *__unsafe_unretained dvR=dV;
    dS.onValueChanged=^(float v){aimDistance=v;dvR.text=[NSString stringWithFormat:@"%.0f",v];};
    [extraTabContainer addSubview:dS];ey+=44;

    // Speed slider
    UILabel *sL=[[UILabel alloc]initWithFrame:CGRectMake(15,ey,eW-60,14)];
    sL.text=@"Aim Speed";sL.textColor=[UIColor colorWithWhite:0.6 alpha:1.0];sL.font=[UIFont systemFontOfSize:10];[extraTabContainer addSubview:sL];
    UILabel *sV=[[UILabel alloc]initWithFrame:CGRectMake(eW-45,ey,40,14)];
    sV.text=[NSString stringWithFormat:@"%.2f",aimSpeed];sV.textColor=[UIColor colorWithWhite:0.5 alpha:1.0];sV.font=[UIFont systemFontOfSize:10];sV.textAlignment=NSTextAlignmentRight;[extraTabContainer addSubview:sV];ey+=16;
    HUDSlider *sS=[[HUDSlider alloc]initWithFrame:CGRectMake(10,ey,eW-20,36)];
    sS.minimumValue=0.05;sS.maximumValue=1.0;sS.value=aimSpeed;
    sS.minimumTrackTintColor=[UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:1.0];
    sS.thumbTintColor=[UIColor whiteColor];sS.tag=302;
    UILabel *__unsafe_unretained svR=sV;
    sS.onValueChanged=^(float v){aimSpeed=v;svR.text=[NSString stringWithFormat:@"%.2f",v];};
    [extraTabContainer addSubview:sS];

    // --- SETTING TAB ---
    settingTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15,50,tabW,tabH)];
    settingTabContainer.backgroundColor = [UIColor blackColor];
    settingTabContainer.layer.borderColor=[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    settingTabContainer.layer.borderWidth=1;settingTabContainer.layer.cornerRadius=10;
    settingTabContainer.hidden=YES;[menuContainer addSubview:settingTabContainer];

    UILabel *stT=[[UILabel alloc]initWithFrame:CGRectMake(15,12,tabW-30,18)];
    stT.text=@"SETTINGS";stT.textColor=[UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    stT.font=[UIFont boldSystemFontOfSize:11];[settingTabContainer addSubview:stT];
    UIView *stS=[[UIView alloc]initWithFrame:CGRectMake(15,33,tabW-30,1)];
    stS.backgroundColor=[UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];[settingTabContainer addSubview:stS];
    [self addFeatureToView:settingTabContainer withTitle:@"Stream Proof" atY:40 initialValue:isStreamerMode andAction:@selector(toggleStreamerMode:)];
    UILabel *stD=[[UILabel alloc]initWithFrame:CGRectMake(15,80,tabW-30,32)];
    stD.text=@"Hides the overlay from screen recordings & screenshots.";
    stD.textColor=[UIColor colorWithWhite:0.5 alpha:1.0];stD.font=[UIFont systemFontOfSize:10];stD.numberOfLines=2;[settingTabContainer addSubview:stD];

    [menuContainer bringSubviewToFront:sb];
}

// ---------------------------------------------------------------
#pragma mark - Tab switching
// ---------------------------------------------------------------
- (void)switchToTab:(NSInteger)idx {
    for (UIView *v in @[mainTabContainer,aimTabContainer,extraTabContainer,settingTabContainer]) {
        v.hidden = YES; v.userInteractionEnabled = NO;
    }
    for (UIView *s in _sidebar.subviews) {
        if (s.tag>=100 && s.tag<=103)
            s.backgroundColor=[UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    }
    [_sidebar viewWithTag:100+idx].backgroundColor=[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
    NSArray *tabs=@[mainTabContainer,aimTabContainer,extraTabContainer,settingTabContainer];
    if (idx < (NSInteger)tabs.count) {
        UIView *t = tabs[idx]; t.hidden = NO; t.userInteractionEnabled = YES;
    }
}

// ---------------------------------------------------------------
#pragma mark - Preview
// ---------------------------------------------------------------
- (void)drawPreviewElements {
    CGFloat w=previewView.frame.size.width,h=previewView.frame.size.height,cx=w/2,startY=45;

    previewNameLabel=[[UILabel alloc]initWithFrame:CGRectMake(0,20,w,15)];
    previewNameLabel.text=@"ID PlayerName";previewNameLabel.textColor=[UIColor greenColor];
    previewNameLabel.textAlignment=NSTextAlignmentCenter;previewNameLabel.font=[UIFont boldSystemFontOfSize:11];
    [previewContentContainer addSubview:previewNameLabel];

    CGFloat bW=70;
    healthBarContainer=[[UIView alloc]initWithFrame:CGRectMake(cx-bW/2,38,bW,2)];
    healthBarContainer.backgroundColor=[UIColor greenColor];[previewContentContainer addSubview:healthBarContainer];

    CGFloat boxW=70,boxH=130,bx=cx-boxW/2,by=startY;
    boxContainer=[[UIView alloc]initWithFrame:previewView.bounds];[previewContentContainer addSubview:boxContainer];
    CGFloat ll=15;UIColor *bc=[UIColor whiteColor];
    [self addLineRect:CGRectMake(bx,by,ll,1) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx,by,1,ll) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx+boxW-ll,by,ll,1) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx+boxW,by,1,ll) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx,by+boxH,ll,1) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx,by+boxH-ll,1,ll) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx+boxW-ll,by+boxH,ll,1) color:bc parent:boxContainer];
    [self addLineRect:CGRectMake(bx+boxW,by+boxH-ll,1,ll) color:bc parent:boxContainer];

    skeletonContainer=[[UIView alloc]initWithFrame:previewView.bounds];[previewContentContainer addSubview:skeletonContainer];
    UIColor *sc=[UIColor whiteColor];CGFloat st=1.0;
    CGFloat hr=7,hY=by+15;
    UIView *hv=[[UIView alloc]initWithFrame:CGRectMake(cx-hr,hY-hr,hr*2,hr*2)];
    hv.layer.borderColor=sc.CGColor;hv.layer.borderWidth=st;hv.layer.cornerRadius=hr;[skeletonContainer addSubview:hv];
    CGPoint pN=CGPointMake(cx,hY+hr),pP=CGPointMake(cx,by+65);
    CGPoint pSL=CGPointMake(cx-15,by+30),pSR=CGPointMake(cx+15,by+30);
    CGPoint pEL=CGPointMake(cx-20,by+50),pER=CGPointMake(cx+20,by+50);
    CGPoint pHL=CGPointMake(cx-20,by+70),pHR=CGPointMake(cx+20,by+70);
    CGPoint pKL=CGPointMake(cx-12,by+95),pKR=CGPointMake(cx+12,by+95);
    CGPoint pFL=CGPointMake(cx-15,by+125),pFR=CGPointMake(cx+15,by+125);
    [self addLineFrom:pN to:pP color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pSL to:pSR color:sc width:st inView:skeletonContainer];
    [self addLineFrom:CGPointMake(cx,by+30) to:pSL color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pSL to:pEL color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pEL to:pHL color:sc width:st inView:skeletonContainer];
    [self addLineFrom:CGPointMake(cx,by+30) to:pSR color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pSR to:pER color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pER to:pHR color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pP to:pKL color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pKL to:pFL color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pP to:pKR color:sc width:st inView:skeletonContainer];
    [self addLineFrom:pKR to:pFR color:sc width:st inView:skeletonContainer];

    previewDistLabel=[[UILabel alloc]initWithFrame:CGRectMake(0,by+boxH+5,w,15)];
    previewDistLabel.text=@"Distance";previewDistLabel.textColor=[UIColor whiteColor];
    previewDistLabel.textAlignment=NSTextAlignmentCenter;previewDistLabel.font=[UIFont systemFontOfSize:10];
    [previewContentContainer addSubview:previewDistLabel];
}

- (void)updatePreviewVisibility {
    boxContainer.hidden       = !isBox;
    skeletonContainer.hidden  = !isBone;
    healthBarContainer.hidden = !isHealth;
    previewNameLabel.hidden   = !isName;
    previewDistLabel.hidden   = !isDis;
    if (isBox && isBone) [previewContentContainer bringSubviewToFront:boxContainer];
}

// ---------------------------------------------------------------
#pragma mark - Toggle handlers
// ---------------------------------------------------------------
- (void)toggleBox:(CustomSwitch *)s    { isBox=s.isOn; boxContainer.hidden=!isBox; }
- (void)toggleBone:(CustomSwitch *)s   { isBone=s.isOn; skeletonContainer.hidden=!isBone; }
- (void)toggleHealth:(CustomSwitch *)s { isHealth=s.isOn; healthBarContainer.hidden=!isHealth; }
- (void)toggleName:(CustomSwitch *)s   { isName=s.isOn; previewNameLabel.hidden=!isName; }
- (void)toggleDist:(CustomSwitch *)s   { isDis=s.isOn; previewDistLabel.hidden=!isDis; }
- (void)toggleLine:(CustomSwitch *)s   { isLine=s.isOn; }
- (void)toggleAimbot:(CustomSwitch *)s { isAimbot=s.isOn; }
- (void)toggleStreamerMode:(CustomSwitch *)s {
    isStreamerMode=s.isOn;
    if (menuContainer)  __applyHideCapture(menuContainer,  isStreamerMode);
    if (floatingButton) __applyHideCapture(floatingButton, isStreamerMode);
    __applyHideCapture(self, isStreamerMode);
}

// ---------------------------------------------------------------
#pragma mark - Gesture handlers
// ---------------------------------------------------------------
- (void)handleSegmentTapGesture:(UITapGestureRecognizer *)t {
    void (^h)(UITapGestureRecognizer *)=objc_getAssociatedObject(t,&kSegHandlerKey);
    if (h) h(t);
}
- (void)handleTabTap:(UITapGestureRecognizer *)gr {
    NSInteger tag=gr.view.tag;
    if (tag>=100 && tag<=103) [self switchToTab:(int)(tag-100)];
}
- (void)handleCloseTap:(UITapGestureRecognizer *)gr { [self hideMenu]; }

- (void)handlePan:(UIPanGestureRecognizer *)gr {
    UIView *v=(gr.view==floatingButton)?floatingButton:menuContainer;
    CGPoint t=[gr translationInView:self];
    if (gr.state==UIGestureRecognizerStateBegan||gr.state==UIGestureRecognizerStateChanged) {
        v.center=CGPointMake(v.center.x+t.x, v.center.y+t.y);
        [gr setTranslation:CGPointZero inView:self];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {}

// ---------------------------------------------------------------
#pragma mark - Show / Hide / Center
// ---------------------------------------------------------------
- (void)showMenu {
    menuContainer.hidden=NO; floatingButton.hidden=YES;
    menuContainer.transform=CGAffineTransformMakeScale(0.1,0.1);
    [self centerMenu];
    [UIView animateWithDuration:0.3 animations:^{ self->menuContainer.transform=CGAffineTransformIdentity; }
                     completion:^(BOOL f){ [self centerMenu]; }];
    [self updatePreviewVisibility];
}
- (void)hideMenu {
    [UIView animateWithDuration:0.3
                     animations:^{ self->menuContainer.transform=CGAffineTransformMakeScale(0.1,0.1); }
                     completion:^(BOOL f){ self->menuContainer.hidden=YES; self->floatingButton.hidden=NO; self->menuContainer.transform=CGAffineTransformIdentity; }];
}
- (void)centerMenu {
    CGRect b=self.bounds;
    if (CGRectIsEmpty(b)) b=[UIScreen mainScreen].bounds;
    menuContainer.center=CGPointMake(b.size.width/2,b.size.height/2);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) {
        CGRect nf=self.superview.bounds;
        if (!CGSizeEqualToSize(self.frame.size,nf.size)) {
            self.frame=nf;
            if (menuContainer&&!menuContainer.hidden)
                menuContainer.center=CGPointMake(nf.size.width/2,nf.size.height/2);
        }
    }
    if (floatingButton) {
        CGRect sb=self.bounds;
        CGPoint c=floatingButton.center;
        CGFloat hw=floatingButton.bounds.size.width/2,hh=floatingButton.bounds.size.height/2;
        c.x=MAX(hw,MIN(sb.size.width-hw,c.x));
        c.y=MAX(hh,MIN(sb.size.height-hh,c.y));
        floatingButton.center=c;
    }
}

// ---------------------------------------------------------------
#pragma mark - Line helpers
// ---------------------------------------------------------------
- (void)addLineRect:(CGRect)f color:(UIColor *)c parent:(UIView *)p {
    UIView *v=[[UIView alloc]initWithFrame:f]; v.backgroundColor=c; [p addSubview:v];
}
- (void)addLineFrom:(CGPoint)p1 to:(CGPoint)p2 color:(UIColor *)c width:(CGFloat)w inView:(UIView *)v {
    CGFloat dx=p2.x-p1.x,dy=p2.y-p1.y,len=sqrt(dx*dx+dy*dy);
    UIView *l=[[UIView alloc]init]; l.backgroundColor=c;
    l.frame=CGRectMake(p1.x,p1.y,len,w);
    l.layer.anchorPoint=CGPointMake(0,0.5); l.center=p1;
    l.transform=CGAffineTransformMakeRotation(atan2(dy,dx));
    [v addSubview:l];
}

// ---------------------------------------------------------------
#pragma mark - dealloc
// ---------------------------------------------------------------
- (void)dealloc {
    [self.displayLink invalidate]; self.displayLink=nil;
}

// ---------------------------------------------------------------
#pragma mark - ESP render helpers
// ---------------------------------------------------------------
static inline void DrawBoneLine(NSMutableArray<CALayer *> *layers,
                                 CGPoint p1, CGPoint p2,
                                 UIColor *color, CGFloat width) {
    CGFloat dx=p2.x-p1.x,dy=p2.y-p1.y,len=sqrt(dx*dx+dy*dy);
    if (len<2.0f) return;
    CALayer *l=[CALayer layer];
    l.backgroundColor=color.CGColor;
    l.bounds=CGRectMake(0,0,len,width);
    l.position=p1; l.anchorPoint=CGPointMake(0,0.5);
    l.transform=CATransform3DMakeRotation(atan2(dy,dx),0,0,1);
    [layers addObject:l];
}

static Quaternion GetRotationToLocation(Vector3 target, float bias, Vector3 myLoc) {
    return Quaternion::LookRotation((target+Vector3(0,bias,0))-myLoc, Vector3(0,1,0));
}

static void set_aim(uint64_t player, Quaternion rot) {
    if (!isVaildPtr(player)) return;
    WriteAddr<Quaternion>(player+OFF_ROTATION, rot);
}

static bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<bool>(player+OFF_FIRING);
}

// ---------------------------------------------------------------
#pragma mark - renderESPToLayers
// ---------------------------------------------------------------
- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers {
    if (Moudule_Base==(uint64_t)-1 || get_task==MACH_PORT_NULL) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);
    if (!isVaildPtr(matchGame)) return;
    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) return;
    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) return;
    uint64_t myPawn = getLocalPlayer(match);
    if (!isVaildPtr(myPawn)) return;

    uint64_t camTransform = ReadAddr<uint64_t>(myPawn+OFF_CAMERA_TRANSFORM);
    Vector3 myLoc = getPositionExt(camTransform);

    uint64_t playerList = ReadAddr<uint64_t>(match+OFF_PLAYERLIST);
    uint64_t tVal       = ReadAddr<uint64_t>(playerList+OFF_PLAYERLIST_ARR);
    int cnt             = ReadAddr<int>(tVal+OFF_PLAYERLIST_CNT);

    // ФИКС 3: читаем матрицу одним vm_read (64 байта)
    uint64_t camV1  = ReadAddr<uint64_t>(camera+OFF_CAM_V1);
    static float matrix[16];
    _read(camV1+OFF_MATRIX_BASE, matrix, sizeof(float)*16);

    float vW = self.bounds.size.width;
    float vH = self.bounds.size.height;
    CGPoint center = CGPointMake(vW/2, vH/2);

    uint64_t bestTarget = 0;
    float    bestScore  = FLT_MAX;
    bool     isFire     = get_IsFiring(myPawn);

    for (int i = 0; i < cnt; i++) {
        uint64_t pawn = ReadAddr<uint64_t>(tVal+OFF_PLAYERLIST_ITEM+8*i);
        if (!isVaildPtr(pawn)) continue;
        if (isLocalTeamMate(myPawn, pawn)) continue;

        int curHP = get_CurHP(pawn);
        if (curHP <= 0) continue;

        Vector3 headPos = getPositionExt(getHead(pawn));
        float   dis     = Vector3::Distance(myLoc, headPos);
        if (dis > 400.0f) continue;

        // Aimbot
        if (isAimbot && dis <= aimDistance) {
            Vector3 aimPos = headPos;
            if (aimTarget==1) aimPos=headPos+Vector3(0,-0.15f,0);
            else if (aimTarget==2) aimPos=getPositionExt(getHip(pawn));

            Vector3 w2s = WorldToScreen(aimPos, matrix, vW, vH);
            float dx = w2s.x-center.x, dy = w2s.y-center.y;
            float d2c = sqrt(dx*dx+dy*dy);
            if (d2c <= aimFov) {
                float score = (aimMode==0) ? dis : d2c;
                if (score < bestScore) { bestScore=score; bestTarget=pawn; }
            }
        }

        if (dis > 220.0f) continue;

        Vector3 toePos  = getPositionExt(getRightToeNode(pawn));
        Vector3 hipPos  = getPositionExt(getHip(pawn));
        Vector3 lAnkle  = getPositionExt(getLeftAnkle(pawn));
        Vector3 rAnkle  = getPositionExt(getRightAnkle(pawn));
        Vector3 lShoulder = getPositionExt(getLeftShoulder(pawn));
        Vector3 rShoulder = getPositionExt(getRightShoulder(pawn));
        Vector3 lElbow  = getPositionExt(getLeftElbow(pawn));
        Vector3 rElbow  = getPositionExt(getRightElbow(pawn));
        Vector3 lHand   = getPositionExt(getLeftHand(pawn));
        Vector3 rHand   = getPositionExt(getRightHand(pawn));

        Vector3 headTop = headPos; headTop.y += 0.2f;
        Vector3 w2sHead = WorldToScreen(headTop, matrix, vW, vH);
        Vector3 w2sToe  = WorldToScreen(toePos,  matrix, vW, vH);
        Vector3 wHead   = WorldToScreen(headPos,  matrix, vW, vH);
        Vector3 wHip    = WorldToScreen(hipPos,   matrix, vW, vH);

        // Bones
        if (isBone) {
            Vector3 wLS=WorldToScreen(lShoulder,matrix,vW,vH);
            Vector3 wRS=WorldToScreen(rShoulder,matrix,vW,vH);
            Vector3 wLE=WorldToScreen(lElbow,matrix,vW,vH);
            Vector3 wRE=WorldToScreen(rElbow,matrix,vW,vH);
            Vector3 wLH=WorldToScreen(lHand,matrix,vW,vH);
            Vector3 wRH=WorldToScreen(rHand,matrix,vW,vH);
            Vector3 wLA=WorldToScreen(lAnkle,matrix,vW,vH);
            Vector3 wRA=WorldToScreen(rAnkle,matrix,vW,vH);
            UIColor *bc=[UIColor whiteColor]; CGFloat bw=1.0f;
            DrawBoneLine(layers,CGPointMake(wHead.x,wHead.y),CGPointMake(wHip.x,wHip.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wLS.x,wLS.y),CGPointMake(wRS.x,wRS.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wLS.x,wLS.y),CGPointMake(wLE.x,wLE.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wLE.x,wLE.y),CGPointMake(wLH.x,wLH.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wRS.x,wRS.y),CGPointMake(wRE.x,wRE.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wRE.x,wRE.y),CGPointMake(wRH.x,wRH.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wHip.x,wHip.y),CGPointMake(wLA.x,wLA.y),bc,bw);
            DrawBoneLine(layers,CGPointMake(wHip.x,wHip.y),CGPointMake(wRA.x,wRA.y),bc,bw);
        }

        float boxH = fabsf(w2sHead.y - w2sToe.y);
        if (boxH < 5.0f) continue;
        float boxW = boxH * 0.45f;
        float bx   = w2sHead.x - boxW * 0.5f;
        float by   = w2sHead.y;

        UIColor *accent;
        if (dis<30.f)      accent=[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
        else if (dis<80.f) accent=[UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0];
        else               accent=[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:0.85];

        // Box (corners)
        if (isBox) {
            float cLen=MIN(boxW,boxH)*0.22f, lw=1.2f;
            float pts[][4]={
                {bx,by,bx+cLen,by},{bx,by,bx,by+cLen},
                {bx+boxW-cLen,by,bx+boxW,by},{bx+boxW,by,bx+boxW,by+cLen},
                {bx,by+boxH-cLen,bx,by+boxH},{bx,by+boxH,bx+cLen,by+boxH},
                {bx+boxW,by+boxH-cLen,bx+boxW,by+boxH},{bx+boxW-cLen,by+boxH,bx+boxW,by+boxH}
            };
            for (int ci=0;ci<8;ci++) {
                CALayer *c=[CALayer layer];
                c.frame=CGRectMake(MIN(pts[ci][0],pts[ci][2]),MIN(pts[ci][1],pts[ci][3]),
                                   MAX(fabsf(pts[ci][2]-pts[ci][0]),lw),MAX(fabsf(pts[ci][3]-pts[ci][1]),lw));
                c.backgroundColor=accent.CGColor; [layers addObject:c];
            }
        }

        // Name
        if (isName) {
            NSString *nm=GetNickName(pawn); if(!nm||nm.length==0) nm=@"?";
            float nW=MAX(boxW,50.f),nH=11.f,nX=bx+(boxW-nW)*0.5f,nY=by-nH-3.f;
            CALayer *nbg=[CALayer layer];
            nbg.frame=CGRectMake(nX,nY,nW,nH);
            nbg.backgroundColor=[UIColor colorWithWhite:0.0 alpha:0.45].CGColor;
            nbg.cornerRadius=2.f;[layers addObject:nbg];
            CATextLayer *nl=[CATextLayer layer];
            nl.string=nm;nl.fontSize=8.5f;nl.frame=CGRectMake(nX,nY,nW,nH);
            nl.alignmentMode=kCAAlignmentCenter;
            nl.foregroundColor=[UIColor colorWithWhite:0.95 alpha:1.0].CGColor;
            nl.contentsScale=[UIScreen mainScreen].scale;[layers addObject:nl];
        }

        // ФИКС 4: Health bar + цифры HP
        if (isHealth) {
            int maxHP = get_MaxHP(pawn);
            if (maxHP > 0) {
                float ratio = fmaxf(0.f, fminf(1.f, (float)curHP/maxHP));
                float barW  = MAX(boxW, 50.f);
                float barH  = 3.f;
                float barX  = bx + (boxW-barW)*0.5f;
                float barY  = by - 11.f - 3.f - barH - 2.f;

                CALayer *bgH=[CALayer layer];
                bgH.frame=CGRectMake(barX,barY,barW,barH);
                bgH.backgroundColor=[UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
                bgH.cornerRadius=1.5f; [layers addObject:bgH];

                UIColor *hpCol;
                if (ratio>0.6f)      hpCol=[UIColor colorWithRed:0.15 green:0.9 blue:0.35 alpha:1.0];
                else if (ratio>0.3f) hpCol=[UIColor colorWithRed:1.0 green:0.75 blue:0.0 alpha:1.0];
                else                 hpCol=[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];

                CALayer *fillH=[CALayer layer];
                fillH.frame=CGRectMake(barX,barY,barW*ratio,barH);
                fillH.backgroundColor=hpCol.CGColor;
                fillH.cornerRadius=1.5f; [layers addObject:fillH];

                // Цифры HP справа от бара
                CATextLayer *hpTxt=[CATextLayer layer];
                hpTxt.string=[NSString stringWithFormat:@"%d/%d", curHP, maxHP];
                hpTxt.fontSize=7.5f;
                hpTxt.frame=CGRectMake(barX+barW+3.f, barY-1.f, 40.f, 10.f);
                hpTxt.alignmentMode=kCAAlignmentLeft;
                hpTxt.foregroundColor=hpCol.CGColor;
                hpTxt.contentsScale=[UIScreen mainScreen].scale;
                [layers addObject:hpTxt];
            }
        }

        // Distance
        if (isDis) {
            CATextLayer *dl=[CATextLayer layer];
            dl.string=[NSString stringWithFormat:@"%.0fm",dis];
            dl.fontSize=8.f;dl.frame=CGRectMake(bx,by+boxH+1.f,boxW,10.f);
            dl.alignmentMode=kCAAlignmentCenter;
            dl.foregroundColor=[UIColor colorWithWhite:0.7 alpha:0.8].CGColor;
            dl.contentsScale=[UIScreen mainScreen].scale;[layers addObject:dl];
        }

        // Lines
        if (isLine) {
            CGFloat sw=self.bounds.size.width,sh=self.bounds.size.height;
            CGPoint from;
            if (lineOrigin==0)      from=CGPointMake(sw*.5f,0);
            else if (lineOrigin==1) from=CGPointMake(sw*.5f,sh*.5f);
            else                    from=CGPointMake(sw*.5f,sh);
            CGPoint to=(lineOrigin==2)?CGPointMake(bx+boxW*.5f,by+boxH):CGPointMake(bx+boxW*.5f,by);
            DrawBoneLine(layers,from,to,[accent colorWithAlphaComponent:0.5],0.8f);
        }
    }

    // Apply aimbot
    bool shouldAim=(aimTrigger==0)||((aimTrigger==1)&&isFire);
    if (isAimbot && isVaildPtr(bestTarget) && shouldAim) {
        Vector3 aimPos;
        if (aimTarget==0)      aimPos=getPositionExt(getHead(bestTarget));
        else if (aimTarget==1) aimPos=getPositionExt(getHead(bestTarget))+Vector3(0,-0.15f,0);
        else                   aimPos=getPositionExt(getHip(bestTarget));
        set_aim(myPawn, GetRotationToLocation(aimPos,0.1f,myLoc));
    }
}

@end
