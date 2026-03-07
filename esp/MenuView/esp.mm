#import "esp.h"
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
#define OFF_ROTATION        ENCRYPTOFFSET("0x53C")    // m_AimRotation (камера)
#define OFF_SILENT_ROTATION ENCRYPTOFFSET("0x172C")   // m_CurrentAimRotation (пуля)
#define OFF_FIRING          ENCRYPTOFFSET("0x750")

// Knocked state через PropertyData pool @ player+0x68 (varID=2)
// Тот же механизм что HP (varID=0,1) — работает стабильно
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

// Структура для передачи текстовых данных из bg-потока в main
struct ESPTextEntry {
    char text[48];
    float x, y, w, h;
    float fontSize;
    float r, g, b, a;       // foreground color
    float bgAlpha;           // 0 = нет фона
    int   align;             // 0=left, 1=center
};
static const int kMaxESPText = 64; // максимум строк за кадр

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
// ── Обычный Aimbot ──────────────────────────────────────────────────
static bool  isAimbot      = NO;
static float aimFov        = 150.0f;
static float aimDistance   = 200.0f;
// ── Silent Aim ───────────────────────────────────────────────────────
static bool  isSilentAim     = NO;
static float silentFov       = 150.0f;
static float silentDistance  = 200.0f;

// --- Advanced Aimbot Config ---


static int  aimMode = 1;           // 0 = Closest to Player, 1 = Closest to Crosshair
static int  aimTrigger = 1;        // 0 = Always, 1 = Only Shooting, 2 = Only Aiming
static int  aimTarget = 0;         // 0 = Head, 1 = Neck, 2 = Hip
static float aimSpeed = 1.0f;      // Aim smoothing 0.05 - 1.0
static bool isStreamerMode = NO;   // Stream Proof

@interface CustomSwitch : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@end

