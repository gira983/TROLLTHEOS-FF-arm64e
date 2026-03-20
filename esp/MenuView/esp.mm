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
#import <notify.h>

// --- Obfuscated offsets (compile-time encrypted, runtime decrypted) ---
// Player fields
#define OFF_ROTATION        ENCRYPTOFFSET("0x53C")    // m_AimRotation (камера)
// Silent aim: пишем в оба поля rotation одновременно
// m_AimRotation (камера)         @ 0x53C  = OFF_ROTATION
// m_CurrentAimRotation (пуля)    @ 0x172C
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

// ── WriteDataUInt16: пишем в PropertyDataPool (тот же путь что GetDataUInt16) ─
static void SetDataUInt16(uint64_t player, int varID, int value) {
    if (!isVaildPtr(player)) return;
    uint64_t pool = ReadAddr<uint64_t>(player + 0x68); // GL_IPRIDATAPOOL
    if (!isVaildPtr(pool)) return;
    uint64_t list = ReadAddr<uint64_t>(pool + 0x10);   // GL_POOL_LIST
    if (!isVaildPtr(list)) return;
    uint64_t item = ReadAddr<uint64_t>(list + 0x8 * varID + 0x20); // GL_POOL_ITEM
    if (!isVaildPtr(item)) return;
    WriteAddr<int>(item + 0x18, value);                // GL_POOL_VAL
}

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
static bool isBox = NO;
static bool isBone = NO;
static bool isHealth = NO;
static bool isName = NO;
static bool isDis = NO;
static bool isLine = NO;       // ESP Lines
static int  lineOrigin = 1;    // 0 = Top, 1 = Center, 2 = Bottom

// --- Aimbot Config ---
// ── Обычный Aimbot ──────────────────────────────────────────────────
static bool  isAimbot      = NO;
static float aimFov        = 150.0f;
static bool  isInMatch     = NO;    // детекция матча — обновляется в renderESP
// Жёсткие пороги дальности (как в старой версии)
#define kESPMaxDistance    400.0f   // max distance for aimbot check
#define kESPDetailDistance 300.0f   // max distance for skeleton/box/name render
#define kESPDotDistance    300.0f   // beyond this: show dot marker only
static float aimDistance   = 200.0f;


// --- Advanced Aimbot Config ---


static int  aimMode = 1;           // 0 = Closest to Player, 1 = Closest to Crosshair
static int  aimTrigger = 1;        // 0 = Always, 1 = Only Shooting, 2 = Only Aiming
static int  aimTarget = 0;         // 0 = Head, 1 = Neck, 2 = Hip
static float aimSpeed = 1.0f;      // Aim smoothing 0.05 - 1.0
static float aimSensX = 1.0f;     // Aim axis X sensitivity multiplier
static float aimSensY = 1.0f;     // Aim axis Y sensitivity multiplier
static bool isStreamerMode = NO;   // Stream Proof

// ── Hacks via PlayerAttributes (Player + 0x680) ──────────────────
static bool isInfiniteAmmo = NO;
static bool isDamageBoost  = NO;
static bool isSpeedBoost   = NO;
static bool isEnemyOnMap   = NO;
static bool isSuperArmor   = NO;
static bool isInstantSkill = NO;
static bool isOneHitKill  = NO;
static bool isInvincible  = NO;
static bool isInfGrenades = NO;
// ── Weapons tab ─────────────────────────────────────────────────
static bool isKillAura    = NO;   // Убиваем всех врагов в радиусе через HP=0
static float g_killRadius = 50.0f; // метры

// ── Kill tab ────────────────────────────────────────────────────
static bool isKillAll    = NO;  // SetCurHP=0 всем врагам в радиусе
static bool isFreezeEnemies = NO; // Враги не двигаются




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
    // bounds проверяем с запасом — для HUD overlay view
    CGFloat bW = self.bounds.size.width  > 10 ? self.bounds.size.width  : self.superview.bounds.size.width;
    CGFloat bH = self.bounds.size.height > 10 ? self.bounds.size.height : self.superview.bounds.size.height;
    if (pt.x < -10 || pt.x > bW + 10 ||
        pt.y < -10 || pt.y > bH + 10) {
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
    CGContextSetFillColorWithColor(ctx, (self.isOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1.0] : [UIColor colorWithRed:0.1 green:0.1 blue:0.14 alpha:1.0]).CGColor);
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
        self->_thumb.backgroundColor = self.isOn ? [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0] : [UIColor colorWithWhite:0.35 alpha:1.0];
    }];
}
@end

// (PassThroughScrollView удалён — AIM таб больше не использует ScrollView)
// ExpandedHitView: passes hitTest to subviews even if they exceed container bounds.
// Uses standard UIKit hitTest to avoid mutation-during-iteration crashes with UIScrollView.
@interface ExpandedHitView : UIView
@end
@implementation ExpandedHitView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    // Use UIKit's standard traversal — safe with UIScrollView subviews
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit) return hit;
    // Fallback: check subviews that may extend outside our bounds
    NSArray *subs = [self.subviews copy]; // snapshot — safe from mutation
    for (UIView *sub in subs.reverseObjectEnumerator) {
        if (sub.hidden || !sub.userInteractionEnabled) continue;
        CGPoint local = [self convertPoint:point toView:sub];
        UIView *h = [sub hitTest:local withEvent:event];
        if (h) return h;
    }
    return nil;
}
@end


@interface MenuView () <UIGestureRecognizerDelegate>
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
        self.multipleTouchEnabled = NO;
        [self buildUI];
        // Собственный pan — перехватывает горизонтальное движение раньше containerPan
        UIPanGestureRecognizer *sliderPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSliderPan:)];
        sliderPan.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:sliderPan];
    }
    return self;
}

- (void)handleSliderPan:(UIPanGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan ||
        gr.state == UIGestureRecognizerStateChanged) {
        CGPoint loc = [gr locationInView:self];
        [self updateValueFromX:loc.x];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_track && self.bounds.size.width > 0) {
        CGFloat h = self.bounds.size.height;
        CGFloat w = self.bounds.size.width;
        CGFloat trackH = 4;
        _track.frame = CGRectMake(10, (h - trackH)/2, w - 20, trackH);
        [self updateThumbPosition];
    }
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

// Запрещаем родительским gesture получать touches когда слайдер активен
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gr {
    // Разрешаем только собственный sliderPan
    return (gr.view == self);
}

- (void)updateValueFromX:(CGFloat)x {
    CGFloat trackW = _track.bounds.size.width;
    CGFloat trackX = _track.frame.origin.x;
    CGFloat relX   = x - trackX;
    CGFloat pct    = MAX(0.0f, MIN(1.0f, relX / trackW));
    _value = _minimumValue + pct * (_maximumValue - _minimumValue);
    // Мгновенное обновление без CAAnimation — ползунок идёт за пальцем
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self updateThumbPosition];
    [CATransaction commit];
    if (_onValueChanged) _onValueChanged(_value);
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
    BOOL _didInitialLayout;
    CGPoint _initialTouchPoint;
    
    // Tab Views
    UIView *mainTabContainer;
    UIView *aimTabContainer;
    UIView *settingTabContainer;
    UIView *killTabContainer;
    UIView *weaponsTabContainer;
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
    CAShapeLayer *_boxNear;       // outer rect
    CAShapeLayer *_boxMid;
    CAShapeLayer *_boxFar;
    CAShapeLayer *_boxKnocked;
    CAShapeLayer *_boxInnerNear;  // inner rect (double-line effect)
    CAShapeLayer *_boxInnerMid;
    CAShapeLayer *_boxInnerFar;
    CAShapeLayer *_boxInnerKnocked;
    CAShapeLayer *_lineNear;
    CAShapeLayer *_lineMid;
    CAShapeLayer *_lineFar;
    // Старые алиасы (используются в коде применения)
    CAShapeLayer *_boneLayer;
    CAShapeLayer *_boxLayer;
    CAShapeLayer *_lineLayer;
    CAShapeLayer *_fovLayer;
    // Aim sensitivity sliders — kept as ivars so toggleAimbot can reset them
    HUDSlider *_sensXSlider;
    HUDSlider *_sensYSlider;
    UILabel   *_sensXLabel;
    UILabel   *_sensYLabel;
    CAShapeLayer *_hpBgLayer;
    CAShapeLayer *_hpFillGreen;   // ratio > 0.6
    CAShapeLayer *_hpFillYellow;  // 0.3-0.6
    CAShapeLayer *_hpFillRed;     // < 0.3
    CAShapeLayer *_hpFillLayer;   // алиас для совместимости
    NSMutableArray<CATextLayer *> *_textPool;
    NSInteger _textPoolIndex;

    // Dedicated full-screen layer for ESP drawing — always landscape bounds
    CALayer *_espLayer;
    // Cached viewport size — updated on orientation change (avoids per-frame main sync)
    float _espVW, _espVH;
    // Background ESP compute queue — считаем paths не на main thread
    dispatch_queue_t _espQueue;
    // Match state: consecutive valid frames counter (prevents false positives)
    volatile int32_t _validFrameCount;
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
        _validFrameCount = 0;

        // Init viewport size from screen
        CGSize sc = UIScreen.mainScreen.bounds.size;
        _espVW = (float)MAX(sc.width, sc.height);
        _espVH = (float)MIN(sc.width, sc.height);

        // Update viewport + _espLayer.frame on orientation change (no per-frame sync)
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(_onOrientationChange:)
            name:UIApplicationDidChangeStatusBarOrientationNotification
            object:nil];

        // === ESP слои — создаются один раз ===
        // _espLayer — dedicated container layer, always sized to landscape screen.
        // All shape layers go into _espLayer, NOT self.layer, to avoid coordinate mismatch
        // caused by MenuView's portrait frame vs landscape drawing coordinates.
        _espLayer = [CALayer layer];
        _espLayer.frame = CGRectMake(0, 0, 844, 390); // will be updated in renderESP
        _espLayer.backgroundColor = [UIColor clearColor].CGColor;
        [self.layer addSublayer:_espLayer];

        auto makeShape = [self](UIColor *stroke, CGFloat lw, BOOL round) -> CAShapeLayer * {
            CAShapeLayer *sl = [CAShapeLayer layer];
            sl.fillColor   = nil;
            sl.strokeColor = stroke.CGColor;
            sl.lineWidth   = lw;
            sl.lineCap     = round ? kCALineCapRound : kCALineCapSquare;
            // Disable ALL implicit animations — path changes are instant, no interpolation lag
            sl.actions = @{@"path":        [NSNull null],
                           @"strokeColor": [NSNull null],
                           @"fillColor":   [NSNull null],
                           @"hidden":      [NSNull null],
                           @"opacity":     [NSNull null]};
            [self->_espLayer addSublayer:sl];
            return sl;
        };

        // Skeleton — white, clean (matches reference screenshot)
        // All distance zones same color; knocked = grey-purple
        _boneNear    = makeShape([UIColor colorWithWhite:1.f alpha:0.95f], 1.2f, YES);
        _boneMid     = makeShape([UIColor colorWithWhite:1.f alpha:0.90f], 1.1f, YES);
        _boneFar     = makeShape([UIColor colorWithWhite:1.f alpha:0.80f], 1.0f, YES);
        _boneKnocked = makeShape([UIColor colorWithRed:0.7f green:0.5f blue:1.f alpha:0.75f], 0.9f, YES);
        _boneLayer   = _boneFar;

        // Box — thin outer + very thin inner for elegant double-line look
        UIColor *boxWhite   = [UIColor colorWithWhite:1.f alpha:0.90f];
        UIColor *boxKnColor = [UIColor colorWithRed:0.7f green:0.5f blue:1.f alpha:0.85f];
        _boxNear    = makeShape(boxWhite,   1.0f, NO);
        _boxMid     = makeShape(boxWhite,   1.0f, NO);
        _boxFar     = makeShape(boxWhite,   0.9f, NO);
        _boxKnocked = makeShape(boxKnColor, 0.9f, NO);
        _boxLayer   = _boxFar;
        // Inner rect — very thin
        _boxInnerNear    = makeShape(boxWhite,   0.5f, NO);
        _boxInnerMid     = makeShape(boxWhite,   0.5f, NO);
        _boxInnerFar     = makeShape(boxWhite,   0.4f, NO);
        _boxInnerKnocked = makeShape(boxKnColor, 0.4f, NO);

        // ESP lines — white, semi-transparent (matches reference)
        _lineNear = makeShape([UIColor colorWithWhite:1.f alpha:0.55f], 0.9f, NO);
        _lineMid  = makeShape([UIColor colorWithWhite:1.f alpha:0.45f], 0.8f, NO);
        _lineFar  = makeShape([UIColor colorWithWhite:1.f alpha:0.30f], 0.6f, NO);
        _lineLayer = _lineFar;

        // HP полоски
        _hpBgLayer = makeShape(nil, 0, NO);
        _hpBgLayer.fillColor = [UIColor colorWithWhite:0.0f alpha:0.55f].CGColor;
        // HP bar always green (matches reference — clean single color)
        _hpFillGreen = makeShape(nil, 0, NO);
        _hpFillGreen.fillColor  = [UIColor colorWithRed:0.1f green:0.85f blue:0.3f alpha:1.0f].CGColor;
        // Yellow and red kept as aliases pointing to green for simplicity
        _hpFillYellow = _hpFillGreen;
        _hpFillRed    = _hpFillGreen;
        _hpFillLayer  = _hpFillGreen;

        // FOV круг
        _fovLayer = makeShape([UIColor colorWithWhite:1.0 alpha:0.4], 1.0f, NO);
        _fovLayer.hidden = YES;

        // value-scan features инициализируются при первом включении

        [self SetUpBase];

        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        // 30fps для ESP: плавно и не жрёт FPS игры
        // _espBusy гарантирует что тяжёлый кадр не накапливается
        if (@available(iOS 15.0, *)) {
            self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        } else {
            self.displayLink.preferredFramesPerSecond = 60;
        }
        // ВАЖНО: вешаем DisplayLink на отдельный фоновый thread а не mainRunLoop
        // Это освобождает main thread для касаний и убирает лаги UI игры
        // updateFrame внутри сам делает dispatch_async(main) только для CALayer изменений
        NSThread *displayLinkThread = [[NSThread alloc] initWithBlock:^{
            NSRunLoop *rl = [NSRunLoop currentRunLoop];
            [self.displayLink addToRunLoop:rl forMode:NSDefaultRunLoopMode];
            [rl run];
        }];
        displayLinkThread.name = @"com.fryzz.esp.displaylink";
        displayLinkThread.qualityOfService = NSQualityOfServiceUserInitiated;
        [displayLinkThread start];

        [self setupFloatingButton];
        [self setupMenuUI];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat W = self.bounds.size.width;
            CGFloat H = self.bounds.size.height;
            if (W < 10 || H < 10) {
                W = [UIScreen mainScreen].bounds.size.width;
                H = [UIScreen mainScreen].bounds.size.height;
            }
            self->menuContainer.center = CGPointMake(W / 2.0, H / 2.0);
            // Позицию кнопки устанавливаем ТОЛЬКО при первом появлении.
            // При повторном Start после Stop кнопка остаётся там, куда её переместил пользователь.
            if (!self->_didInitialLayout) {
                self->_didInitialLayout = YES;
                CGFloat btnSz = self->floatingButton.bounds.size.width;
                self->floatingButton.center = CGPointMake(btnSz / 2.0 + 20, btnSz / 2.0 + 60);
            }
        });
    }
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
            // Use standard UIKit hitTest — correctly routes to UIScrollView without conflict
            UIView *hit = [menuContainer hitTest:pInMenu withEvent:event];
            // Only return menuContainer itself if NO subview claimed the touch
            // (prevents containerPan from stealing scroll gestures)
            return hit ? hit : nil;
        }
    }

    return nil;
}