@implementation CustomSwitch { UIView *_thumb; BOOL _touchActive; NSTimeInterval _lastToggleTime; }
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
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    return [self pointInside:point withEvent:event] ? self : nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touchActive = YES;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint pt = [touches.anyObject locationInView:self];
    if (pt.x < -10 || pt.x > self.bounds.size.width + 10 ||
        pt.y < -10 || pt.y > self.bounds.size.height + 10) {
        _touchActive = NO;
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touchActive) return;
    _touchActive = NO;
    // Дебаунс 300мс — TSEventFetcher присылает два Ended подряд, это отсекает второй
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastToggleTime < 0.3) return;
    CGPoint pt = [touches.anyObject locationInView:self];
    if ([self pointInside:pt withEvent:event]) {
        _lastToggleTime = now;
        [self toggle];
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touchActive = NO;
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
- (void)toggle {
    self.on = !self.on;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
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

// (PassThroughScrollView удалён — AIM таб больше не использует ScrollView)
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
- (void)renderESP;
- (CATextLayer *)textLayer;
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
    // locationInView конвертирует глобальные координаты в локальные автоматически
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
// View остаётся ВИДИМОЙ на экране пользователя.
static BOOL __applyHideCapture(UIView *v, BOOL hidden) {
    static NSString *maskKey = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // base64("disableUpdateMask")
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
    
    // Tab Views
    UIView *mainTabContainer;
    UIView *aimTabContainer;
    UIView *silentTabContainer;
    UIView *settingTabContainer;
    UIView *extraTabContainer;
    UIView *_sidebar;

    UIView *previewView;
    UIView *previewContentContainer;
    
    UILabel *previewNameLabel;
    UILabel *previewDistLabel;
    UIView *healthBarContainer;
    UIView *boxContainer;
    
    // HUD freeze detection
    uint64_t _lastMatchPtr;
    NSTimeInterval _lastValidFrame;
    UIView *skeletonContainer;
    float previewScale;

    // ESP рендер — CAShapeLayer + текстовый пул
    // Bone/Box/Line разделены по 3 цветовым зонам дистанции
    CAShapeLayer *_boneNear;    // <40м красный
    CAShapeLayer *_boneMid;     // <100м жёлтый
    CAShapeLayer *_boneFar;     // >=100м белый/голубой
    CAShapeLayer *_boneKnocked; // нокнут фиолетовый
    CAShapeLayer *_boxNear;
    CAShapeLayer *_boxMid;
    CAShapeLayer *_boxFar;
    CAShapeLayer *_boxKnocked;
    CAShapeLayer *_lineNear;
    CAShapeLayer *_lineMid;
    CAShapeLayer *_lineFar;
    // Старые алиасы (используются в коде применения)
    CAShapeLayer *_boneLayer;
    CAShapeLayer *_boxLayer;
    CAShapeLayer *_lineLayer;
    CAShapeLayer *_fovLayer;
    CAShapeLayer *_hpBgLayer;
    CAShapeLayer *_hpFillGreen;   // ratio > 0.6
    CAShapeLayer *_hpFillYellow;  // 0.3-0.6
    CAShapeLayer *_hpFillRed;     // < 0.3
    CAShapeLayer *_hpFillLayer;   // алиас для совместимости
    NSMutableArray<CATextLayer *> *_textPool;
    NSInteger _textPoolIndex;

    // Background ESP compute queue — считаем paths не на main thread
    dispatch_queue_t _espQueue;
    // Atomic flag — не запускаем новый расчёт пока предыдущий не кончил
    volatile BOOL _espBusy;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.drawingLayers = [NSMutableArray array];
        _textPool = [NSMutableArray array];
        // Высокоприоритетная очередь для расчёта ESP путей
        _espQueue = dispatch_queue_create("esp.render", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_espQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        _espBusy = NO;

        // === ESP слои — создаются один раз ===
        // Хелпер создания шейп-слоя
        auto makeShape = [self](UIColor *stroke, CGFloat lw, BOOL round) -> CAShapeLayer * {
            CAShapeLayer *sl = [CAShapeLayer layer];
            sl.fillColor   = nil;
            sl.strokeColor = stroke.CGColor;
            sl.lineWidth   = lw;
            sl.lineCap     = round ? kCALineCapRound : kCALineCapSquare;
            [self.layer addSublayer:sl];
            return sl;
        };

        // Кости по зонам
        _boneNear    = makeShape([UIColor colorWithRed:1.f green:0.2f blue:0.2f alpha:0.9f], 1.2f, YES);
        _boneMid     = makeShape([UIColor colorWithRed:1.f green:0.85f blue:0.f alpha:0.9f], 1.1f, YES);
        _boneFar     = makeShape([UIColor colorWithWhite:1.f alpha:0.75f],                    1.0f, YES);
        _boneKnocked = makeShape([UIColor colorWithRed:0.6f green:0.4f blue:1.f alpha:0.7f], 0.9f, YES);
        _boneLayer   = _boneFar; // алиас для совместимости

        // Боксы по зонам
        _boxNear    = makeShape([UIColor colorWithRed:1.f green:0.2f blue:0.2f alpha:0.95f], 1.6f, NO);
        _boxMid     = makeShape([UIColor colorWithRed:1.f green:0.85f blue:0.f alpha:0.95f], 1.5f, NO);
        _boxFar     = makeShape([UIColor colorWithWhite:1.f alpha:0.9f],                     1.4f, NO);
        _boxKnocked = makeShape([UIColor colorWithRed:0.6f green:0.4f blue:1.f alpha:0.75f],1.2f, NO);
        _boxLayer   = _boxFar; // алиас

        // Линии ESP по зонам
        _lineNear = makeShape([UIColor colorWithRed:1.f green:0.2f blue:0.2f alpha:0.55f], 0.9f, NO);
        _lineMid  = makeShape([UIColor colorWithRed:1.f green:0.85f blue:0.f alpha:0.5f],  0.8f, NO);
        _lineFar  = makeShape([UIColor colorWithWhite:0.8f alpha:0.4f],                    0.7f, NO);
        _lineLayer = _lineFar; // алиас

        // HP полоски
        _hpBgLayer = makeShape(nil, 0, NO);
        _hpBgLayer.fillColor = [UIColor colorWithWhite:0.1 alpha:0.6].CGColor;
        _hpFillGreen = makeShape(nil, 0, NO);
        _hpFillGreen.fillColor  = [UIColor colorWithRed:0.15 green:0.9 blue:0.35 alpha:1.0].CGColor;
        _hpFillYellow = makeShape(nil, 0, NO);
        _hpFillYellow.fillColor = [UIColor colorWithRed:1.0  green:0.75 blue:0.0  alpha:1.0].CGColor;
        _hpFillRed = makeShape(nil, 0, NO);
        _hpFillRed.fillColor    = [UIColor colorWithRed:1.0  green:0.2  blue:0.2  alpha:1.0].CGColor;
        _hpFillLayer = _hpFillGreen; // алиас

        // FOV круг
        _fovLayer = makeShape([UIColor colorWithWhite:1.0 alpha:0.4], 1.0f, NO);
        _fovLayer.hidden = YES;

        [self SetUpBase];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        // 30fps для ESP: плавно и не жрёт FPS игры
        // _espBusy гарантирует что тяжёлый кадр не накапливается
        if (@available(iOS 15.0, *)) {
            self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(24, 30, 30);
        } else {
            self.displayLink.preferredFramesPerSecond = 30;
        }
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [self setupFloatingButton];
        [self setupMenuUI];
        [self layoutSubviews];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;

    // Когда меню закрыто — ТОЛЬКО floatingButton, всё в игру
    if (!menuContainer || menuContainer.hidden) {
        if (floatingButton && !floatingButton.hidden) {
            CGPoint p = [self convertPoint:point toView:floatingButton];
            if ([floatingButton pointInside:p withEvent:event]) return floatingButton;
        }
        return nil;
    }
    if (menuContainer && !menuContainer.hidden) {
        CGPoint pInMenu = [self convertPoint:point toView:menuContainer];
        if ([menuContainer pointInside:pInMenu withEvent:event]) {
#ifdef DEBUG
            espLog([NSString stringWithFormat:@"[HITTEST] point=(%.0f,%.0f) menuContainer OK", pInMenu.x, pInMenu.y]);
#endif
            // Стандартный hitTest UIKit — он правильно найдёт нужный view
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
    
    // Pan для перетаскивания — minimumNumberOfTouches=1
    UIPanGestureRecognizer *iconPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    iconPan.maximumNumberOfTouches = 1;
    iconPan.minimumNumberOfTouches = 1;
    [floatingButton addGestureRecognizer:iconPan];
    
    // Tap для открытия — должен провалиться если идёт pan
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
    [customSwitch addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [view addSubview:customSwitch];
}

// ==================== HELPER UI BUILDERS ====================

- (UILabel *)makeSectionLabel:(NSString *)title atY:(CGFloat)y width:(CGFloat)w {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, y, w, 16)];
    lbl.text = title;
    lbl.textColor = [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    lbl.font = [UIFont boldSystemFontOfSize:10];
    return lbl;
}

// addSegmentTo: — старая рабочая реализация без ScrollView.
// UITapGestureRecognizer на segContainer, cancelsTouchesInView=NO.
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
        segBtn.backgroundColor = (*selectedRef == i)
            ? [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0]
            : [UIColor clearColor];
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
            btn.backgroundColor = (j == idx)
                ? [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0]
                : [UIColor clearColor];
            UILabel *l = btn.subviews.firstObject;
            l.textColor = (j == idx) ? [UIColor blackColor] : [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [tap addTarget:self action:@selector(handleSegmentTapGesture:)];
    [segContainer addGestureRecognizer:tap];
}

// ============================================================


- (void)setupMenuUI {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat menuWidth = MIN(550, screenW - 10);
    CGFloat menuHeight = MIN(370, screenH * 0.55);
    
    // Масштаб для адаптации всех элементов
    CGFloat scale = menuWidth / 550.0;
    
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, menuHeight)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 15;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    menuContainer.layer.borderWidth = 2;
    menuContainer.clipsToBounds = NO;
    menuContainer.hidden = YES;
    // absorbTap убран — menuContainer.hitTest сам решает что перехватить
    [self addSubview:menuContainer];
    
    // Header
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
            circle.tag = 200; // tag 200 = close button
            UITapGestureRecognizer *closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCloseTap:)];
            [circle addGestureRecognizer:closeTap];
        }
        [circle addSubview:btnIcon];
        [headerView addSubview:circle];
    }
    
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [headerView addGestureRecognizer:menuPan];
    
    // Sidebar Buttons
    CGFloat sidebarW = 75 * scale;
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectMake(menuWidth - sidebarW - 10, 50, sidebarW, 310 * scale)];
    sidebar.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    sidebar.layer.cornerRadius = 10;
    sidebar.userInteractionEnabled = YES;
    _sidebar = sidebar;
    [menuContainer addSubview:sidebar];
    
    NSArray *tabs = @[@"Main", @"AIM", @"Extra", @"Setting", @"Silent"];
    for (int i = 0; i < tabs.count; i++) {
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(3, 8 + (i * 50 * scale), sidebarW - 6, 35 * scale)];
        btn.backgroundColor = (i == 0) ? [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0] : [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        btn.layer.cornerRadius = 17.5;
        btn.userInteractionEnabled = YES;
        btn.tag = 100 + i; // tag 100=Main, 101=AIM, 102=Setting
        UILabel *btnLbl = [[UILabel alloc] initWithFrame:btn.bounds];
        btnLbl.text = tabs[i];
        btnLbl.textColor = [UIColor whiteColor];
        btnLbl.font = [UIFont boldSystemFontOfSize:11];
        btnLbl.textAlignment = NSTextAlignmentCenter;
        btnLbl.userInteractionEnabled = NO;
        [btn addSubview:btnLbl];
        // Gesture recognizer — надёжнее чем touchesEnded для UIView (не UIButton)
        UITapGestureRecognizer *tabTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTabTap:)];
        [btn addGestureRecognizer:tabTap];
        [sidebar addSubview:btn];
    }

    // --- MAIN TAB (ESP) ---
    CGFloat tabW = menuWidth - sidebarW - 25;
    CGFloat tabH = menuHeight - 55;
    mainTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    mainTabContainer.backgroundColor = [UIColor clearColor];
    [menuContainer addSubview:mainTabContainer];

    // Preview Section (Left)
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

    // Feature Box (Right)
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

    // Size slider убран — не влияет на функционал

    // --- AIM TAB ---
    // menuHeight увеличен для AIM таба через switchToTab
    aimTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    aimTabContainer.backgroundColor = [UIColor blackColor];
    aimTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    aimTabContainer.layer.borderWidth = 1;
    aimTabContainer.layer.cornerRadius = 10;
    aimTabContainer.hidden = YES;
    aimTabContainer.clipsToBounds = YES;
    [menuContainer addSubview:aimTabContainer];

    UIView *aimContent = aimTabContainer; // алиас — всё добавляется прямо в контейнер
    CGFloat aW = tabW;
    CGFloat ay = 6;

    UILabel *aimTitle = [self makeSectionLabel:@"AIMBOT" atY:ay width:aW];
    [aimContent addSubview:aimTitle]; ay += 18;
    UIView *aimSep1 = [[UIView alloc] initWithFrame:CGRectMake(10, ay, aW - 20, 1)];
    aimSep1.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.25 alpha:1.0];
    [aimContent addSubview:aimSep1]; ay += 6;

    // ─ Aimbot ─────────────────────────────────────────────────────────
    [self addFeatureToView:aimContent withTitle:@"Enable Aimbot" atY:ay initialValue:isAimbot andAction:@selector(toggleAimbot:)]; ay += 30;

    ay += 4;
    UIView *aimSep2 = [[UIView alloc] initWithFrame:CGRectMake(10, ay, aW - 20, 1)];
    aimSep2.backgroundColor = aimSep1.backgroundColor;
    [aimContent addSubview:aimSep2]; ay += 6;

    UILabel *aimModeTitle = [self makeSectionLabel:@"AIM MODE" atY:ay width:aW];
    [aimContent addSubview:aimModeTitle]; ay += 16;

    NSArray *aimModeOpts = @[@"Closest Player", @"Crosshair"];
    [self addSegmentTo:aimContent atY:ay title:@"" options:aimModeOpts selectedRef:&aimMode tag:10]; ay += 32;

    NSArray *aimTargetOpts = @[@"Head", @"Neck", @"Hip"];
    [self addSegmentTo:aimContent atY:ay title:@"" options:aimTargetOpts selectedRef:&aimTarget tag:11]; ay += 32;

    NSArray *aimTriggerOpts = @[@"Always", @"Shooting"];
    [self addSegmentTo:aimContent atY:ay title:@"" options:aimTriggerOpts selectedRef:&aimTrigger tag:12]; ay += 10;

    CGFloat aimContentHeight = ay + 10;
    objc_setAssociatedObject(aimTabContainer, "aimH", @(aimContentHeight), OBJC_ASSOCIATION_RETAIN_NONATOMIC);


    // --- EXTRA TAB: слайдеры ---
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

    // FOV Slider
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

    // Distance Slider
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

    // Speed Slider
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


    // --- SETTING TAB ---
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

    // Поднять sidebar поверх всех табов
    [menuContainer bringSubviewToFront:sidebar];

    // --- SILENT AIM TAB ---
    silentTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    silentTabContainer.backgroundColor = [UIColor blackColor];
    silentTabContainer.layer.borderColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.8 alpha:1.0].CGColor;
    silentTabContainer.layer.borderWidth = 1;
    silentTabContainer.layer.cornerRadius = 10;
    silentTabContainer.hidden = YES;
    silentTabContainer.clipsToBounds = YES;
    [menuContainer addSubview:silentTabContainer];
    [menuContainer bringSubviewToFront:sidebar];

    CGFloat sW = tabW;
    CGFloat sy = 8;

    UILabel *silHdr = [self makeSectionLabel:@"SILENT AIM" atY:sy width:sW];
    [silentTabContainer addSubview:silHdr]; sy += 18;
    UIView *silLine = [[UIView alloc] initWithFrame:CGRectMake(10, sy, sW - 20, 1)];
    silLine.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.8 alpha:0.8];
    [silentTabContainer addSubview:silLine]; sy += 8;

    [self addFeatureToView:silentTabContainer withTitle:@"Enable Silent Aim" atY:sy initialValue:isSilentAim andAction:@selector(toggleSilentAim:)]; sy += 32;

    // FOV
    UILabel *sfovLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, sy, sW - 60, 14)];
    sfovLbl.text = @"FOV Radius"; sfovLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    sfovLbl.font = [UIFont systemFontOfSize:10]; [silentTabContainer addSubview:sfovLbl];
    UILabel *sfovVal = [[UILabel alloc] initWithFrame:CGRectMake(sW - 45, sy, 40, 14)];
    sfovVal.text = [NSString stringWithFormat:@"%.0f", silentFov];
    sfovVal.textColor = [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    sfovVal.font = [UIFont systemFontOfSize:10]; sfovVal.textAlignment = NSTextAlignmentRight;
    [silentTabContainer addSubview:sfovVal]; sy += 16;
    HUDSlider *sfovSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, sy, sW - 20, 36)];
    sfovSlider.minimumValue = 10; sfovSlider.maximumValue = 500; sfovSlider.value = silentFov;
    sfovSlider.minimumTrackTintColor = [UIColor colorWithRed:0.7 green:0.3 blue:1.0 alpha:1.0];
    sfovSlider.thumbTintColor = [UIColor whiteColor];
    UILabel * __unsafe_unretained sfvRef = sfovVal;
    sfovSlider.onValueChanged = ^(float v){ silentFov = v; sfvRef.text = [NSString stringWithFormat:@"%.0f", v]; };
    [silentTabContainer addSubview:sfovSlider]; sy += 44;

    // Distance
    UILabel *sdLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, sy, sW - 60, 14)];
    sdLbl.text = @"Distance"; sdLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    sdLbl.font = [UIFont systemFontOfSize:10]; [silentTabContainer addSubview:sdLbl];
    UILabel *sdVal = [[UILabel alloc] initWithFrame:CGRectMake(sW - 45, sy, 40, 14)];
    sdVal.text = [NSString stringWithFormat:@"%.0f", silentDistance];
    sdVal.textColor = [UIColor colorWithRed:0.8 green:0.5 blue:1.0 alpha:1.0];
    sdVal.font = [UIFont systemFontOfSize:10]; sdVal.textAlignment = NSTextAlignmentRight;
    [silentTabContainer addSubview:sdVal]; sy += 16;
    HUDSlider *sdSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, sy, sW - 20, 36)];
    sdSlider.minimumValue = 10; sdSlider.maximumValue = 600; sdSlider.value = silentDistance;
    sdSlider.minimumTrackTintColor = [UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0];
    sdSlider.thumbTintColor = [UIColor whiteColor];
    UILabel * __unsafe_unretained sdvRef = sdVal;
    sdSlider.onValueChanged = ^(float v){ silentDistance = v; sdvRef.text = [NSString stringWithFormat:@"%.0f", v]; };
    [silentTabContainer addSubview:sdSlider]; sy += 44;

    // Target
    UIView *silLine2 = [[UIView alloc] initWithFrame:CGRectMake(10, sy, sW - 20, 1)];
    silLine2.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [silentTabContainer addSubview:silLine2]; sy += 8;
    UILabel *silTargHdr = [self makeSectionLabel:@"TARGET" atY:sy width:sW];
    [silentTabContainer addSubview:silTargHdr]; sy += 16;
    NSArray *silTargOpts = @[@"Head", @"Neck", @"Hip"];
    [self addSegmentTo:silentTabContainer atY:sy title:@"" options:silTargOpts selectedRef:&aimTarget tag:20]; sy += 32;
}

- (void)switchToTab:(NSInteger)tabIndex {
    mainTabContainer.hidden = YES;
    aimTabContainer.hidden = YES;
    extraTabContainer.hidden = YES;
    settingTabContainer.hidden = YES;
    silentTabContainer.hidden = YES;
    mainTabContainer.userInteractionEnabled = NO;
    aimTabContainer.userInteractionEnabled = NO;
    extraTabContainer.userInteractionEnabled = NO;
    settingTabContainer.userInteractionEnabled = NO;
    silentTabContainer.userInteractionEnabled = NO;
    
    for (UIView *sub in _sidebar.subviews) {
        if ([sub isKindOfClass:[UIView class]] && sub.tag >= 100 && sub.tag <= 104) {
            sub.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        }
    }
    UIView *activeBtn = [_sidebar viewWithTag:100 + tabIndex];
    activeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];

    // AIM таб больше обычного — увеличиваем menuContainer и таб под контент
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat baseH = MIN(370, screenH * 0.55);
    CGFloat tabW  = aimTabContainer.frame.size.width;

    if (tabIndex == 1) {
        NSNumber *aimHNum = objc_getAssociatedObject(aimTabContainer, "aimH");
        CGFloat aimH = aimHNum ? aimHNum.floatValue : baseH - 55;
        CGFloat newMenuH = MIN(aimH + 55 + 10, screenH * 0.88);
        CGFloat newTabH  = newMenuH - 55;
        CGRect mf = menuContainer.frame;
        mf.size.height = newMenuH;
        menuContainer.frame = mf;
        aimTabContainer.frame = CGRectMake(15, 50, tabW, newTabH);
        aimTabContainer.hidden = NO; aimTabContainer.userInteractionEnabled = YES;
    } else {
        // Возвращаем стандартную высоту
        CGRect mf = menuContainer.frame;
        mf.size.height = baseH;
        menuContainer.frame = mf;
        aimTabContainer.frame = CGRectMake(15, 50, tabW, baseH - 55);
        if (tabIndex == 0) { mainTabContainer.hidden = NO; mainTabContainer.userInteractionEnabled = YES; }
        if (tabIndex == 2) { extraTabContainer.hidden = NO; extraTabContainer.userInteractionEnabled = YES; }
        if (tabIndex == 3) { settingTabContainer.hidden = NO; settingTabContainer.userInteractionEnabled = YES; }
        if (tabIndex == 4) { silentTabContainer.hidden = NO; silentTabContainer.userInteractionEnabled = YES; }
    }
    silentTabContainer.hidden = (tabIndex != 4);
    silentTabContainer.userInteractionEnabled = (tabIndex == 4);
}