- (void)setupFloatingButton {
    floatingButton = [[UIView alloc] initWithFrame:CGRectMake(20, 60, 46, 46)];
    floatingButton.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:0.97];
    floatingButton.layer.cornerRadius = 12;
    floatingButton.layer.borderWidth = 1;
    floatingButton.layer.borderColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.45].CGColor;
    floatingButton.clipsToBounds = YES;
    floatingButton.userInteractionEnabled = YES;

    UILabel *iconLabel = [[UILabel alloc] initWithFrame:floatingButton.bounds];
    iconLabel.text = @"F";
    iconLabel.textColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1.0];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    iconLabel.font = [UIFont fontWithName:@"Courier-Bold" size:20];
    iconLabel.userInteractionEnabled = NO;
    [floatingButton addSubview:iconLabel];

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(33, 33, 5, 5)];
    dot.backgroundColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1.0];
    dot.layer.cornerRadius = 2.5;
    [floatingButton addSubview:dot];

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

// ─── HELPERS ──────────────────────────────────────────────────────────────────

// Цвета дизайна
#define COL_BG0     [UIColor colorWithRed:0.04  green:0.045 blue:0.062 alpha:1.0]
#define COL_BG1     [UIColor colorWithRed:0.048 green:0.053 blue:0.073 alpha:1.0]
#define COL_BG2     [UIColor colorWithRed:0.065 green:0.072 blue:0.098 alpha:1.0]
#define COL_BG3     [UIColor colorWithRed:0.086 green:0.095 blue:0.13  alpha:1.0]
#define COL_LINE    [UIColor colorWithRed:0.11  green:0.12  blue:0.16  alpha:1.0]
#define COL_LINE2   [UIColor colorWithRed:0.14  green:0.155 blue:0.2   alpha:1.0]
#define COL_ACC     [UIColor colorWithRed:0.78  green:0.95  blue:0.1   alpha:1.0]
#define COL_ACC_DIM [UIColor colorWithRed:0.78  green:0.95  blue:0.1   alpha:0.55]
#define COL_TEXT    [UIColor colorWithRed:0.8   green:0.8   blue:0.9   alpha:1.0]
#define COL_DIM     [UIColor colorWithRed:0.31  green:0.32  blue:0.42  alpha:1.0]
#define COL_DIM2    [UIColor colorWithRed:0.17  green:0.18  blue:0.24  alpha:1.0]
#define COL_RED     [UIColor colorWithRed:0.94  green:0.28  blue:0.28  alpha:1.0]

// Секционный заголовок с линией
- (UIView *)makeSectionHeaderWithTitle:(NSString *)title atY:(CGFloat)y width:(CGFloat)w {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 16)];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 80, 14)];
    lbl.text = title;
    lbl.textColor = COL_ACC_DIM;
    lbl.font = [UIFont fontWithName:@"Courier-Bold" size:8.5];
    [container addSubview:lbl];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(18 + lbl.intrinsicContentSize.width, 6, w - 28 - lbl.intrinsicContentSize.width, 1)];
    line.backgroundColor = COL_LINE;
    [container addSubview:line];

    return container;
}

// Строка с чекбоксом — возвращает UIView
- (UIView *)makeCheckRowWithTitle:(NSString *)title badge:(NSString *)badge badgeColor:(UIColor *)badgeColor atY:(CGFloat)y width:(CGFloat)w initialValue:(BOOL)isOn action:(SEL)action {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 28)];
    row.tag = 999; // помечаем как row

    // Чекбокс
    UIView *cb = [[UIView alloc] initWithFrame:CGRectMake(10, 7, 14, 14)];
    cb.backgroundColor = isOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.1] : COL_BG3;
    cb.layer.cornerRadius = 3;
    cb.layer.borderWidth = 1.5;
    cb.layer.borderColor = isOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.6].CGColor : COL_DIM2.CGColor;
    cb.tag = 500; // tag чекбокса
    [row addSubview:cb];

    // Галочка внутри чекбокса
    UILabel *checkMark = [[UILabel alloc] initWithFrame:cb.bounds];
    checkMark.text = @"✓";
    checkMark.textColor = COL_ACC;
    checkMark.font = [UIFont boldSystemFontOfSize:9];
    checkMark.textAlignment = NSTextAlignmentCenter;
    checkMark.hidden = !isOn;
    checkMark.tag = 501;
    [cb addSubview:checkMark];

    // Лейбл
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(30, 5, w - 50, 18)];
    lbl.text = title;
    lbl.textColor = isOn ? COL_TEXT : COL_DIM;
    lbl.font = [UIFont fontWithName:@"Courier" size:11];
    lbl.tag = 502;
    [row addSubview:lbl];

    // Бейдж (LOOP/SCAN)
    if (badge.length > 0) {
        UILabel *bdg = [[UILabel alloc] initWithFrame:CGRectMake(30 + [title sizeWithAttributes:@{NSFontAttributeName: lbl.font}].width + 6, 8, 36, 12)];
        bdg.text = badge;
        bdg.textColor = badgeColor;
        bdg.font = [UIFont fontWithName:@"Courier-Bold" size:7];
        bdg.textAlignment = NSTextAlignmentCenter;
        bdg.backgroundColor = [badgeColor colorWithAlphaComponent:0.1];
        bdg.layer.cornerRadius = 2;
        bdg.layer.borderWidth = 0.5;
        bdg.layer.borderColor = [badgeColor colorWithAlphaComponent:0.3].CGColor;
        bdg.clipsToBounds = YES;
        [row addSubview:bdg];
    }

    // Tap gesture
    objc_setAssociatedObject(row, "rowAction", NSStringFromSelector(action), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(row, "rowTarget", self, OBJC_ASSOCIATION_ASSIGN);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCheckRowTap:)];
    tap.cancelsTouchesInView = NO;
    [row addGestureRecognizer:tap];

    return row;
}

- (void)handleCheckRowTap:(UITapGestureRecognizer *)gr {
    UIView *row = gr.view;
    UIView *cb = [row viewWithTag:500];
    UILabel *checkMark = (UILabel *)[cb viewWithTag:501];
    UILabel *lbl = (UILabel *)[row viewWithTag:502];

    BOOL nowOn = checkMark.hidden; // было скрыто → включаем
    checkMark.hidden = !nowOn;
    cb.backgroundColor = nowOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.1] : COL_BG3;
    cb.layer.borderColor = nowOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.6].CGColor : COL_DIM2.CGColor;
    lbl.textColor = nowOn ? COL_TEXT : COL_DIM;

    NSString *actionStr = objc_getAssociatedObject(row, "rowAction");
    if (actionStr) {
        SEL sel = NSSelectorFromString(actionStr);
        // Создаём фиктивный CustomSwitch чтобы передать .on
        CustomSwitch *fakeSw = [[CustomSwitch alloc] init];
        fakeSw.on = nowOn;
        if ([self respondsToSelector:sel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self performSelector:sel withObject:fakeSw];
            #pragma clang diagnostic pop
        }
    }
}

// Сегментный контрол
- (void)addSegmentTo:(UIView *)parent atY:(CGFloat)y title:(NSString *)title options:(NSArray *)options selectedRef:(int *)selectedRef tag:(NSInteger)baseTag {
    CGFloat padding = 10;
    CGFloat segW = (parent.bounds.size.width - padding * 2) / options.count;
    CGFloat segH = 26;
    CGFloat titleH = (title.length > 0) ? 14 : 0;

    if (title.length > 0) {
        UIView *sec = [self makeSectionHeaderWithTitle:title atY:y width:parent.bounds.size.width];
        [parent addSubview:sec];
    }

    UIView *segContainer = [[UIView alloc] initWithFrame:CGRectMake(padding, y + titleH, parent.bounds.size.width - padding * 2, segH)];
    segContainer.backgroundColor = COL_BG0;
    segContainer.layer.cornerRadius = 5;
    segContainer.layer.borderWidth = 1;
    segContainer.layer.borderColor = COL_LINE.CGColor;
    segContainer.clipsToBounds = YES;
    [parent addSubview:segContainer];

    for (int i = 0; i < (int)options.count; i++) {
        BOOL isActive = (*selectedRef == i);
        UIView *segBtn = [[UIView alloc] initWithFrame:CGRectMake(i * segW, 0, segW, segH)];
        segBtn.backgroundColor = isActive ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.09] : [UIColor clearColor];
        segBtn.tag = baseTag * 100 + i;
        segBtn.userInteractionEnabled = NO;

        if (i < (int)options.count - 1) {
            UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(segW - 1, 5, 1, segH - 10)];
            divider.backgroundColor = COL_LINE;
            [segBtn addSubview:divider];
        }

        UILabel *lbl = [[UILabel alloc] initWithFrame:segBtn.bounds];
        lbl.text = options[i];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.font = [UIFont fontWithName:@"Courier" size:9.5];
        lbl.textColor = isActive ? COL_ACC : COL_DIM;
        lbl.userInteractionEnabled = NO;
        [segBtn addSubview:lbl];
        [segContainer addSubview:segBtn];
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
            btn.backgroundColor = (j == idx) ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.09] : [UIColor clearColor];
            UILabel *l = btn.subviews.lastObject;
            l.textColor = (j == idx) ? COL_ACC : COL_DIM;
        }
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [tap addTarget:self action:@selector(handleSegmentTapGesture:)];
    [segContainer addGestureRecognizer:tap];
}