- (void)drawPreviewElements {
    CGFloat w = previewView.frame.size.width;  
    CGFloat h = previewView.frame.size.height; 
    CGFloat cx = w / 2;
    CGFloat startY = 45; 
    
    previewNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, w, 15)];
    previewNameLabel.text = @"ID PlayerName";
    previewNameLabel.textColor = [UIColor greenColor];
    previewNameLabel.textAlignment = NSTextAlignmentCenter;
    previewNameLabel.font = [UIFont boldSystemFontOfSize:11];
    [previewContentContainer addSubview:previewNameLabel];
    
    CGFloat barW = 70;
    healthBarContainer = [[UIView alloc] initWithFrame:CGRectMake(cx - barW/2, 38, barW, 2)];
    healthBarContainer.backgroundColor = [UIColor greenColor];
    [previewContentContainer addSubview:healthBarContainer];
    
    CGFloat boxW = 70;
    CGFloat boxH = 130;
    CGFloat bx = cx - boxW/2;
    CGFloat by = startY;
    
    boxContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewContentContainer addSubview:boxContainer];
    
    CGFloat lineLen = 15;
    UIColor *boxColor = [UIColor whiteColor];
    [self addLineRect:CGRectMake(bx, by, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx, by, 1, lineLen) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW - lineLen, by, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW, by, 1, lineLen) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx, by + boxH, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx, by + boxH - lineLen, 1, lineLen) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW - lineLen, by + boxH, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW, by + boxH - lineLen, 1, lineLen) color:boxColor parent:boxContainer];

    skeletonContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewContentContainer addSubview:skeletonContainer];
    
    UIColor *skelColor = [UIColor whiteColor];
    CGFloat skelThick = 1.0;
    
    CGFloat headRad = 7;
    CGFloat headY = by + 15;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(cx - headRad, headY - headRad, headRad*2, headRad*2)];
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
    
    if (isBox && isBone) {
        [previewContentContainer bringSubviewToFront:boxContainer];
    }
}

// --- Toggle Handlers ---
- (void)toggleBox:(CustomSwitch *)sender { isBox = sender.isOn; boxContainer.hidden = !isBox; }
- (void)toggleBone:(CustomSwitch *)sender { isBone = sender.isOn; skeletonContainer.hidden = !isBone; }
- (void)toggleHealth:(CustomSwitch *)sender { isHealth = sender.isOn; healthBarContainer.hidden = !isHealth; }
- (void)toggleName:(CustomSwitch *)sender { isName = sender.isOn; previewNameLabel.hidden = !isName; }
- (void)toggleDist:(CustomSwitch *)sender { isDis = sender.isOn; previewDistLabel.hidden = !isDis; }
- (void)toggleLine:(CustomSwitch *)sender { isLine = sender.isOn; }
- (void)toggleAimbot:(CustomSwitch *)sender    { isAimbot    = sender.isOn; }
- (void)toggleSilentAim:(CustomSwitch *)sender { isSilentAim = sender.isOn; }


- (void)toggleStreamerMode:(CustomSwitch *)sender {
    isStreamerMode = sender.isOn;

    // Применяем disableUpdateMask к menuContainer и floatingButton напрямую.
    // disableUpdateMask скрывает view от ReplayKit/скриншотов, но view остаётся ВИДИМОЙ на экране.
    if (menuContainer) {
        __applyHideCapture(menuContainer, isStreamerMode);
    }
    if (floatingButton) {
        __applyHideCapture(floatingButton, isStreamerMode);
    }
    // Также применяем к self (MenuView) как страховка
    __applyHideCapture(self, isStreamerMode);
}