// Слайдер-строка
- (void)addSliderTo:(UIView *)parent label:(NSString *)label atY:(CGFloat)y width:(CGFloat)w minVal:(float)minVal maxVal:(float)maxVal value:(float)val format:(NSString *)fmt onChanged:(void(^)(float))block {
    UIView *sec = [self makeSectionHeaderWithTitle:label atY:y width:w];
    [parent addSubview:sec]; y += 18;

    UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(w - 50, y - 18, 44, 14)];
    valLbl.text = [NSString stringWithFormat:fmt, val];
    valLbl.textColor = COL_ACC;
    valLbl.font = [UIFont fontWithName:@"Courier" size:9];
    valLbl.textAlignment = NSTextAlignmentRight;
    [parent addSubview:valLbl];

    HUDSlider *slider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, y, w - 20, 32)];
    slider.minimumValue = minVal;
    slider.maximumValue = maxVal;
    slider.value = val;
    slider.minimumTrackTintColor = COL_ACC;
    slider.thumbTintColor = [UIColor colorWithRed:0.88 green:0.88 blue:0.95 alpha:1.0];
    UILabel * __unsafe_unretained ref = valLbl;
    NSString *captFmt = fmt;
    slider.onValueChanged = ^(float v){
        if (block) block(v);
        ref.text = [NSString stringWithFormat:captFmt, v];
    };
    [parent addSubview:slider];
}

// Добавляет Feature через старый CustomSwitch (совместимость с toggleBox: и др.)
- (void)addFeatureToView:(UIView *)view withTitle:(NSString *)title atY:(CGFloat)y initialValue:(BOOL)isOn andAction:(SEL)action {
    UIView *row = [self makeCheckRowWithTitle:title badge:nil badgeColor:nil atY:y width:view.bounds.size.width initialValue:isOn action:action];
    [view addSubview:row];
}

- (UILabel *)makeSectionLabel:(NSString *)title atY:(CGFloat)y width:(CGFloat)w {
    UIView *sec = [self makeSectionHeaderWithTitle:title atY:y width:w];
    UILabel *lbl = sec.subviews.firstObject;
    return lbl;
}

// ─── SETUP MENU UI ────────────────────────────────────────────────────────────

- (void)setupMenuUI {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat menuWidth  = MIN(380, screenW - 20);
    CGFloat menuHeight = MIN(460, screenH * 0.72);
    CGFloat scale = menuWidth / 380.0;

    // ── КОНТЕЙНЕР ─────────────────────────────────────────────────────
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, menuHeight)];
    menuContainer.backgroundColor = COL_BG1;
    menuContainer.layer.cornerRadius = 10;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.14].CGColor;
    menuContainer.layer.borderWidth = 1;
    menuContainer.clipsToBounds = NO; // кнопка закрытия выглядывает за край
    menuContainer.hidden = YES;
    [self addSubview:menuContainer];

    // Верхняя акцентная линия (градиент имитируем тонкой view)
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(menuWidth * 0.15, 0, menuWidth * 0.7, 1)];
    topLine.backgroundColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.55];
    [menuContainer addSubview:topLine];

    // ── HEADER ────────────────────────────────────────────────────────
    CGFloat hdrH = 36;
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, hdrH)];
    hdr.backgroundColor = COL_BG0;
    hdr.userInteractionEnabled = YES;
    [menuContainer addSubview:hdr];

    UIView *hdrLine = [[UIView alloc] initWithFrame:CGRectMake(0, hdrH - 1, menuWidth, 1)];
    hdrLine.backgroundColor = COL_LINE;
    [hdr addSubview:hdrLine];

    // Dot
    UIView *hDot = [[UIView alloc] initWithFrame:CGRectMake(12, 14, 6, 6)];
    hDot.backgroundColor = COL_ACC;
    hDot.layer.cornerRadius = 3;
    [hdr addSubview:hDot];

    // Название
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(24, 4, 110, 17)];
    titleLbl.text = @"FRYZZ";
    titleLbl.textColor = COL_TEXT;
    titleLbl.font = [UIFont fontWithName:@"Courier-Bold" size:13];
    [hdr addSubview:titleLbl];

    UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(24, 20, 110, 12)];
    subLbl.text = @"by Fryzz 🧊";
    subLbl.textColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.6];
    subLbl.font = [UIFont fontWithName:@"Courier" size:8];
    [hdr addSubview:subLbl];

    // Кнопка закрытия — встроена в правый верхний угол menuContainer
    // Скруглён только нижний левый угол (внутренний), остальные = угол меню
    CGFloat closeSz = 28.0;
    UIView *closeBtn = [[UIView alloc] initWithFrame:CGRectMake(menuWidth - closeSz, 0, closeSz, closeSz)];
    closeBtn.backgroundColor = COL_RED;
    closeBtn.layer.cornerRadius = 9;
    if (@available(iOS 13.0, *)) {
        closeBtn.layer.cornerCurve = kCACornerCurveContinuous;
    }
    closeBtn.layer.maskedCorners = kCALayerMinXMaxYCorner;
    closeBtn.tag = 200;
    UILabel *closeLbl = [[UILabel alloc] initWithFrame:closeBtn.bounds];
    closeLbl.text = @"✕";
    closeLbl.textColor = [UIColor whiteColor];
    closeLbl.font = [UIFont boldSystemFontOfSize:12];
    closeLbl.textAlignment = NSTextAlignmentCenter;
    closeLbl.userInteractionEnabled = NO;
    [closeBtn addSubview:closeLbl];
    UITapGestureRecognizer *closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCloseTap:)];
    [closeBtn addGestureRecognizer:closeTap];
    // (добавляется в menuContainer после sidebar)

    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [hdr addGestureRecognizer:menuPan];

    // Pan на весь menuContainer — можно тащить за любую точку
    UIPanGestureRecognizer *containerPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    containerPan.cancelsTouchesInView = NO;
    containerPan.delaysTouchesBegan = NO;
    containerPan.delegate = self;
    [menuContainer addGestureRecognizer:containerPan];

    // ── SIDEBAR (СЛЕВА) ───────────────────────────────────────────────
    CGFloat sbW = 52 * scale;
    CGFloat sbY = hdrH;
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectMake(0, sbY, sbW, menuHeight - sbY)];
    sidebar.backgroundColor = COL_BG0;
    sidebar.userInteractionEnabled = YES;
    _sidebar = sidebar;

    UIView *sbLine = [[UIView alloc] initWithFrame:CGRectMake(sbW - 1, 0, 1, menuHeight - sbY)];
    sbLine.backgroundColor = COL_LINE;
    [sidebar addSubview:sbLine];

    NSArray *tabNames  = @[@"Main", @"AIM", @"Extra", @"Config", @"Kill", @"Wpn"];
    NSArray *tabSF     = @[@"square.3.layers.3d", @"scope", @"slider.horizontal.3", @"wrench.and.screwdriver", @"bolt.fill", @"flame.fill"];
    NSArray *tabIconTx = @[@"⊞", @"⊕", @"⊛", @"⊜", @"⚡", @"🔥"];
    CGFloat btnH = 36 * scale;
    CGFloat btnPad = 4 * scale;

    for (int i = 0; i < (int)tabNames.count; i++) {
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(4, btnPad + i * (btnH + 3 * scale), sbW - 8, btnH)];
        BOOL isFirst = (i == 0);
        btn.backgroundColor = isFirst ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.08] : [UIColor clearColor];
        btn.layer.cornerRadius = 6;
        btn.layer.borderWidth = 1;
        btn.layer.borderColor = isFirst ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.28].CGColor : [UIColor clearColor].CGColor;
        btn.userInteractionEnabled = YES;
        btn.tag = 100 + i;

        // Иконка (SF Symbol если поддерживается, иначе unicode)
        UIImageView *iconView = nil;
        if (@available(iOS 13.0, *)) {
            UIImage *sfImg = [UIImage systemImageNamed:tabSF[i]];
            if (sfImg) {
                iconView = [[UIImageView alloc] initWithFrame:CGRectMake((sbW - 8 - 18) / 2, 5, 18, 18)];
                iconView.image = sfImg;
                iconView.tintColor = isFirst ? COL_ACC : COL_DIM;
                iconView.contentMode = UIViewContentModeScaleAspectFit;
                [btn addSubview:iconView];
            }
        }
        if (!iconView) {
            UILabel *iconLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 5, sbW - 8, 18)];
            iconLbl.text = tabIconTx[i];
            iconLbl.textColor = isFirst ? COL_ACC : COL_DIM;
            iconLbl.font = [UIFont systemFontOfSize:14];
            iconLbl.textAlignment = NSTextAlignmentCenter;
            [btn addSubview:iconLbl];
        }

        UILabel *nameLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, btnH - 16, sbW - 8, 13)];
        nameLbl.text = tabNames[i];
        nameLbl.textColor = isFirst ? COL_ACC : COL_DIM;
        nameLbl.font = [UIFont fontWithName:@"Courier" size:8];
        nameLbl.textAlignment = NSTextAlignmentCenter;
        [btn addSubview:nameLbl];

        UITapGestureRecognizer *tabTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTabTap:)];
        [btn addGestureRecognizer:tabTap];
        [sidebar addSubview:btn];
    }
    [menuContainer addSubview:sidebar];

    // ── ОБЩИЕ РАЗМЕРЫ ДЛЯ ТАБОВ ──────────────────────────────────────
    CGFloat tabX = sbW + 1; // +1 для border сайдбара
    CGFloat tabY = hdrH;
    CGFloat tabW = menuWidth - sbW - 1;
    CGFloat tabH = menuHeight - hdrH;

    // ══ MAIN TAB ══════════════════════════════════════════════════════
    mainTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    mainTabContainer.backgroundColor = COL_BG1;
    [menuContainer addSubview:mainTabContainer];

    CGFloat mW = tabW;
    CGFloat my = 0;

    // Tab header
    UIView *mHdr = [[UIView alloc] initWithFrame:CGRectMake(0, my, mW, 28)];
    mHdr.backgroundColor = COL_BG1;
    UILabel *mHdrTtl = [[UILabel alloc] initWithFrame:CGRectMake(10, 7, 80, 14)];
    mHdrTtl.text = @"ESP";
    mHdrTtl.textColor = COL_ACC;
    mHdrTtl.font = [UIFont fontWithName:@"Courier-Bold" size:9.5];
    [mHdr addSubview:mHdrTtl];
    UILabel *mHdrDesc = [[UILabel alloc] initWithFrame:CGRectMake(40, 9, mW - 50, 12)];
    mHdrDesc.text = @"— Visual overlays";
    mHdrDesc.textColor = COL_DIM;
    mHdrDesc.font = [UIFont fontWithName:@"Courier" size:8];
    [mHdr addSubview:mHdrDesc];
    UIView *mHdrLine = [[UIView alloc] initWithFrame:CGRectMake(0, 27, mW, 1)];
    mHdrLine.backgroundColor = COL_LINE;
    [mHdr addSubview:mHdrLine];
    [mainTabContainer addSubview:mHdr];
    my += 30;

    // Фичи — все выключены по умолчанию
    my += 2;
    UIView *mSec = [self makeSectionHeaderWithTitle:@"FEATURES" atY:my width:mW];
    [mainTabContainer addSubview:mSec]; my += 18;

    struct { NSString *title; SEL action; } espRows[] = {
        { @"Box",      @selector(toggleBox:)    },
        { @"Skeleton", @selector(toggleBone:)   },
        { @"Health",   @selector(toggleHealth:) },
        { @"Name",     @selector(toggleName:)   },
        { @"Distance", @selector(toggleDist:)   },
        { @"Snaplines",@selector(toggleLine:)   },
    };
    for (int i = 0; i < 6; i++) {
        UIView *row = [self makeCheckRowWithTitle:espRows[i].title badge:nil badgeColor:nil atY:my width:mW initialValue:NO action:espRows[i].action];
        [mainTabContainer addSubview:row]; my += 26;
    }

    my += 2;
    UIView *mSec2 = [self makeSectionHeaderWithTitle:@"SNAPLINE ORIGIN" atY:my width:mW];
    [mainTabContainer addSubview:mSec2]; my += 16;
    [self addSegmentTo:mainTabContainer atY:my title:@"" options:@[@"Top", @"Center", @"Bottom"] selectedRef:&lineOrigin tag:20];

    // ══ AIM TAB ═══════════════════════════════════════════════════════
    aimTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    aimTabContainer.backgroundColor = COL_BG1;
    aimTabContainer.hidden = YES;
    [menuContainer addSubview:aimTabContainer];

    CGFloat aW = tabW;
    CGFloat ay = 0;

    UIView *aHdr = [[UIView alloc] initWithFrame:CGRectMake(0, ay, aW, 28)];
    aHdr.backgroundColor = COL_BG1;
    UILabel *aHdrTtl = [[UILabel alloc] initWithFrame:CGRectMake(10, 7, 80, 14)];
    aHdrTtl.text = @"AIMBOT";
    aHdrTtl.textColor = COL_ACC;
    aHdrTtl.font = [UIFont fontWithName:@"Courier-Bold" size:9.5];
    [aHdr addSubview:aHdrTtl];
    UILabel *aHdrDesc = [[UILabel alloc] initWithFrame:CGRectMake(58, 9, aW - 68, 12)];
    aHdrDesc.text = @"— Auto aim";
    aHdrDesc.textColor = COL_DIM;
    aHdrDesc.font = [UIFont fontWithName:@"Courier" size:8];
    [aHdr addSubview:aHdrDesc];
    UIView *aHdrLine = [[UIView alloc] initWithFrame:CGRectMake(0, 27, aW, 1)];
    aHdrLine.backgroundColor = COL_LINE;
    [aHdr addSubview:aHdrLine];
    [aimTabContainer addSubview:aHdr];
    ay += 30;

    // Enable toggle
    ay += 2;
    UIView *aSec0 = [self makeSectionHeaderWithTitle:@"TOGGLE" atY:ay width:aW];
    [aimTabContainer addSubview:aSec0]; ay += 18;
    UIView *aimRow = [self makeCheckRowWithTitle:@"Enable Aimbot" badge:nil badgeColor:nil atY:ay width:aW initialValue:NO action:@selector(toggleAimbot:)];
    [aimTabContainer addSubview:aimRow]; ay += 26;

    ay += 4;
    UIView *aSec1 = [self makeSectionHeaderWithTitle:@"MODE" atY:ay width:aW];
    [aimTabContainer addSubview:aSec1]; ay += 16;
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:@[@"Closest Player", @"Crosshair"] selectedRef:&aimMode tag:10]; ay += 30;

    ay += 4;
    UIView *aSec2 = [self makeSectionHeaderWithTitle:@"TARGET" atY:ay width:aW];
    [aimTabContainer addSubview:aSec2]; ay += 16;
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:@[@"Head", @"Neck", @"Hip"] selectedRef:&aimTarget tag:11]; ay += 30;

    ay += 4;
    UIView *aSec3 = [self makeSectionHeaderWithTitle:@"TRIGGER" atY:ay width:aW];
    [aimTabContainer addSubview:aSec3]; ay += 16;
    [self addSegmentTo:aimTabContainer atY:ay title:@"" options:@[@"Always", @"Shooting"] selectedRef:&aimTrigger tag:12];

    // ══ EXTRA TAB ═════════════════════════════════════════════════════
    extraTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    extraTabContainer.backgroundColor = COL_BG1;
    extraTabContainer.clipsToBounds = YES;
    extraTabContainer.hidden = YES;
    [menuContainer addSubview:extraTabContainer];

    CGFloat eW = tabW;
    CGFloat ey = 0;

    UIView *eHdr = [[UIView alloc] initWithFrame:CGRectMake(0, ey, eW, 28)];
    eHdr.backgroundColor = COL_BG1;
    UILabel *eHdrTtl = [[UILabel alloc] initWithFrame:CGRectMake(10, 7, 80, 14)];
    eHdrTtl.text = @"EXTRA";
    eHdrTtl.textColor = COL_ACC;
    eHdrTtl.font = [UIFont fontWithName:@"Courier-Bold" size:9.5];
    [eHdr addSubview:eHdrTtl];
    UILabel *eHdrDesc = [[UILabel alloc] initWithFrame:CGRectMake(46, 9, eW - 56, 12)];
    eHdrDesc.text = @"— Parameters";
    eHdrDesc.textColor = COL_DIM;
    eHdrDesc.font = [UIFont fontWithName:@"Courier" size:8];
    [eHdr addSubview:eHdrDesc];
    UIView *eHdrLine = [[UIView alloc] initWithFrame:CGRectMake(0, 27, eW, 1)];
    eHdrLine.backgroundColor = COL_LINE;
    [eHdr addSubview:eHdrLine];
    [extraTabContainer addSubview:eHdr];
    ey += 32;

    [self addSliderTo:extraTabContainer label:@"FOV RADIUS" atY:ey width:eW minVal:10 maxVal:400 value:aimFov format:@"%.0f" onChanged:^(float v){ aimFov = v; }]; ey += 54;
    [self addSliderTo:extraTabContainer label:@"AIM DISTANCE" atY:ey width:eW minVal:10 maxVal:500 value:aimDistance format:@"%.0fm" onChanged:^(float v){ aimDistance = v; }]; ey += 54;
    [self addSliderTo:extraTabContainer label:@"AIM SPEED" atY:ey width:eW minVal:0.05 maxVal:1.0 value:aimSpeed format:@"%.2f" onChanged:^(float v){ aimSpeed = v; }]; ey += 54;
    // AIM SENS X — saved as ivar so toggleAimbot can reset it
    {
        UIView *sec = [self makeSectionHeaderWithTitle:@"AIM SENS X" atY:ey width:eW];
        [extraTabContainer addSubview:sec]; ey += 18;
        _sensXLabel = [[UILabel alloc] initWithFrame:CGRectMake(eW - 50, ey - 18, 44, 14)];
        _sensXLabel.text = [NSString stringWithFormat:@"%.2f", aimSensX];
        _sensXLabel.textColor = COL_ACC;
        _sensXLabel.font = [UIFont fontWithName:@"Courier" size:9];
        _sensXLabel.textAlignment = NSTextAlignmentRight;
        [extraTabContainer addSubview:_sensXLabel];
        _sensXSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, ey, eW - 20, 32)];
        _sensXSlider.minimumValue = 0.1f; _sensXSlider.maximumValue = 3.0f;
        _sensXSlider.value = aimSensX;
        _sensXSlider.minimumTrackTintColor = COL_ACC;
        _sensXSlider.thumbTintColor = [UIColor colorWithRed:0.88 green:0.88 blue:0.95 alpha:1.0];
        UILabel * __unsafe_unretained xRef = _sensXLabel;
        _sensXSlider.onValueChanged = ^(float v){ aimSensX = v; xRef.text = [NSString stringWithFormat:@"%.2f", v]; };
        [extraTabContainer addSubview:_sensXSlider]; ey += 54;
    }
    // AIM SENS Y
    {
        UIView *sec = [self makeSectionHeaderWithTitle:@"AIM SENS Y" atY:ey width:eW];
        [extraTabContainer addSubview:sec]; ey += 18;
        _sensYLabel = [[UILabel alloc] initWithFrame:CGRectMake(eW - 50, ey - 18, 44, 14)];
        _sensYLabel.text = [NSString stringWithFormat:@"%.2f", aimSensY];
        _sensYLabel.textColor = COL_ACC;
        _sensYLabel.font = [UIFont fontWithName:@"Courier" size:9];
        _sensYLabel.textAlignment = NSTextAlignmentRight;
        [extraTabContainer addSubview:_sensYLabel];
        _sensYSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(10, ey, eW - 20, 32)];
        _sensYSlider.minimumValue = 0.1f; _sensYSlider.maximumValue = 3.0f;
        _sensYSlider.value = aimSensY;
        _sensYSlider.minimumTrackTintColor = COL_ACC;
        _sensYSlider.thumbTintColor = [UIColor colorWithRed:0.88 green:0.88 blue:0.95 alpha:1.0];
        UILabel * __unsafe_unretained yRef = _sensYLabel;
        _sensYSlider.onValueChanged = ^(float v){ aimSensY = v; yRef.text = [NSString stringWithFormat:@"%.2f", v]; };
        [extraTabContainer addSubview:_sensYSlider]; ey += 54;
    }


    // ══ CONFIG TAB ════════════════════════════════════════════════════
    settingTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    settingTabContainer.backgroundColor = COL_BG1;
    settingTabContainer.hidden = YES;
    [menuContainer addSubview:settingTabContainer];

    // ── KILL TAB ─────────────────────────────────────────────────
    killTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    killTabContainer.backgroundColor = COL_BG1;
    killTabContainer.clipsToBounds = YES;
    killTabContainer.hidden = YES;
    [menuContainer addSubview:killTabContainer];
    {
        CGFloat kW = tabW - 16; CGFloat ky = 0;
        UILabel *kTtl = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, kW, 16)];
        kTtl.text = @"KILL";
        kTtl.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
        kTtl.font = [UIFont fontWithName:@"Courier-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
        [killTabContainer addSubview:kTtl]; ky += 30;
        UIView *kLine = [[UIView alloc] initWithFrame:CGRectMake(0, ky, tabW, 1)];
        kLine.backgroundColor = COL_LINE;
        [killTabContainer addSubview:kLine]; ky += 8;
        UIView *kSec = [self makeSectionHeaderWithTitle:@"ENEMIES" atY:ky width:kW];
        [killTabContainer addSubview:kSec]; ky += 18;
        UIView *killAllRow = [self makeCheckRowWithTitle:@"Kill All (HP=0)"
            badge:nil badgeColor:nil atY:ky width:kW initialValue:NO
            action:@selector(toggleKillAll:)];
        [killTabContainer addSubview:killAllRow]; ky += 26;
        UIView *freezeRow = [self makeCheckRowWithTitle:@"Freeze Enemies"
            badge:nil badgeColor:nil atY:ky width:kW initialValue:NO
            action:@selector(toggleFreezeEnemies:)];
        [killTabContainer addSubview:freezeRow]; ky += 26;
    }

    // ── WEAPONS tab (index 5) ──────────────────────────────────────
    weaponsTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    weaponsTabContainer.backgroundColor = COL_BG1;
    weaponsTabContainer.clipsToBounds = YES;
    weaponsTabContainer.hidden = YES;
    [menuContainer addSubview:weaponsTabContainer];
    {
        CGFloat wW = tabW - 16; CGFloat wy = 0;
        UILabel *wTtl = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, wW, 16)];
        wTtl.text = @"WEAPONS";
        wTtl.textColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0];
        wTtl.font = [UIFont fontWithName:@"Courier-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
        [weaponsTabContainer addSubview:wTtl]; wy += 30;
        UIView *wLine = [[UIView alloc] initWithFrame:CGRectMake(0, wy, tabW, 1)];
        wLine.backgroundColor = COL_LINE;
        [weaponsTabContainer addSubview:wLine]; wy += 8;
        UIView *wSec1 = [self makeSectionHeaderWithTitle:@"ELIMINATION" atY:wy width:wW];
        [weaponsTabContainer addSubview:wSec1]; wy += 18;
        UIView *killAuraRow = [self makeCheckRowWithTitle:@"Kill Aura (50m)"
            badge:nil badgeColor:nil atY:wy width:wW initialValue:NO
            action:@selector(toggleKillAura:)];
        [weaponsTabContainer addSubview:killAuraRow]; wy += 26;
        UIView *wSec2 = [self makeSectionHeaderWithTitle:@"GRENADE" atY:wy width:wW];
        [weaponsTabContainer addSubview:wSec2]; wy += 18;
        UIView *nukeRow = [self makeCheckRowWithTitle:@"Nuke Grenade"
            badge:nil badgeColor:nil atY:wy width:wW initialValue:NO
            action:@selector(toggleInfGrenades:)];
        [weaponsTabContainer addSubview:nukeRow]; wy += 26;
        UIView *wSec3 = [self makeSectionHeaderWithTitle:@"AMMO" atY:wy width:wW];
        [weaponsTabContainer addSubview:wSec3]; wy += 18;
        UIView *ammoRow2 = [self makeCheckRowWithTitle:@"Infinite Ammo"
            badge:nil badgeColor:nil atY:wy width:wW initialValue:NO
            action:@selector(toggleInfiniteAmmo:)];
        [weaponsTabContainer addSubview:ammoRow2]; wy += 26;
        UIView *wSec4 = [self makeSectionHeaderWithTitle:@"DAMAGE" atY:wy width:wW];
        [weaponsTabContainer addSubview:wSec4]; wy += 18;
        UIView *ohkRow2 = [self makeCheckRowWithTitle:@"One Hit Kill"
            badge:nil badgeColor:nil atY:wy width:wW initialValue:NO
            action:@selector(toggleOneHitKill:)];
        [weaponsTabContainer addSubview:ohkRow2]; wy += 26;
        UIView *dmgRow2 = [self makeCheckRowWithTitle:@"Damage x2"
            badge:nil badgeColor:nil atY:wy width:wW initialValue:NO
            action:@selector(toggleDamageBoost:)];
        [weaponsTabContainer addSubview:dmgRow2]; wy += 26;
    }

    CGFloat cW = tabW;
    CGFloat cy = 0;

    UIView *cHdr = [[UIView alloc] initWithFrame:CGRectMake(0, cy, cW, 28)];
    cHdr.backgroundColor = COL_BG1;
    UILabel *cHdrTtl = [[UILabel alloc] initWithFrame:CGRectMake(10, 7, 80, 14)];
    cHdrTtl.text = @"CONFIG";
    cHdrTtl.textColor = COL_ACC;
    cHdrTtl.font = [UIFont fontWithName:@"Courier-Bold" size:9.5];
    [cHdr addSubview:cHdrTtl];
    UILabel *cHdrDesc = [[UILabel alloc] initWithFrame:CGRectMake(50, 9, cW - 60, 12)];
    cHdrDesc.text = @"— System";
    cHdrDesc.textColor = COL_DIM;
    cHdrDesc.font = [UIFont fontWithName:@"Courier" size:8];
    [cHdr addSubview:cHdrDesc];
    UIView *cHdrLine = [[UIView alloc] initWithFrame:CGRectMake(0, 27, cW, 1)];
    cHdrLine.backgroundColor = COL_LINE;
    [cHdr addSubview:cHdrLine];
    [settingTabContainer addSubview:cHdr];
    cy += 32;

    cy += 4;
    UIView *cSecH = [self makeSectionHeaderWithTitle:@"HACKS" atY:cy width:cW];
    [settingTabContainer addSubview:cSecH]; cy += 18;
    UIView *ammoRow  = [self makeCheckRowWithTitle:@"Infinite Ammo"   badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleInfiniteAmmo:)];
    [settingTabContainer addSubview:ammoRow]; cy += 26;
    UIView *dmgRow   = [self makeCheckRowWithTitle:@"Damage x2"       badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleDamageBoost:)];
    [settingTabContainer addSubview:dmgRow]; cy += 26;
    UIView *spdRow   = [self makeCheckRowWithTitle:@"Speed Boost"     badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleSpeedBoost:)];
    [settingTabContainer addSubview:spdRow]; cy += 26;
    UIView *mapRow   = [self makeCheckRowWithTitle:@"Enemy On Map"    badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleEnemyOnMap:)];
    [settingTabContainer addSubview:mapRow]; cy += 26;
    UIView *armorRow = [self makeCheckRowWithTitle:@"Super Armor"     badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleSuperArmor:)];
    [settingTabContainer addSubview:armorRow]; cy += 26;
    UIView *skillRow = [self makeCheckRowWithTitle:@"Instant Skills"  badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleInstantSkill:)];
    [settingTabContainer addSubview:skillRow]; cy += 26;
    UIView *ohkRow   = [self makeCheckRowWithTitle:@"One Hit Kill"    badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleOneHitKill:)];
    [settingTabContainer addSubview:ohkRow]; cy += 26;
    UIView *invRow   = [self makeCheckRowWithTitle:@"Invincible"      badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleInvincible:)];
    [settingTabContainer addSubview:invRow]; cy += 26;


    cy += 4;
    UIView *cSec2 = [self makeSectionHeaderWithTitle:@"PRIVACY" atY:cy width:cW];
    [settingTabContainer addSubview:cSec2]; cy += 18;
    UIView *spfRow = [self makeCheckRowWithTitle:@"Stream Proof" badge:nil badgeColor:nil atY:cy width:cW initialValue:NO action:@selector(toggleStreamerMode:)];
    [settingTabContainer addSubview:spfRow]; cy += 26;

    UILabel *spfDesc = [[UILabel alloc] initWithFrame:CGRectMake(30, cy, cW - 40, 22)];
    spfDesc.text = @"Hides overlay from recordings & screenshots";
    spfDesc.textColor = COL_DIM;
    spfDesc.font = [UIFont fontWithName:@"Courier" size:8];
    spfDesc.numberOfLines = 2;
    [settingTabContainer addSubview:spfDesc]; cy += 26;

    // INFO
    UIView *cSec3 = [self makeSectionHeaderWithTitle:@"INFO" atY:cy width:cW];
    [settingTabContainer addSubview:cSec3]; cy += 18;

    NSDictionary *infos = @{@"Version": @"1.0.0", @"Game": @"Free Fire", @"Author": @"Fryzz 🧊"};
    NSArray *infoKeys = @[@"Version", @"Game", @"Author"];
    for (NSString *key in infoKeys) {
        UIView *infoLine = [[UIView alloc] initWithFrame:CGRectMake(10, cy, cW - 20, 1)];
        infoLine.backgroundColor = COL_LINE;
        [settingTabContainer addSubview:infoLine]; cy += 2;

        UILabel *kLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, cy, 60, 16)];
        kLbl.text = key; kLbl.textColor = COL_DIM;
        kLbl.font = [UIFont fontWithName:@"Courier" size:9];
        [settingTabContainer addSubview:kLbl];

        UILabel *vLbl = [[UILabel alloc] initWithFrame:CGRectMake(cW - 90, cy, 82, 16)];
        vLbl.text = infos[key];
        vLbl.textColor = [key isEqualToString:@"Author"] ? COL_ACC : COL_TEXT;
        vLbl.font = [UIFont fontWithName:@"Courier" size:9];
        vLbl.textAlignment = NSTextAlignmentRight;
        [settingTabContainer addSubview:vLbl]; cy += 18;
    }

    // Sidebar поверх всего
    [menuContainer bringSubviewToFront:sidebar];

    // Кнопка закрыть — поверх всего включая sidebar
    [menuContainer addSubview:closeBtn];
    [menuContainer bringSubviewToFront:closeBtn];
    // clipsToBounds = NO чтобы кнопка выглядывала за край
    menuContainer.clipsToBounds = NO;
}