- (void)handleSegmentTapGesture:(UITapGestureRecognizer *)t {
    void (^handler)(UITapGestureRecognizer *) = objc_getAssociatedObject(t, &kSegHandlerKey);
    if (handler) handler(t);
}

- (void)fovChanged:(UISlider *)sender { aimFov = sender.value; }
- (void)distChanged:(UISlider *)sender { aimDistance = sender.value; }

- (void)addLineRect:(CGRect)frame color:(UIColor *)color parent:(UIView *)parent {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = color;
    [parent addSubview:v];
}
- (void)addLineFrom:(CGPoint)p1 to:(CGPoint)p2 color:(UIColor *)color width:(CGFloat)width inView:(UIView *)view {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = color;
    CGFloat dx = p2.x - p1.x;
    CGFloat dy = p2.y - p1.y;
    CGFloat len = sqrt(dx*dx + dy*dy);
    CGFloat angle = atan2(dy, dx);
    line.frame = CGRectMake(p1.x, p1.y, len, width);
    line.layer.anchorPoint = CGPointMake(0, 0.5);
    line.center = p1;
    line.transform = CGAffineTransformMakeRotation(angle);
    [view addSubview:line];
}

- (void)sliderValueChanged:(UISlider *)sender {
    previewScale = sender.value;
    [UIView animateWithDuration:0.1 animations:^{
        self->previewContentContainer.transform = CGAffineTransformMakeScale(self->previewScale, self->previewScale);
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) {
        CGRect newFrame = self.superview.bounds;
        // Меняем frame только если размер реально изменился (поворот экрана)
        if (!CGSizeEqualToSize(self.frame.size, newFrame.size)) {
            self.frame = newFrame;
            CGRect screenBounds = self.bounds;
            if (menuContainer && !menuContainer.hidden) {
                menuContainer.center = CGPointMake(screenBounds.size.width / 2, screenBounds.size.height / 2);
            }
        }
    }
    if (floatingButton) {
        CGRect sb = self.bounds;
        CGPoint btnCenter = floatingButton.center;
        CGFloat halfW = floatingButton.bounds.size.width / 2;
        CGFloat halfH = floatingButton.bounds.size.height / 2;
        if (btnCenter.x < halfW) btnCenter.x = halfW;
        if (btnCenter.x > sb.size.width - halfW) btnCenter.x = sb.size.width - halfW;
        if (btnCenter.y < halfH) btnCenter.y = halfH;
        if (btnCenter.y > sb.size.height - halfH) btnCenter.y = sb.size.height - halfH;
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
    CGRect bounds = self.bounds;
    if (CGRectIsEmpty(bounds)) {
        bounds = [UIScreen mainScreen].bounds;
    }
    menuContainer.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
}
// Обработчики tap — используем gesture recognizers вместо ручного touchesEnded
// Это надёжно работает со всей иерархией UIScrollView/PassThroughScrollView
- (void)handleTabTap:(UITapGestureRecognizer *)gr {
    NSInteger tag = gr.view.tag;
    if (tag >= 100 && tag <= 104) {
#ifdef DEBUG
        espLog([NSString stringWithFormat:@"[TAP] sidebar btn tag=%ld", (long)tag]);
#endif
        [self switchToTab:(int)(tag - 100)];
    }
}

- (void)handleCloseTap:(UITapGestureRecognizer *)gr {
    [self hideMenu];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *viewToMove = (gesture.view == floatingButton) ? floatingButton : menuContainer;
    CGPoint translation = [gesture translationInView:self];
    
    if (gesture.state == UIGestureRecognizerStateBegan ||
        gesture.state == UIGestureRecognizerStateChanged) {
        viewToMove.center = CGPointMake(
            viewToMove.center.x + translation.x,
            viewToMove.center.y + translation.y
        );
        [gesture setTranslation:CGPointZero inView:self];
    }
}

- (void)SetUpBase {
    // Запускаем поиск асинхронно — не блокируем main thread
    // Повторяем каждые 3 секунды пока не найдём процесс
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (Moudule_Base == (uint64_t)-1 || Moudule_Base == 0) {
            uint64_t base = (uint64_t)GetGameModule_Base((char*)ENCRYPT("freefireth"));
            if (base != 0) {
                Moudule_Base = base;
                break;
            }
            // Игра не запущена — ждём
            [NSThread sleepForTimeInterval:3.0];
        }
    });
}

- (void)updateFrame {
    if (!self.window) return;
    // Если предыдущий расчёт ещё не закончил — пропускаем кадр (нет очереди задач)
    if (_espBusy) return;
    _espBusy = YES;

    // FOV круг — белый для aimbot, фиолетовый для silent aim
    if (isAimbot || isSilentAim) {
        float cx = self.bounds.size.width / 2;
        float cy = self.bounds.size.height / 2;
        float radius = isSilentAim ? silentFov : aimFov;
        _fovLayer.strokeColor = isSilentAim
            ? [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:0.6].CGColor
            : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
        _fovLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy)
            radius:radius startAngle:0 endAngle:M_PI*2 clockwise:YES].CGPath;
        _fovLayer.hidden = NO;
    } else {
        _fovLayer.hidden = YES;
    }

    // Весь тяжёлый расчёт — на background queue
    // memory reads, WorldToScreen, CGPath построение — всё там
    dispatch_async(_espQueue, ^{
        [self renderESP];
        _espBusy = NO;
    });
}

Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias, Vector3 myLoc) {
    return Quaternion::LookRotation((targetLocation + Vector3(0, y_bias, 0)) - myLoc, Vector3(0, 1, 0));
}

void set_aim(uint64_t player, Quaternion rotation) {
    if (!isVaildPtr(player)) return;
    WriteAddr<Quaternion>(player + OFF_ROTATION, rotation);
}

bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<bool>(player + OFF_FIRING);
}

// knocked detection — inline в renderESP loop (ReadAddr<bool> @ 0xA0, 0x1110)

// Pool текстовых слоёв — берёт существующий или создаёт новый
- (CATextLayer *)textLayer {
    if (_textPoolIndex < (NSInteger)_textPool.count) {
        CATextLayer *t = _textPool[_textPoolIndex++];
        t.hidden = NO;
        return t;
    }
    CATextLayer *t = [CATextLayer layer];
    t.contentsScale = [UIScreen mainScreen].scale;
    t.allowsFontSubpixelQuantization = YES;
    [self.layer addSublayer:t];
    [_textPool addObject:t];
    _textPoolIndex++;
    return t;
}