- (void)switchToTab:(NSInteger)tabIndex {
    mainTabContainer.hidden = YES;
    aimTabContainer.hidden = YES;
    extraTabContainer.hidden = YES;
    extraTabContainer.userInteractionEnabled = NO;
    settingTabContainer.hidden = YES;
    killTabContainer.hidden = YES;
    weaponsTabContainer.hidden = YES;
    mainTabContainer.userInteractionEnabled = NO;
    aimTabContainer.userInteractionEnabled = NO;
    settingTabContainer.userInteractionEnabled = NO;
    killTabContainer.userInteractionEnabled = NO;
    weaponsTabContainer.userInteractionEnabled = NO;
    
    for (UIView *sub in _sidebar.subviews) {
        if ([sub isKindOfClass:[UIView class]] && sub.tag >= 100 && sub.tag <= 105) {
            sub.backgroundColor = [UIColor clearColor];
            sub.layer.borderColor = [UIColor clearColor].CGColor;
            for (UIView *child in sub.subviews) {
                if ([child isKindOfClass:[UILabel class]])
                    ((UILabel *)child).textColor = [UIColor colorWithRed:0.31 green:0.32 blue:0.42 alpha:1.0];
                if ([child isKindOfClass:[UIImageView class]])
                    ((UIImageView *)child).tintColor = [UIColor colorWithRed:0.31 green:0.32 blue:0.42 alpha:1.0];
            }
        }
    }
    UIView *activeBtn = [_sidebar viewWithTag:100 + tabIndex];
    activeBtn.backgroundColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.08];
    activeBtn.layer.borderColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.28].CGColor;
    for (UIView *child in activeBtn.subviews) {
        if ([child isKindOfClass:[UILabel class]])
            ((UILabel *)child).textColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1.0];
        if ([child isKindOfClass:[UIImageView class]])
            ((UIImageView *)child).tintColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1.0];
    }

    // Берём размер из mainTabContainer — он всегда правильный (задан в setupMenuUI)
    CGFloat tabX = mainTabContainer.frame.origin.x;
    CGFloat tabY = mainTabContainer.frame.origin.y;
    CGFloat tabW = mainTabContainer.frame.size.width;
    CGFloat tabH = mainTabContainer.frame.size.height;

    switch (tabIndex) {
        case 0:
        case 1:
        case 3:
        case 4:
        case 5: {
            // Restore menuContainer to original size if it was grown for Extra tab
            // Original size stored at setup time — re-derive from mainTabContainer
            CGRect mf = menuContainer.frame;
            CGFloat origH = mainTabContainer.frame.size.height + mainTabContainer.frame.origin.y;
            if (mf.size.height != origH && origH > 50) {
                CGFloat diff = mf.size.height - origH;
                menuContainer.frame = CGRectMake(mf.origin.x, mf.origin.y + diff * 0.5f,
                                                  mf.size.width, origH);
            }
            if (tabIndex == 0) {
                mainTabContainer.hidden = NO; mainTabContainer.userInteractionEnabled = YES;
            } else if (tabIndex == 1) {
                aimTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
                aimTabContainer.hidden = NO; aimTabContainer.userInteractionEnabled = YES;
            } else if (tabIndex == 3) {
                settingTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
                settingTabContainer.hidden = NO; settingTabContainer.userInteractionEnabled = YES;
            } else if (tabIndex == 4) {
                killTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
                killTabContainer.hidden = NO; killTabContainer.userInteractionEnabled = YES;
            } else {
                weaponsTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
                weaponsTabContainer.hidden = NO; weaponsTabContainer.userInteractionEnabled = YES;
            }
            break;
        }
        case 2: {
            // Compute content height from subviews
            CGFloat contentH = tabH;
            for (UIView *sv in extraTabContainer.subviews) {
                CGFloat bottom = CGRectGetMaxY(sv.frame);
                if (bottom > contentH) contentH = bottom;
            }
            contentH += 12;
            // Grow menuContainer temporarily to fit all sliders
            CGRect mf = menuContainer.frame;
            CGFloat extraGrow = MAX(0, contentH - tabH);
            menuContainer.frame = CGRectMake(mf.origin.x, mf.origin.y - extraGrow * 0.5f,
                                              mf.size.width, mf.size.height + extraGrow);
            CGFloat newTabH = contentH;
            extraTabContainer.frame = CGRectMake(tabX, tabY, tabW, newTabH);
            extraTabContainer.clipsToBounds = YES;
            extraTabContainer.hidden = NO;
            extraTabContainer.userInteractionEnabled = YES;
            break;
        }
    }
}

- (void)drawPreviewElements {
    CGFloat w = previewView.frame.size.width;  
    CGFloat h = previewView.frame.size.height; 
    CGFloat cx = w / 2;
    CGFloat startY = 45; 
    
    previewNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, w, 15)];
    previewNameLabel.text = @"ID PlayerName";
    previewNameLabel.textColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1.0];
    previewNameLabel.textAlignment = NSTextAlignmentCenter;
    previewNameLabel.font = [UIFont boldSystemFontOfSize:11];
    [previewContentContainer addSubview:previewNameLabel];
    
    CGFloat barW = 70;
    healthBarContainer = [[UIView alloc] initWithFrame:CGRectMake(cx - barW/2, 38, barW, 2)];
    healthBarContainer.backgroundColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.8];
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
- (void)toggleAimbot:(CustomSwitch *)sender {
    isAimbot = sender.isOn;
    // Reset aim sensitivity sliders to 1.0 on every toggle (ON or OFF)
    aimSensX = 1.0f;
    aimSensY = 1.0f;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_sensXSlider) { _sensXSlider.value = 1.0f; }
        if (_sensYSlider) { _sensYSlider.value = 1.0f; }
        if (_sensXLabel)  { _sensXLabel.text = @"1.00"; }
        if (_sensYLabel)  { _sensYLabel.text = @"1.00"; }
    });
}


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

// ── Hack toggles ─────────────────────────────────────────────────────
- (void)toggleInfiniteAmmo:(CustomSwitch *)s { isInfiniteAmmo = s.isOn; }
- (void)toggleDamageBoost:(CustomSwitch *)s  { isDamageBoost  = s.isOn; }
- (void)toggleSpeedBoost:(CustomSwitch *)s   { isSpeedBoost   = s.isOn; }
- (void)toggleEnemyOnMap:(CustomSwitch *)s   { isEnemyOnMap   = s.isOn; }
- (void)toggleSuperArmor:(CustomSwitch *)s   { isSuperArmor   = s.isOn; }
- (void)toggleInstantSkill:(CustomSwitch *)s { isInstantSkill = s.isOn; }
- (void)toggleOneHitKill:(CustomSwitch *)s  { isOneHitKill  = s.isOn; }
- (void)toggleInvincible:(CustomSwitch *)s  { isInvincible  = s.isOn; }
- (void)toggleInfGrenades:(CustomSwitch *)s { isInfGrenades = s.isOn; }
- (void)toggleKillAura:(CustomSwitch *)s   { isKillAura  = s.isOn; }
- (void)toggleKillAll:(CustomSwitch *)s    { isKillAll    = s.isOn; }
- (void)toggleFreezeEnemies:(CustomSwitch *)s { isFreezeEnemies = s.isOn; }