- (void)renderESP {
    if (Moudule_Base == -1) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);
    uint64_t camera    = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            _boneLayer.path=nil; _boxLayer.path=nil;
            _hpBgLayer.path=nil; _hpFillLayer.path=nil; _lineLayer.path=nil;
            for (CATextLayer *t in _textPool) t.hidden = YES;
            [CATransaction commit];
        });
        return;
    }

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) return;

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) return;

    uint64_t camTransform = ReadAddr<uint64_t>(myPawnObject + OFF_CAMERA_TRANSFORM);
    Vector3 myLoc = getPositionExt(camTransform);

    uint64_t playerList = ReadAddr<uint64_t>(match + OFF_PLAYERLIST);
    uint64_t tValue     = ReadAddr<uint64_t>(playerList + OFF_PLAYERLIST_ARR);
    int      totalCount = ReadAddr<int>(tValue + OFF_PLAYERLIST_CNT);
    // Защита от мусорного значения
    if (totalCount <= 0 || totalCount > 64) totalCount = 64;

    float *matrix = GetViewMatrix(camera);
    float vW = self.bounds.size.width;
    float vH = self.bounds.size.height;
    CGPoint center = CGPointMake(vW * 0.5f, vH * 0.5f);

    // Paths по цветовым зонам: Near(<40м) Mid(<100м) Far(>=100м) Knocked
    CGMutablePathRef boneNearPath    = CGPathCreateMutable();
    CGMutablePathRef boneMidPath     = CGPathCreateMutable();
    CGMutablePathRef boneFarPath     = CGPathCreateMutable();
    CGMutablePathRef boneKnockedPath = CGPathCreateMutable();
    CGMutablePathRef boxNearPath     = CGPathCreateMutable();
    CGMutablePathRef boxMidPath      = CGPathCreateMutable();
    CGMutablePathRef boxFarPath      = CGPathCreateMutable();
    CGMutablePathRef boxKnockedPath  = CGPathCreateMutable();
    CGMutablePathRef lineNearPath    = CGPathCreateMutable();
    CGMutablePathRef lineMidPath     = CGPathCreateMutable();
    CGMutablePathRef lineFarPath     = CGPathCreateMutable();
    CGMutablePathRef hpBgPath         = CGPathCreateMutable();
    CGMutablePathRef hpFillGreenPath  = CGPathCreateMutable(); // ratio > 0.6
    CGMutablePathRef hpFillYellowPath = CGPathCreateMutable(); // 0.3..0.6
    CGMutablePathRef hpFillRedPath    = CGPathCreateMutable(); // < 0.3
    CGMutablePathRef hpFillPath       = hpFillGreenPath;       // алиас

    // Выбор нужного bucket'а по дистанции/состоянию
    #define BONE_PATH  (isKnocked ? boneKnockedPath : (dis<40.f ? boneNearPath : (dis<100.f ? boneMidPath : boneFarPath)))
    #define BOX_PATH   (isKnocked ? boxKnockedPath  : (dis<40.f ? boxNearPath  : (dis<100.f ? boxMidPath  : boxFarPath)))
    #define LINE_PATH  (isKnocked ? lineFarPath     : (dis<40.f ? lineNearPath : (dis<100.f ? lineMidPath : lineFarPath)))

    // Текстовые записи
    ESPTextEntry textEntries[kMaxESPText];
    int textCount = 0;
    auto addText = [&](const char *txt, float x, float y, float w, float h,
                       float fs, float r, float g, float b, float a, float bgA, int align) {
        if (textCount >= kMaxESPText) return;
        ESPTextEntry &e = textEntries[textCount++];
        strncpy(e.text, txt, 47); e.text[47] = 0;
        e.x=x; e.y=y; e.w=w; e.h=h; e.fontSize=fs;
        e.r=r; e.g=g; e.b=b; e.a=a; e.bgAlpha=bgA; e.align=align;
    };

    uint64_t bestTarget = 0;
    float    bestScore  = FLT_MAX;
    bool     isFire     = get_IsFiring(myPawnObject);

    for (int i = 0; i < totalCount; i++) {
        uint64_t PawnObject = ReadAddr<uint64_t>(tValue + OFF_PLAYERLIST_ITEM + 8 * i);
        if (!isVaildPtr(PawnObject)) continue;
        if (isLocalTeamMate(myPawnObject, PawnObject)) continue;

        int CurHP  = get_CurHP(PawnObject);
        int MaxHP  = get_MaxHP(PawnObject);
        // Мёртвые и неинициализированные — пропускаем полностью (и ESP и aimbot)
        if (MaxHP <= 0) continue;
        if (CurHP <= 0) continue;  // трупы (HP=0) — не рендерить, не целиться
        // Нокнутый — прямые field reads из IL2CPP дампа:
        // IsFrozenKnockDown  @ 0xA0   — не изменился между версиями
        // IsKnockedDownBleed @ 0x1110 — основной флаг нокдауна (было 0x1040)
        bool isKnocked = ReadAddr<bool>(PawnObject + 0xA0)
                      || ReadAddr<bool>(PawnObject + 0x1110);

        // Читаем голову — для дистанции и aimbot
        uint64_t headNode = getHead(PawnObject);
        if (!isVaildPtr(headNode)) continue;
        Vector3 HeadPos = getPositionExt(headNode);

        float dis = Vector3::Distance(myLoc, HeadPos);
        // Убираем лишний cut-off — ESP работает до 600м
        if (dis > 600.0f) continue;

        // ── Обычный Aimbot ───────────────────────────────────────────
        if (isAimbot && dis <= aimDistance) {
            Vector3 ap = HeadPos;
            if (aimTarget == 1) ap = HeadPos + Vector3(0,-0.15f,0);
            else if (aimTarget == 2) ap = getPositionExt(getHip(PawnObject));
            Vector3 ws = WorldToScreen(ap, matrix, vW, vH);
            float dx = ws.x - center.x, dy = ws.y - center.y;
            float d2 = sqrtf(dx*dx+dy*dy);
            if (d2 <= aimFov) {
                float sc = (aimMode == 0) ? dis : d2;
                if (sc < bestScore) { bestScore = sc; bestTarget = PawnObject; }
            }
        }
        // ── Silent Aim ───────────────────────────────────────────────
        if (isSilentAim && dis <= silentDistance) {
            Vector3 ap = HeadPos;
            if (aimTarget == 1) ap = HeadPos + Vector3(0,-0.15f,0);
            else if (aimTarget == 2) ap = getPositionExt(getHip(PawnObject));
            Vector3 ws = WorldToScreen(ap, matrix, vW, vH);
            float dx = ws.x - center.x, dy = ws.y - center.y;
            float d2 = sqrtf(dx*dx+dy*dy);
            if (d2 <= silentFov) {
                float sc = (aimMode == 0) ? dis : d2;
                if (sc < bestScore) { bestScore = sc; bestTarget = PawnObject; }
            }
        }

        // ── Проецируем голову и ступни ───────────────────────────────
        uint64_t toeNode = getRightToeNode(PawnObject);
        if (!isVaildPtr(toeNode)) continue;
        Vector3 ToePos  = getPositionExt(toeNode);

        Vector3 HeadTop = HeadPos; HeadTop.y += 0.22f;
        Vector3 s_HeadTop = WorldToScreen(HeadTop,  matrix, vW, vH);
        Vector3 s_Toe     = WorldToScreen(ToePos,   matrix, vW, vH);
        Vector3 s_Head    = WorldToScreen(HeadPos,  matrix, vW, vH);

        // Если голова за экраном — пропускаем
        if (s_HeadTop.x < -200 || s_HeadTop.x > vW+200 ||
            s_HeadTop.y < -200 || s_HeadTop.y > vH+200) continue;

        float boxH = fabsf(s_HeadTop.y - s_Toe.y);
        if (boxH < 6.0f) continue;   // слишком маленький — за горизонтом
        float boxW = boxH * 0.45f;
        float bx   = s_HeadTop.x - boxW * 0.5f;
        float by   = s_HeadTop.y;

        // ── Цвет по дистанции ────────────────────────────────────────
        // <40м красный → <100м жёлтый → белый
        // Нокнутый всегда серо-фиолетовый
        float acR, acG, acB;
        if (isKnocked) { acR=0.6f; acG=0.4f; acB=1.f; }       // фиолетовый = нокнут
        else if (dis < 40.f)  { acR=1.f; acG=0.2f; acB=0.2f; }  // красный
        else if (dis < 100.f) { acR=1.f; acG=0.85f; acB=0.f;  }  // жёлтый
        else if (dis < 250.f) { acR=1.f; acG=1.f;  acB=1.f;  }   // белый
        else                  { acR=0.5f;acG=0.8f; acB=1.f;  }   // голубой = далеко
        float acA = isKnocked ? 0.65f : 0.92f; // нокнутые чуть прозрачнее

        // ── SKELETON (только ≤ 150м — дальше незаметно, но жрёт ресурсы) ──
        if (isBone && dis <= 150.f) {
            uint64_t hipNode = getHip(PawnObject);
            Vector3 HipPos  = isVaildPtr(hipNode) ? getPositionExt(hipNode) : HeadPos;
            Vector3 s_Hip   = WorldToScreen(HipPos,  matrix, vW, vH);

            Vector3 s_LS = WorldToScreen(getPositionExt(getLeftShoulder(PawnObject)),  matrix, vW, vH);
            Vector3 s_RS = WorldToScreen(getPositionExt(getRightShoulder(PawnObject)), matrix, vW, vH);
            Vector3 s_LE = WorldToScreen(getPositionExt(getLeftElbow(PawnObject)),     matrix, vW, vH);
            Vector3 s_RE = WorldToScreen(getPositionExt(getRightElbow(PawnObject)),    matrix, vW, vH);
            Vector3 s_LH = WorldToScreen(getPositionExt(getLeftHand(PawnObject)),      matrix, vW, vH);
            Vector3 s_RH = WorldToScreen(getPositionExt(getRightHand(PawnObject)),     matrix, vW, vH);
            Vector3 s_LA = WorldToScreen(getPositionExt(getLeftAnkle(PawnObject)),     matrix, vW, vH);
            Vector3 s_RA = WorldToScreen(getPositionExt(getRightAnkle(PawnObject)),    matrix, vW, vH);

            // Голова→таз
            CGMutablePathRef bp = BONE_PATH;
            CGPathMoveToPoint(bp,nil,s_Head.x,s_Head.y);
            CGPathAddLineToPoint(bp,nil,s_Hip.x,s_Hip.y);
            // Плечи
            CGPathMoveToPoint(bp,nil,s_LS.x,s_LS.y);
            CGPathAddLineToPoint(bp,nil,s_RS.x,s_RS.y);
            // Левая рука
            CGPathMoveToPoint(bp,nil,s_LS.x,s_LS.y);
            CGPathAddLineToPoint(bp,nil,s_LE.x,s_LE.y);
            CGPathAddLineToPoint(bp,nil,s_LH.x,s_LH.y);
            // Правая рука
            CGPathMoveToPoint(bp,nil,s_RS.x,s_RS.y);
            CGPathAddLineToPoint(bp,nil,s_RE.x,s_RE.y);
            CGPathAddLineToPoint(bp,nil,s_RH.x,s_RH.y);
            // Ноги
            CGPathMoveToPoint(bp,nil,s_Hip.x,s_Hip.y);
            CGPathAddLineToPoint(bp,nil,s_LA.x,s_LA.y);
            CGPathMoveToPoint(bp,nil,s_Hip.x,s_Hip.y);
            CGPathAddLineToPoint(bp,nil,s_RA.x,s_RA.y);
        }

        // ── BOX: corner brackets ─────────────────────────────────────
        if (isBox) {
            float cL = MIN(boxW, boxH) * 0.22f;
            CGMutablePathRef xp = BOX_PATH;
            // TL
            CGPathMoveToPoint(xp,nil,bx,by+cL);
            CGPathAddLineToPoint(xp,nil,bx,by);
            CGPathAddLineToPoint(xp,nil,bx+cL,by);
            // TR
            CGPathMoveToPoint(xp,nil,bx+boxW-cL,by);
            CGPathAddLineToPoint(xp,nil,bx+boxW,by);
            CGPathAddLineToPoint(xp,nil,bx+boxW,by+cL);
            // BL
            CGPathMoveToPoint(xp,nil,bx,by+boxH-cL);
            CGPathAddLineToPoint(xp,nil,bx,by+boxH);
            CGPathAddLineToPoint(xp,nil,bx+cL,by+boxH);
            // BR
            CGPathMoveToPoint(xp,nil,bx+boxW-cL,by+boxH);
            CGPathAddLineToPoint(xp,nil,bx+boxW,by+boxH);
            CGPathAddLineToPoint(xp,nil,bx+boxW,by+boxH-cL);
        }

        // ── HP BAR ───────────────────────────────────────────────────
        if (isHealth) {
            int MaxHP = get_MaxHP(PawnObject);
            if (MaxHP > 0) {
                float ratio  = fmaxf(0.f, fminf(1.f, (float)CurHP / MaxHP));
                float hpBW   = 3.5f;
                float hpBX   = bx - hpBW - 3.f;
                float hpBY   = by;
                CGPathAddRect(hpBgPath,   nil, CGRectMake(hpBX, hpBY, hpBW, boxH));
                float fillH = boxH * ratio;
                CGMutablePathRef fillPath = (ratio > 0.6f) ? hpFillGreenPath
                                          : (ratio > 0.3f) ? hpFillYellowPath : hpFillRedPath;
                // Нокнутый — пустая полоска, только фон
                if (!isKnocked)
                    CGPathAddRect(fillPath, nil, CGRectMake(hpBX, hpBY+boxH-fillH, hpBW, fillH));

                // HP текст — цвет совпадает с полоской
                float hr=(ratio>0.6f)?0.15f:1.f, hg=(ratio>0.6f)?0.9f:(ratio>0.3f?0.75f:0.2f), hb=(ratio>0.6f)?0.35f:(ratio>0.3f?0.f:0.2f);
                char hpBuf[32];
                if (isKnocked) snprintf(hpBuf,sizeof(hpBuf),"KO");
                else           snprintf(hpBuf,sizeof(hpBuf),"%d/%d",CurHP,MaxHP);
                addText(hpBuf, hpBX-2.f, hpBY-9.f, 48.f, 9.f, 7.f, hr,hg,hb,1.f, 0.f, 0);
            }
        }

        // ── NAME ─────────────────────────────────────────────────────
        if (isName) {
            NSString *name = GetNickName(PawnObject);
            const char *ns = (name && name.length) ? [name UTF8String] : "?";
            float nW = MAX(boxW, 60.f);
            float nY = by - 12.f - (isHealth ? 10.f : 0.f);
            char nb[48]; strncpy(nb, ns, 47); nb[47]=0;
            addText(nb, bx+(boxW-nW)*0.5f, nY, nW, 11.f, 9.f, 0.95f,0.95f,0.95f,1.f, 0.45f, 1);
        }

        // ── DISTANCE ─────────────────────────────────────────────────
        if (isDis) {
            char db[24];
            if (isKnocked) snprintf(db,sizeof(db),"KO %.0fm",dis);
            else           snprintf(db,sizeof(db),"%.0fm",dis);
            // Ширина — минимум 50pt чтобы текст не обрезался
            float distW = MAX(boxW, 50.f);
            float distX = bx + (boxW - distW) * 0.5f; // центрируем относительно бокса
            addText(db, distX, by+boxH+2.f, distW, 11.f, 8.5f, acR,acG,acB,acA, 0.f, 1);
        }

        // ── ESP LINE ─────────────────────────────────────────────────
        if (isLine) {
            CGPoint from = (lineOrigin==0) ? CGPointMake(vW*.5f,0)
                         : (lineOrigin==1) ? CGPointMake(vW*.5f,vH*.5f)
                                           : CGPointMake(vW*.5f,vH);
            CGPoint to   = (lineOrigin==2) ? CGPointMake(bx+boxW*.5f,by+boxH)
                                           : CGPointMake(bx+boxW*.5f,by);
            CGMutablePathRef lp = LINE_PATH;
            CGPathMoveToPoint(lp,nil,from.x,from.y);
            CGPathAddLineToPoint(lp,nil,to.x,to.y);
        }
    } // end player loop

    // ── Обычный Aimbot apply ─────────────────────────────────────────
    bool shouldAim = (aimTrigger==0)||(aimTrigger==1&&isFire);
    if (isAimbot && isVaildPtr(bestTarget) && shouldAim) {
        Vector3 ap;
        if      (aimTarget==0) ap = getPositionExt(getHead(bestTarget));
        else if (aimTarget==1) ap = getPositionExt(getHead(bestTarget))+Vector3(0,-0.15f,0);
        else                   ap = getPositionExt(getHip(bestTarget));
        set_aim(myPawnObject, GetRotationToLocation(ap, 0.1f, myLoc));
    }
    // ── Silent Aim apply ─────────────────────────────────────────────
    // Пишем только в m_CurrentAimRotation (rotation пули) — камера не двигается.
    // Срабатывает всегда (trigger не нужен — игрок сам решает когда стрелять).
    if (isSilentAim && isVaildPtr(bestTarget)) {
        Vector3 ap;
        if      (aimTarget==0) ap = getPositionExt(getHead(bestTarget));
        else if (aimTarget==1) ap = getPositionExt(getHead(bestTarget))+Vector3(0,-0.15f,0);
        else                   ap = getPositionExt(getHip(bestTarget));
        Quaternion targetRot = GetRotationToLocation(ap, 0.1f, myLoc);
        WriteAddr<Quaternion>(myPawnObject + OFF_SILENT_ROTATION, targetRot);
    }

    // ── Передаём на main thread ──────────────────────────────────────
    BOOL b_bone=isBone, b_box=isBox, b_hp=isHealth, b_line=isLine;
    int  tCount = textCount;
    ESPTextEntry *tCopy = nullptr;
    if (tCount > 0) {
        tCopy = (ESPTextEntry *)malloc(sizeof(ESPTextEntry)*tCount);
        memcpy(tCopy, textEntries, sizeof(ESPTextEntry)*tCount);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [CATransaction setAnimationDuration:0];

        // Кости по зонам
        _boneNear.path    = b_bone ? boneNearPath    : nil;
        _boneMid.path     = b_bone ? boneMidPath     : nil;
        _boneFar.path     = b_bone ? boneFarPath     : nil;
        _boneKnocked.path = b_bone ? boneKnockedPath : nil;
        // Боксы по зонам
        _boxNear.path    = b_box ? boxNearPath    : nil;
        _boxMid.path     = b_box ? boxMidPath     : nil;
        _boxFar.path     = b_box ? boxFarPath     : nil;
        _boxKnocked.path = b_box ? boxKnockedPath : nil;
        // Линии по зонам
        _lineNear.path = b_line ? lineNearPath : nil;
        _lineMid.path  = b_line ? lineMidPath  : nil;
        _lineFar.path  = b_line ? lineFarPath  : nil;
        // HP
        _hpBgLayer.path      = b_hp ? hpBgPath         : nil;
        _hpFillGreen.path    = b_hp ? hpFillGreenPath   : nil;
        _hpFillYellow.path   = b_hp ? hpFillYellowPath  : nil;
        _hpFillRed.path      = b_hp ? hpFillRedPath     : nil;

        // Текст
        for (CATextLayer *t in _textPool) t.hidden = YES;
        _textPoolIndex = 0;
        for (int ti = 0; ti < tCount; ti++) {
            const ESPTextEntry &e = tCopy[ti];
            CATextLayer *tl = [self textLayer];
            tl.string          = [NSString stringWithUTF8String:e.text];
            tl.fontSize        = e.fontSize;
            tl.frame           = CGRectMake(e.x, e.y, e.w, e.h);
            tl.foregroundColor = [UIColor colorWithRed:e.r green:e.g blue:e.b alpha:e.a].CGColor;
            tl.backgroundColor = (e.bgAlpha > 0.01f)
                ? [UIColor colorWithWhite:0.0 alpha:e.bgAlpha].CGColor : nil;
            tl.alignmentMode   = (e.align == 1) ? kCAAlignmentCenter : kCAAlignmentLeft;
            tl.cornerRadius    = (e.bgAlpha > 0.01f) ? 2.0f : 0.0f;
        }
        if (tCopy) free(tCopy);

        [CATransaction commit];

        // Освобождаем все paths
        CGPathRelease(boneNearPath);    CGPathRelease(boneMidPath);
        CGPathRelease(boneFarPath);     CGPathRelease(boneKnockedPath);
        CGPathRelease(boxNearPath);     CGPathRelease(boxMidPath);
        CGPathRelease(boxFarPath);      CGPathRelease(boxKnockedPath);
        CGPathRelease(lineNearPath);    CGPathRelease(lineMidPath);
        CGPathRelease(lineFarPath);
        CGPathRelease(hpBgPath);
        CGPathRelease(hpFillGreenPath); CGPathRelease(hpFillYellowPath);
        CGPathRelease(hpFillRedPath);
    });
}

@end