// ── Value scan helper ────────────────────────────────────────────────



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

    CGFloat W = self.superview ? self.superview.bounds.size.width  : self.bounds.size.width;
    CGFloat H = self.superview ? self.superview.bounds.size.height : self.bounds.size.height;
    if (W < 10 || H < 10) { W = self.bounds.size.width; H = self.bounds.size.height; }

    // При повороте экрана — центрируем меню и возвращаем кнопку в безопасное место
    static CGSize _lastSize;
    if (!CGSizeEqualToSize(_lastSize, CGSizeMake(W, H))) {
        _lastSize = CGSizeMake(W, H);

        // Меню — по центру
        if (menuContainer) {
            [UIView animateWithDuration:0.3 animations:^{
                self->menuContainer.center = CGPointMake(W / 2.0, H / 2.0);
            }];
        }

        // Кнопка — прижимаем к левому верхнему углу с отступом
        if (floatingButton) {
            CGFloat btnW = floatingButton.bounds.size.width;
            CGFloat btnH = floatingButton.bounds.size.height;
            CGFloat margin = 20.0;
            // Если кнопка вышла за новые границы — возвращаем, иначе оставляем на месте
            CGFloat cx = floatingButton.center.x;
            CGFloat cy = floatingButton.center.y;
            cx = MAX(btnW / 2 + margin, MIN(cx, W - btnW / 2 - margin));
            cy = MAX(btnH / 2 + margin, MIN(cy, H - btnH / 2 - margin));
            [UIView animateWithDuration:0.3 animations:^{
                self->floatingButton.center = CGPointMake(cx, cy);
            }];
        }
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
    CGFloat w = self.superview ? self.superview.bounds.size.width  : self.bounds.size.width;
    CGFloat h = self.superview ? self.superview.bounds.size.height : self.bounds.size.height;
    if (w < 10 || h < 10) { w = self.bounds.size.width; h = self.bounds.size.height; }
    menuContainer.center = CGPointMake(w / 2.0, h / 2.0);
}
// Обработчики tap — используем gesture recognizers вместо ручного touchesEnded
// Это надёжно работает со всей иерархией UIScrollView/PassThroughScrollView
- (void)handleTabTap:(UITapGestureRecognizer *)gr {
    NSInteger tag = gr.view.tag;
    if (tag >= 100 && tag <= 105) {
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

// Gesture delegate — containerPan yields to UIScrollView, HUDSlider, CustomSwitch
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v != nil) {
        if ([v isKindOfClass:[HUDSlider class]])  return NO;
        if ([v isKindOfClass:[CustomSwitch class]]) return NO;
        if ([v isKindOfClass:[UIScrollView class]]) return NO; // don't steal scroll touches
        if (v == menuContainer) break;
        v = v.superview;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // Always yield to UIScrollView pan (extraScroll)
    if ([other.view isKindOfClass:[UIScrollView class]]) return YES;
    // Yield to HUDSlider pan
    UIView *ov = other.view;
    while (ov) {
        if ([ov isKindOfClass:[HUDSlider class]]) return YES;
        ov = ov.superview;
    }
    return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *viewToMove = (gesture.view == floatingButton) ? floatingButton : menuContainer;
    CGPoint translation = [gesture translationInView:self];

    if (gesture.state == UIGestureRecognizerStateBegan ||
        gesture.state == UIGestureRecognizerStateChanged) {
        // Во время перетаскивания — полная свобода, никаких ограничений
        viewToMove.center = CGPointMake(
            viewToMove.center.x + translation.x,
            viewToMove.center.y + translation.y
        );
        [gesture setTranslation:CGPointZero inView:self];
    }

    // При отпускании — плавно возвращаем в экран
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {

        // superview (_blurView) всегда полноэкранный — берём его размеры
        CGFloat containerW = self.superview ? self.superview.bounds.size.width  : self.bounds.size.width;
        CGFloat containerH = self.superview ? self.superview.bounds.size.height : self.bounds.size.height;
        if (containerW < 10 || containerH < 10) {
            containerW = [UIScreen mainScreen].bounds.size.width;
            containerH = [UIScreen mainScreen].bounds.size.height;
        }
        CGFloat halfW = viewToMove.bounds.size.width  / 2.0;
        CGFloat halfH = viewToMove.bounds.size.height / 2.0;
        CGFloat margin = 8.0;

        CGFloat cx = viewToMove.center.x;
        CGFloat cy = viewToMove.center.y;

        // Меню полностью внутри экрана при отпускании
        cx = MAX(halfW + margin, MIN(cx, containerW - halfW - margin));
        cy = MAX(halfH + margin, MIN(cy, containerH - halfH - margin));

        [UIView animateWithDuration:0.3
                               delay:0
              usingSpringWithDamping:0.75
               initialSpringVelocity:0.5
                             options:UIViewAnimationOptionCurveEaseOut
                          animations:^{ viewToMove.center = CGPointMake(cx, cy); }
                          completion:nil];
    }
}

- (void)SetUpBase {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (YES) {
            uint64_t base = (uint64_t)GetGameModule_Base((char*)ENCRYPT("freefireth"));
            if (base != 0 && base != Moudule_Base) {
                // Base changed (game restarted) — reset all state
                Moudule_Base = base;
                resetMatchState();
                __atomic_store_n(&_validFrameCount, 0, __ATOMIC_RELAXED);
            } else if (base == 0) {
                Moudule_Base = (uint64_t)-1;
            }
            // Re-check every 10 seconds to catch game restarts
            [NSThread sleepForTimeInterval:10.0];
        }
    });
}

- (void)updateFrame {
    if (!self.window) return;
    // Если предыдущий расчёт ещё не закончил — пропускаем кадр (нет очереди задач)
    if (_espBusy) return;
    _espBusy = YES;

    // Снапшот значений — читаем атомарно до перехода на background
    BOOL  _aimOn  = isAimbot;
    BOOL  _inMatch = isInMatch;
    float _fov    = aimFov;

    // FOV обновляем на main thread (CALayer не thread-safe)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_aimOn && _inMatch) {
            float vW = self.superview ? (float)self.superview.bounds.size.width  : (float)self.bounds.size.width;
            float vH = self.superview ? (float)self.superview.bounds.size.height : (float)self.bounds.size.height;
            if (vW < 10 || vH < 10) { vW = self.bounds.size.width; vH = self.bounds.size.height; }
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _fovLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
            _fovLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(vW/2.f, vH/2.f)
                radius:_fov startAngle:0 endAngle:M_PI*2 clockwise:YES].CGPath;
            _fovLayer.hidden = NO;
            [CATransaction commit];
        } else {
            _fovLayer.hidden = YES;
        }
    });

    // Весь тяжёлый расчёт — на background queue
    // memory reads, WorldToScreen, CGPath построение — всё там
    dispatch_async(_espQueue, ^{
        [self renderESP];
        _espBusy = NO;
    });
}

// Returns aim rotation adjusted by per-axis sensitivity
// aimSensX scales horizontal (yaw) component, aimSensY scales vertical (pitch)
Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias, Vector3 myLoc) {
    Vector3 dir = (targetLocation + Vector3(0, y_bias, 0)) - myLoc;
    // Apply axis sensitivity: scale X (horizontal) and Y (vertical) components
    dir.x *= aimSensX;
    dir.y *= aimSensY;
    return Quaternion::LookRotation(dir, Vector3(0, 1, 0));
}

// ── Kill tab helpers ─────────────────────────────────────────────
static void SetDataInt(uint64_t player, int varID, int value) {
    uint64_t pool = ReadAddr<uint64_t>(player + 0x68); // GL_IPRIDATAPOOL
    if (!isVaildPtr(pool)) return;
    uint64_t list = ReadAddr<uint64_t>(pool + 0x10);   // GL_POOL_LIST
    if (!isVaildPtr(list)) return;
    uint64_t item = ReadAddr<uint64_t>(list + 0x8 * varID + 0x20); // GL_POOL_ITEM
    if (!isVaildPtr(item)) return;
    WriteAddr<int>(item + 0x18, value);                // GL_POOL_VAL
}

void set_aim(uint64_t player, Quaternion rotation) {
    if (!isVaildPtr(player)) return;
    // Пишем в оба поля — аимбот работает стабильно
    // Небольшой рандомный noise делает статистику человекоподобной
    // rand offset ±0.01 рад (~0.5°) — незаметно для игрока, но меняет паттерн
    static uint32_t _seed = 12345;
    _seed = _seed * 1664525 + 1013904223; // LCG random
    float noise = ((_seed & 0xFF) / 255.0f - 0.5f) * 0.02f; // ±0.01
    // Добавляем noise к rotation через небольшое смещение вектора
    Quaternion noisy = rotation;
    noisy.x += noise;
    noisy.y += noise * 0.5f;
    float len = sqrtf(noisy.x*noisy.x + noisy.y*noisy.y + noisy.z*noisy.z + noisy.w*noisy.w);
    if (len > 0.001f) { noisy.x/=len; noisy.y/=len; noisy.z/=len; noisy.w/=len; }
    WriteAddr<Quaternion>(player + OFF_ROTATION, noisy); // 0x53C камера
    WriteAddr<Quaternion>(player + 0x172C,       noisy); // 0x172C пуля
}

bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    // 0x750 = <LPEIEILIKGC>k__BackingField (подтверждён в дампе)
    // Читаем как uint8, но только нижний бит = реальный bool
    uint8_t val = ReadAddr<uint8_t>(player + OFF_FIRING);
    return (val & 0x01) != 0;
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
    // Используем bold системный шрифт для чёткости ESP текста
    t.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:10].fontName;
    [_espLayer addSublayer:t];
    [_textPool addObject:t];
    _textPoolIndex++;
    return t;
}

- (void)_onOrientationChange:(NSNotification *)n {
    CGSize sc = UIScreen.mainScreen.bounds.size;
    float fw = (float)MAX(sc.width, sc.height);
    float fh = (float)MIN(sc.width, sc.height);
    _espVW = fw; _espVH = fh;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _espLayer.frame = CGRectMake(0, 0, fw, fh);
    [CATransaction commit];
}

// ── Full match-state reset (called on death, camera loss, match exit) ──
static void resetMatchState(void) {
    isInMatch         = NO;
}

- (void)renderESP {
    if (Moudule_Base == -1) return;

    // ── Primary match check: CurrentMatchGame from GameFacade (dump offset 0x8) ──
    // Non-zero only while inside a match — lobby/loading = 0
    uint64_t currentMatchGame = getCurrentMatchGame(Moudule_Base);
    if (!isVaildPtr(currentMatchGame)) {
        if (isInMatch) {
            // Just left match — full state reset
            resetMatchState();
            __atomic_store_n(&_validFrameCount, 0, __ATOMIC_RELAXED);
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                _boneLayer.path=nil; _boxLayer.path=nil;
                _boxInnerNear.path=nil; _boxInnerMid.path=nil;
                _boxInnerFar.path=nil;  _boxInnerKnocked.path=nil;
                _hpBgLayer.path=nil; _hpFillLayer.path=nil; _lineLayer.path=nil;
                for (CATextLayer *t in _textPool) t.hidden = YES;
                [CATransaction commit];
            });
        }
        return;
    }

    uint64_t matchGame = getMatchGame(Moudule_Base);
    uint64_t camera    = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        resetMatchState();
        __atomic_store_n(&_validFrameCount, 0, __ATOMIC_RELAXED);
        dispatch_async(dispatch_get_main_queue(), ^{
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            _boneLayer.path=nil; _boxLayer.path=nil;
            _boxInnerNear.path=nil; _boxInnerMid.path=nil;
            _boxInnerFar.path=nil;  _boxInnerKnocked.path=nil;
            _hpBgLayer.path=nil; _hpFillLayer.path=nil; _lineLayer.path=nil;
            for (CATextLayer *t in _textPool) t.hidden = YES;
            [CATransaction commit];
        });
        return;
    }
    // Increment valid frame counter — require 2 consecutive valid frames
    // before activating features (prevents stale pointer false positives)
    __atomic_add_fetch(&_validFrameCount, 1, __ATOMIC_RELAXED);
    BOOL matchReady = (_validFrameCount >= 5); // 5 frames ~83ms buffer
    isInMatch = matchReady;

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) return;

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) return;

    uint64_t camTransform = ReadAddr<uint64_t>(myPawnObject + OFF_CAMERA_TRANSFORM);
    Vector3 myLoc = getPositionExt(camTransform);

    // ── Hacks через PlayerAttributes @ player+0x680 ───────────────
    uint64_t attr = ReadAddr<uint64_t>(myPawnObject + 0x680);
    if (isVaildPtr(attr)) {
        if (isInfiniteAmmo) {
            WriteAddr<bool>(attr + 0xC9, true);  // ShootNoReload
            WriteAddr<bool>(attr + 0xC8, true);  // ReloadNoConsumeAmmoclip
            WriteAddr<int> (attr + 0x124, 9999); // BuffWeaponAmmoClip (снайпер)
            WriteAddr<int> (attr + 0x128, 9999); // TalentWeaponAmmoClip
        } else {
            WriteAddr<bool>(attr + 0xC9, false);
            WriteAddr<bool>(attr + 0xC8, false);
            WriteAddr<int> (attr + 0x124, 0);
            WriteAddr<int> (attr + 0x128, 0);
        }
        if (isDamageBoost) {
            WriteAddr<float>(attr + 0x118, 2.0f); // BuffWeaponDamageScale
            WriteAddr<float>(attr + 0xFC,  2.0f); // DamageAdditionScale
        } else {
            WriteAddr<float>(attr + 0x118, 1.0f);
            WriteAddr<float>(attr + 0xFC,  1.0f);
        }
        if (isSpeedBoost) {
            WriteAddr<float>(attr + 0x250, 1.8f); // RunSpeedUpScale x1.8
        } else {
            WriteAddr<float>(attr + 0x250, 1.0f);
        }
        if (isEnemyOnMap) {
            WriteAddr<bool>(attr + 0x160, true); // ShowEnermyTargetOnMap
            WriteAddr<bool>(attr + 0x161, true); // ShowEnermyTargetOnHud
        } else {
            WriteAddr<bool>(attr + 0x160, false);
            WriteAddr<bool>(attr + 0x161, false);
        }
        if (isSuperArmor) {
            WriteAddr<bool>(attr + 0x248, true); // IsSuperArmorEnable
        } else {
            WriteAddr<bool>(attr + 0x248, false);
        }
        if (isInstantSkill) {
            WriteAddr<float>(attr + 0x188, 0.99f); // ActiveSkillCdReduction
            WriteAddr<float>(attr + 0x184, 0.99f); // PetSkillCDReduction
        } else {
            WriteAddr<float>(attr + 0x188, 0.0f);
            WriteAddr<float>(attr + 0x184, 0.0f);
        }
        if (isOneHitKill) {
            WriteAddr<float>(attr + 0xFC,  999.0f); // DamageAdditionScale x999
            WriteAddr<float>(attr + 0x118, 999.0f); // BuffWeaponDamageScale x999
        } else {
            WriteAddr<float>(attr + 0xFC,  1.0f);
            WriteAddr<float>(attr + 0x118, 1.0f);
        }
        if (isInfGrenades) {
            // ── CARPET BOMB ───────────────────────────────────────
            // CanGrenadeSplit OFF — никаких вертикальных осколков
            // Только основной взрыв с колоссальным радиусом
            // GrenadeStaticSplitTan = 0 блокирует вертикаль даже при Split ON
            WriteAddr<bool> (attr + 0x264, true);    // CanGrenadeSplit ON
            WriteAddr<int>  (attr + 0x268, 16);      // мало осколков — они горизонтальные
            WriteAddr<float>(attr + 0x26C, 0.01f);   // GrenadeSplitTime — почти сразу
            WriteAddr<float>(attr + 0x270, 0.0f);    // SubGrenadeExplodeTime — мгновенно
            WriteAddr<float>(attr + 0x274, 1.0f);    // VelocityFactor минимальный — не летят вверх
            WriteAddr<float>(attr + 0x278, 1.0f);    // VelocityFactorStatic
            WriteAddr<float>(attr + 0x27C, 50.0f);   // SubGrenadeRangeScale x50
            WriteAddr<float>(attr + 0x280, 99.0f);   // SubGrenadeDamageScale x99
            WriteAddr<float>(attr + 0x284, 1.0f);    // SubGrenadeModelScale
            WriteAddr<float>(attr + 0x288, 99.0f);   // MainGrenadeRangeScale x99 — ОГРОМНЫЙ
            WriteAddr<float>(attr + 0x28C, 99.0f);   // MainGrenadeDamageScale x99
            WriteAddr<float>(attr + 0x290, 5.0f);    // MainGrenadeModelScale большой
            WriteAddr<float>(attr + 0x294, 0.0f);    // GrenadeStaticSplitTan = 0 → горизонталь
        } else {
            WriteAddr<bool> (attr + 0x264, false);
            WriteAddr<float>(attr + 0x274, 1.0f);
            WriteAddr<float>(attr + 0x278, 1.0f);
            WriteAddr<float>(attr + 0x27C, 1.0f);
            WriteAddr<float>(attr + 0x280, 1.0f);
            WriteAddr<float>(attr + 0x284, 1.0f);
            WriteAddr<float>(attr + 0x288, 1.0f);
            WriteAddr<float>(attr + 0x28C, 1.0f);
            WriteAddr<float>(attr + 0x290, 1.0f);
            WriteAddr<float>(attr + 0x294, 0.5f);
        }
    }
    // ── Invincible: LastInvincibleOverTime @ 0x101C ───────────────
    // IsInvincible() проверяет: Time.time < LastInvincibleOverTime
    // FLT_MAX = 3.4e+38 → всегда неуязвим
    if (isInvincible) {
        WriteAddr<float>(myPawnObject + 0x101C, 3.402823466e+38f);
    }




    uint64_t playerList = ReadAddr<uint64_t>(match + OFF_PLAYERLIST);
    uint64_t tValue     = ReadAddr<uint64_t>(playerList + OFF_PLAYERLIST_ARR);
    int      totalCount = ReadAddr<int>(tValue + OFF_PLAYERLIST_CNT);
    // Защита от мусорного значения
    if (totalCount <= 0 || totalCount > 64) totalCount = 64;

    float *matrix = GetViewMatrix(camera);

    // Viewport: use cached screen size (updated on orientation change, not every frame).
    // _espVW/_espVH are updated by orientationDidChange notification — no main thread sync needed.
    float vW = _espVW > 100.f ? _espVW : 844.f;
    float vH = _espVH > 100.f ? _espVH : 390.f;
    if (vW < vH) { float tmp = vW; vW = vH; vH = tmp; }
    CGPoint center = CGPointMake(vW * 0.5f, vH * 0.5f);

    // Paths по цветовым зонам: Near(<40м) Mid(<100м) Far(>=100м) Knocked
    CGMutablePathRef boneNearPath    = CGPathCreateMutable();
    CGMutablePathRef boneMidPath     = CGPathCreateMutable();
    CGMutablePathRef boneFarPath     = CGPathCreateMutable();
    CGMutablePathRef boneKnockedPath = CGPathCreateMutable();
    CGMutablePathRef boxNearPath      = CGPathCreateMutable();
    CGMutablePathRef boxMidPath       = CGPathCreateMutable();
    CGMutablePathRef boxFarPath       = CGPathCreateMutable();
    CGMutablePathRef boxKnockedPath   = CGPathCreateMutable();
    // Inner box paths (for double-line effect)
    CGMutablePathRef boxInnerNearPath    = CGPathCreateMutable();
    CGMutablePathRef boxInnerMidPath     = CGPathCreateMutable();
    CGMutablePathRef boxInnerFarPath     = CGPathCreateMutable();
    CGMutablePathRef boxInnerKnockedPath = CGPathCreateMutable();
    CGMutablePathRef lineNearPath    = CGPathCreateMutable();
    CGMutablePathRef lineMidPath     = CGPathCreateMutable();
    CGMutablePathRef lineFarPath     = CGPathCreateMutable();
    CGMutablePathRef hpBgPath         = CGPathCreateMutable();
    CGMutablePathRef hpFillGreenPath  = CGPathCreateMutable(); // ratio > 0.6
    CGMutablePathRef hpFillYellowPath = CGPathCreateMutable(); // 0.3..0.6
    CGMutablePathRef hpFillRedPath    = CGPathCreateMutable(); // < 0.3
    CGMutablePathRef hpFillPath       = hpFillGreenPath;       // алиас

    // Выбор нужного bucket'а по дистанции/состоянию
    #define BONE_PATH       (isKnocked ? boneKnockedPath    : (dis<40.f ? boneNearPath    : (dis<100.f ? boneMidPath    : boneFarPath)))
    #define BOX_PATH        (isKnocked ? boxKnockedPath     : (dis<40.f ? boxNearPath     : (dis<100.f ? boxMidPath     : boxFarPath)))
    #define BOX_INNER_PATH  (isKnocked ? boxInnerKnockedPath: (dis<40.f ? boxInnerNearPath: (dis<100.f ? boxInnerMidPath: boxInnerFarPath)))
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
        bool isKnocked = ReadAddr<bool>(PawnObject + 0xA0)
                      || ReadAddr<bool>(PawnObject + 0x1110);


        // ── Kill tab логика ──────────────────────────────────────
        if (isKillAll) {
            // Пишем CurHP = 0 через PropertyDataPool (varID 0)
            SetDataInt(PawnObject, 0, 0);
        }
        if (isFreezeEnemies) {
            WriteAddr<bool>(PawnObject + 0x19E0, true);  // LockMove
        } else if (!isFreezeEnemies) {
            WriteAddr<bool>(PawnObject + 0x19E0, false); // restore
        }

        // ── Kill Aura: HP = 0 всем врагам в радиусе ─────────────────
        if (isKillAura) {
            Vector3 enemyPos = getPositionExt(getHip(PawnObject));
            float killDis = Vector3::Distance(myLoc, enemyPos);
            if (killDis <= g_killRadius) {
                // varID 0 = CurHP — пишем 0
                SetDataUInt16(PawnObject, 0, 0);
            }
        }

        // Читаем голову — для дистанции и aimbot
        uint64_t headNode = getHead(PawnObject);
        if (!isVaildPtr(headNode)) continue;
        Vector3 HeadPos = getPositionExt(headNode);

        float dis = Vector3::Distance(myLoc, HeadPos);
        // Жёсткий порог дальности ESP (400м — aimbot, 220м — рендер)
        if (dis > kESPMaxDistance) continue;

        // ── Обычный Aimbot ───────────────────────────────────────────
        if (isAimbot && dis <= aimDistance) {
            Vector3 ap = HeadPos;
            if (aimTarget == 1) {
                // Neck = interpolated between Head(75%) and Hip(25%) — no separate Neck bone
                Vector3 hPos = getPositionExt(getHead(PawnObject));
                uint64_t hipN = getHip(PawnObject);
                Vector3 neckAp = isVaildPtr(hipN)
                    ? hPos + (getPositionExt(hipN) - hPos) * 0.30f
                    : hPos;
                ap = neckAp;
            }
            else if (aimTarget == 2) ap = getPositionExt(getHip(PawnObject));
            Vector3 ws = WorldToScreen(ap, matrix, vW, vH);
            float dx = ws.x - center.x, dy = ws.y - center.y;
            float d2 = sqrtf(dx*dx+dy*dy);
            if (d2 <= aimFov) {
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

        // ── Stable box size: distance-based with focal correction ─────
        // Using toe-head projection causes pulsation when player moves.
        // Pure distance-based box size — stable, no pulsation, correct at any range.
        // Box from real head-toe projection — always matches skeleton scale.
        // Stabilised: blend with distance-based estimate to reduce pulsation.
        if (fabsf(matrix[5]) < 0.01f) continue;
        float rawH   = fabsf(s_HeadTop.y - s_Toe.y);
        float focalY = fabsf(matrix[5]) * (vH * 0.5f);
        float distH  = fmaxf(fminf(focalY * 1.80f / fmaxf(dis, 1.f), vH * 0.85f), 14.f);
        // 50/50 blend: real projection gives correct scale, distH stabilises it
        float boxH   = fmaxf(rawH, 14.f) * 0.5f + distH * 0.5f;
        boxH         = fmaxf(fminf(boxH, vH * 0.85f), 14.f);
        bool  isTiny = false;
        float boxW   = boxH * 0.45f;
        float bx     = s_Head.x - boxW * 0.5f;
        float by     = s_HeadTop.y;

        // Skip full detail rendering beyond kESPDetailDistance
        if (dis > kESPDetailDistance) continue;

        // Distance label color: green(close) → yellow(mid) → red(far)
        // Knocked = purple. Matches reference design.
        float acR, acG, acB;
        if (isKnocked)        { acR=0.7f; acG=0.5f; acB=1.f;  }  // purple = knocked
        else if (dis < 40.f)  { acR=0.1f; acG=0.9f; acB=0.3f; }  // green  = close
        else if (dis < 100.f) { acR=1.f;  acG=0.85f;acB=0.f;  }  // yellow = medium
        else                  { acR=1.f;  acG=0.2f; acB=0.2f; }  // red    = far
        float acA = isKnocked ? 0.75f : 0.95f;

        // ── SKELETON — all real bones from dump (Kuydum-verified offsets) ──
        if (isBone && dis <= 150.f ) {
            // Read all 13 joints — real offsets from obfuscated dump
            uint64_t nkNode = getNeck(PawnObject);
            uint64_t hpNode = getHip(PawnObject);
            uint64_t lsNode = getLeftShoulder(PawnObject);
            uint64_t rsNode = getRightShoulder(PawnObject);
            uint64_t leNode = getLeftElbow(PawnObject);
            uint64_t reNode = getRightElbow(PawnObject);
            uint64_t lhNode = getLeftHand(PawnObject);
            uint64_t rhNode = getRightHand(PawnObject);
            uint64_t lkNode = getLeftKnee(PawnObject);   // 0x5F0 — real knee
            uint64_t rkNode = getRightKnee(PawnObject);  // 0x5F8 — real knee
            uint64_t lfNode = getLeftFoot(PawnObject);   // 0x600 — real foot
            uint64_t rfNode = getRightFoot(PawnObject);  // 0x608 — real foot

            // Guard — skip skeleton if critical nodes invalid
            if (!isVaildPtr(hpNode) || !isVaildPtr(lkNode)) goto skip_skeleton;

            {
                // Neck = 20% from Head toward Hip (no reliable Neck bone in this build)
                uint64_t hpNodeForNeck = getHip(PawnObject);
                Vector3 neckWorld = isVaildPtr(hpNodeForNeck)
                    ? HeadPos + (getPositionExt(hpNodeForNeck) - HeadPos) * 0.30f
                    : HeadPos;
                Vector3 s_Neck = WorldToScreen(neckWorld, matrix, vW, vH);
                (void)nkNode; // nkNode not used — Neck is interpolated
                Vector3 s_Hip  = WorldToScreen(getPositionExt(hpNode), matrix, vW, vH);
                Vector3 s_LS   = WorldToScreen(getPositionExt(lsNode), matrix, vW, vH);
                Vector3 s_RS   = WorldToScreen(getPositionExt(rsNode), matrix, vW, vH);
                Vector3 s_LE   = WorldToScreen(getPositionExt(leNode), matrix, vW, vH);
                Vector3 s_RE   = WorldToScreen(getPositionExt(reNode), matrix, vW, vH);
                Vector3 s_LH   = WorldToScreen(getPositionExt(lhNode), matrix, vW, vH);
                Vector3 s_RH   = WorldToScreen(getPositionExt(rhNode), matrix, vW, vH);
                Vector3 s_LK   = WorldToScreen(getPositionExt(lkNode), matrix, vW, vH);
                Vector3 s_RK   = WorldToScreen(getPositionExt(rkNode), matrix, vW, vH);
                Vector3 s_LF   = WorldToScreen(getPositionExt(lfNode), matrix, vW, vH);
                Vector3 s_RF   = WorldToScreen(getPositionExt(rfNode), matrix, vW, vH);

                CGMutablePathRef bp = BONE_PATH;

                // ── Direct bone coords — no clamp (real 3D joints) ────
                float LS_x = s_LS.x, LS_y = s_LS.y;
                float RS_x = s_RS.x, RS_y = s_RS.y;
                float LE_x = s_LE.x, LE_y = s_LE.y;
                float RE_x = s_RE.x, RE_y = s_RE.y;
                float LH_x = s_LH.x, LH_y = s_LH.y;
                float RH_x = s_RH.x, RH_y = s_RH.y;
                float LK_x = s_LK.x, LK_y = s_LK.y;
                float RK_x = s_RK.x, RK_y = s_RK.y;
                float LF_x = s_LF.x, LF_y = s_LF.y;
                float RF_x = s_RF.x, RF_y = s_RF.y;
                float NK_x = s_Neck.x, NK_y = s_Neck.y;
                float HP_x = s_Hip.x,  HP_y = s_Hip.y;
                float HD_x = s_Head.x,  HD_y = s_Head.y;

                // ══════════════════════════════════════════════════════
                // SKELETON — только реальные 3D кости, никаких вычислений
                // Все joint coordinates напрямую из дампа
                // ══════════════════════════════════════════════════════

                // ── SPINE: Head → Hip ─────────────────────────────────
                CGPathMoveToPoint(bp,nil,HD_x, HD_y);
                CGPathAddLineToPoint(bp,nil,HP_x, HP_y);

                // ── SHOULDERS BAR: LS → RS ────────────────────────────
                // Горизонтальная перекладина плеч — всегда правильная
                CGPathMoveToPoint(bp,nil,LS_x, LS_y);
                CGPathAddLineToPoint(bp,nil,RS_x, RS_y);

                // ── TORSO: spine → shoulders (крест) ─────────────────
                // Соединяем середину spine с серединой shoulder bar
                float spMid_x = (HD_x + HP_x) * 0.5f;
                float spMid_y = (HD_y + HP_y) * 0.5f;
                float shMid_x = (LS_x + RS_x) * 0.5f;
                float shMid_y = (LS_y + RS_y) * 0.5f;
                CGPathMoveToPoint(bp,nil,spMid_x, spMid_y);
                CGPathAddLineToPoint(bp,nil,shMid_x, shMid_y);

                // ── LEFT ARM: LS → LE → LH ────────────────────────────
                CGPathMoveToPoint(bp,nil,LS_x, LS_y);
                CGPathAddLineToPoint(bp,nil,LE_x, LE_y);
                CGPathAddLineToPoint(bp,nil,LH_x, LH_y);

                // ── RIGHT ARM: RS → RE → RH ───────────────────────────
                CGPathMoveToPoint(bp,nil,RS_x, RS_y);
                CGPathAddLineToPoint(bp,nil,RE_x, RE_y);
                CGPathAddLineToPoint(bp,nil,RH_x, RH_y);

                // ── LEGS: Hip → Knee → Foot ───────────────────────────
                // Прямо от Hip joint — никаких вычисленных hipOffset
                // Колени и стопы реальные 3D кости — правильные при любом угле
                CGPathMoveToPoint(bp,nil,HP_x, HP_y);
                CGPathAddLineToPoint(bp,nil,LK_x, LK_y);
                CGPathAddLineToPoint(bp,nil,LF_x, LF_y);

                CGPathMoveToPoint(bp,nil,HP_x, HP_y);
                CGPathAddLineToPoint(bp,nil,RK_x, RK_y);
                CGPathAddLineToPoint(bp,nil,RF_x, RF_y);
            }
            skip_skeleton:;
        }

        // ── BOX: double rectangle (reference design) ─────────────────
        // Outer rect — defines the bounding box
        // Inner rect — inset 2px, thinner line → double-line visual effect
        if (isBox) {
            float gap = 2.f; // px gap between outer and inner
            CGMutablePathRef xp = BOX_PATH;
            CGPathAddRect(xp, nil, CGRectMake(bx, by, boxW, boxH));

            // Inner rect — collected into path pool, applied in main commit
            CGPathAddRect(BOX_INNER_PATH, nil, CGRectMake(bx+gap, by+gap, boxW-gap*2, boxH-gap*2));
        }

        // ── HP BAR: vertical, left side of box (reference design) ──────
        if (isHealth) {
            int MaxHP = get_MaxHP(PawnObject);
            if (MaxHP > 0) {
                float ratio  = fmaxf(0.f, fminf(1.f, (float)CurHP / MaxHP));
                float hpBW   = 3.f;                    // bar width
                float hpBX   = bx - hpBW - 2.f;       // left of box
                float hpBY   = by;
                // Background (dark)
                CGPathAddRect(hpBgPath, nil, CGRectMake(hpBX, hpBY, hpBW, boxH));
                // Fill — always green (reference style), knocked = empty
                if (!isKnocked) {
                    float fillH = boxH * ratio;
                    // Fill from bottom up
                    CGPathAddRect(hpFillGreenPath, nil,
                        CGRectMake(hpBX, hpBY + boxH - fillH, hpBW, fillH));
                }
            }
        }

        // ── NAME: above box ──────────────────────────────────────────
        if (isName) {
            NSString *name = GetNickName(PawnObject);
            const char *ns = (name && name.length) ? [name UTF8String] : "?";
            float nW = MAX(boxW, 60.f);
            float nY = by - 13.f;
            char nb[48]; strncpy(nb, ns, 47); nb[47]=0;
            float nfs = fmaxf(8.f, fminf(13.f, boxH * 0.09f));
            addText(nb, bx+(boxW-nW)*0.5f, nY, nW, 12.f, nfs, 1.f,1.f,1.f,1.f, 0.45f, 1);
        }

        // ── DISTANCE: below box ──────────────────────────────────────
        if (isDis) {
            char db[24];
            if (isKnocked)    snprintf(db,sizeof(db),"KO %.0fM",dis);
            else if (dis < 1) snprintf(db,sizeof(db),"<1M");
            else              snprintf(db,sizeof(db),"%.0fM",dis);
            float distW = MAX(boxW, 55.f);
            float distX = bx + (boxW - distW) * 0.5f;
            float dfs = fmaxf(8.f, fminf(13.f, boxH * 0.09f));
            addText(db, distX, by+boxH+3.f, distW, 12.f, dfs, acR,acG,acB,acA, 0.f, 1);
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

    // ── Aimbot apply ──────────────────────────────────────────────────
    // Throttle: пишем rotation не чаще 10 раз/сек (было 60fps)
    // Снижает паттерн детекции — выглядит как редкое обращение
    // ── Silent Aim: пишем только в m_CurrentAimRotation (пуля) ────────
    // Камера НЕ двигается — выглядит как обычный игрок
    // Пуля летит в цель независимо от куда смотрит камера
    // Пишем только в момент нажатия кнопки стрельбы (edge)
    // Silent aim: всегда активен когда враг в FOV (не зависит от isFire)
    // OFF_FIRING offset непроверен — используем Always режим
    bool shouldAim = isVaildPtr(bestTarget);
    if (isAimbot && matchReady && shouldAim) {
        Vector3 ap;
        if      (aimTarget==0) ap = getPositionExt(getHead(bestTarget));
        else if (aimTarget==1) {
            Vector3 hPos = getPositionExt(getHead(bestTarget));
            uint64_t hipN = getHip(bestTarget);
            ap = isVaildPtr(hipN)
                ? hPos + (getPositionExt(hipN) - hPos) * 0.30f
                : hPos;
        }
        else ap = getPositionExt(getHip(bestTarget));
        set_aim(myPawnObject, GetRotationToLocation(ap, 0.1f, myLoc));
    }


    // No Recoil и Speed — работают через value-scan (разовые патчи), не renderESP

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
        // Боксы по зонам (outer + inner)
        _boxNear.path    = b_box ? boxNearPath    : nil;
        _boxMid.path     = b_box ? boxMidPath     : nil;
        _boxFar.path     = b_box ? boxFarPath     : nil;
        _boxKnocked.path = b_box ? boxKnockedPath : nil;
        _boxInnerNear.path    = b_box ? boxInnerNearPath    : nil;
        _boxInnerMid.path     = b_box ? boxInnerMidPath     : nil;
        _boxInnerFar.path     = b_box ? boxInnerFarPath     : nil;
        _boxInnerKnocked.path = b_box ? boxInnerKnockedPath : nil;
        // Линии по зонам
        _lineNear.path = b_line ? lineNearPath : nil;
        _lineMid.path  = b_line ? lineMidPath  : nil;
        _lineFar.path  = b_line ? lineFarPath  : nil;
        // HP
        _hpBgLayer.path      = b_hp ? hpBgPath         : nil;
        // HP fill — single green layer (yellow/red are aliases pointing to same layer)
        // Merge all HP fill paths into one for single color bar
        if (b_hp) {
            CGMutablePathRef mergedHP = CGPathCreateMutableCopy(hpFillGreenPath);
            CGPathAddPath(mergedHP, nil, hpFillYellowPath);
            CGPathAddPath(mergedHP, nil, hpFillRedPath);
            _hpFillGreen.path = mergedHP;
            CGPathRelease(mergedHP);
        } else {
            _hpFillGreen.path = nil;
        }
        // Yellow/Red aliases — already point to same layer, skip redundant assignments

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
        CGPathRelease(boxInnerNearPath);CGPathRelease(boxInnerMidPath);
        CGPathRelease(boxInnerFarPath); CGPathRelease(boxInnerKnockedPath);
        CGPathRelease(lineNearPath);    CGPathRelease(lineMidPath);
        CGPathRelease(lineFarPath);
        CGPathRelease(hpBgPath);
        // Release all HP paths (green/yellow/red are separate CGPath objects
        // even though yellow/red layers alias to green)
        CGPathRelease(hpFillGreenPath);
        CGPathRelease(hpFillYellowPath);
        CGPathRelease(hpFillRedPath);

        // No Recoil работает на background queue — main thread ничего не рендерит
    });
}

@end
