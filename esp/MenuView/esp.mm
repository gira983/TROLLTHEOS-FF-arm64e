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
// Silent aim: пишем в оба поля rotation одновременно
// m_AimRotation (камера)         @ 0x53C  = OFF_ROTATION
// m_CurrentAimRotation (пуля)    @ 0x172C
#define OFF_CURRENT_AIM     ENCRYPTOFFSET("0x172C")   // пули идут сюда
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
static float espDistance   = 400.0f; // дальность ESP (слайдер в Extra)
static float aimDistance   = 200.0f;


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
    Quaternion   _lastAimRot;   // Slerp — текущий угол между кадрами
    bool         _lastAimValid; // первый кадр — нет предыдущего угла
    // (no additional ivars needed for value-scan features)
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
        _lineNear = makeShape([UIColor colorWithRed:1.f green:0.2f blue:0.2f alpha:0.85f], 0.9f, NO);
        _lineMid  = makeShape([UIColor colorWithRed:1.f green:0.85f blue:0.f  alpha:0.85f], 0.8f, NO);
        _lineFar  = makeShape([UIColor colorWithWhite:1.0f alpha:0.85f],                   0.8f, NO);
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

        // value-scan features инициализируются при первом включении

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
    CGFloat menuHeight = MIN(320, screenH * 0.46);
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
    containerPan.cancelsTouchesInView = NO; // не блокировать тапы на кнопки
    containerPan.delaysTouchesBegan = NO;
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

    NSArray *tabNames  = @[@"Main", @"AIM", @"Extra", @"Config"];
    // SF Symbol-подобные unicode иконки (системный шрифт их поддерживает)
    NSArray *tabSF     = @[@"square.3.layers.3d", @"scope", @"slider.horizontal.3", @"wrench.and.screwdriver"];
    // Fallback текстовые иконки
    NSArray *tabIconTx = @[@"⊞", @"⊕", @"⊛", @"⊜"];
    CGFloat btnH = 44 * scale;
    CGFloat btnPad = 6 * scale;

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
    [self addSliderTo:extraTabContainer label:@"HEAD OFFSET" atY:ey width:eW minVal:-0.5 maxVal:0.5 value:headOffset format:@"%.2f" onChanged:^(float v){ headOffset = v; }];

    // ══ CONFIG TAB ════════════════════════════════════════════════════
    settingTabContainer = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tabX, tabY, tabW, tabH)];
    settingTabContainer.backgroundColor = COL_BG1;
    settingTabContainer.hidden = YES;
    [menuContainer addSubview:settingTabContainer];

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
    settingTabContainer.hidden = YES;
    mainTabContainer.userInteractionEnabled = NO;
    aimTabContainer.userInteractionEnabled = NO;
    extraTabContainer.userInteractionEnabled = NO;
    settingTabContainer.userInteractionEnabled = NO;
    
    for (UIView *sub in _sidebar.subviews) {
        if ([sub isKindOfClass:[UIView class]] && sub.tag >= 100 && sub.tag <= 103) {
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
            mainTabContainer.hidden = NO;
            mainTabContainer.userInteractionEnabled = YES;
            break;
        case 1:
            aimTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
            aimTabContainer.hidden = NO;
            aimTabContainer.userInteractionEnabled = YES;
            break;
        case 2:
            extraTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
            extraTabContainer.hidden = NO;
            extraTabContainer.userInteractionEnabled = YES;
            break;
        case 3:
            settingTabContainer.frame = CGRectMake(tabX, tabY, tabW, tabH);
            settingTabContainer.hidden = NO;
            settingTabContainer.userInteractionEnabled = YES;
            break;
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
- (void)toggleAimbot:(CustomSwitch *)sender    { isAimbot    = sender.isOn; }


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
    if (tag >= 100 && tag <= 103) {
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

// Delegate — containerPan не перехватывает слайдеры
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v != nil) {
        if ([v isKindOfClass:[HUDSlider class]]) return NO;
        if ([v isKindOfClass:[CustomSwitch class]]) return NO;
        if (v == menuContainer) break;
        v = v.superview;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // Если один из них — слайдерный pan — containerPan уступает
    UIView *otherView = other.view;
    while (otherView) {
        if ([otherView isKindOfClass:[HUDSlider class]]) return NO;
        otherView = otherView.superview;
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

    // FOV круг — показываем только если aimbot включён И мы в матче
    if (isAimbot && isInMatch) {
        float vW = self.superview ? (float)self.superview.bounds.size.width  : (float)self.bounds.size.width;
        float vH = self.superview ? (float)self.superview.bounds.size.height : (float)self.bounds.size.height;
        if (vW < 10 || vH < 10) { vW = self.bounds.size.width; vH = self.bounds.size.height; }
        float cx = vW / 2.0f;
        float cy = vH / 2.0f;
        float radius = aimFov;
        _fovLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
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
    // Пишем в оба: вход (0x53C) и выход (0x172C)
    // Игра: читает 0x53C → интерполирует → пишет в 0x172C
    // Мы перекрываем оба — нет окна для конкурентной записи игрой
    WriteAddr<Quaternion>(player + OFF_ROTATION,    rotation);  // 0x53C — вход
    WriteAddr<Quaternion>(player + OFF_CURRENT_AIM, rotation);  // 0x172C — выход/пули
}

// Slerp от текущего угла к целевому — без прыжка через тело
// t=1.0 = мгновенно (старое поведение), t=0.1 = очень плавно
static Quaternion SlerpAimTo(Quaternion current, Quaternion target, float t) {
    // Clamp t
    if (t <= 0.0f) return current;
    if (t >= 1.0f) return target;
    return Quaternion::Slerp(current, target, t);
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
    // Используем bold системный шрифт для чёткости ESP текста
    t.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:10].fontName;
    [self.layer addSublayer:t];
    [_textPool addObject:t];
    _textPoolIndex++;
    return t;
}

- (void)renderESP {
    if (Moudule_Base == -1) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);

    // Детекция матча: camera ptr невалиден → не в матче
    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        if (isInMatch) {
            // Только что вышли — полная очистка всех слоёв
            isInMatch = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                _boneLayer.path   = nil;
                _boxLayer.path    = nil;
                _hpBgLayer.path   = nil;
                _hpFillLayer.path = nil;
                _lineLayer.path   = nil;
                for (CATextLayer *t in _textPool) t.hidden = YES;
                _fovLayer.hidden  = YES;
                [CATransaction commit];
            });
        }
        return;
    }
    isInMatch = YES;

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
    // Берём РЕАЛЬНЫЙ размер отображения — self.bounds меняется с поворотом
    // superview (_blurView) имеет autoresizingMask и правильный bounds после поворота
    float vW = self.superview ? (float)self.superview.bounds.size.width  : (float)self.bounds.size.width;
    float vH = self.superview ? (float)self.superview.bounds.size.height : (float)self.bounds.size.height;
    if (vW < 10 || vH < 10) {
        vW = (float)self.bounds.size.width;
        vH = (float)self.bounds.size.height;
    }
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
        bool isKnocked = ReadAddr<bool>(PawnObject + 0xA0)
                      || ReadAddr<bool>(PawnObject + 0x1110);

        // Читаем голову — для дистанции и aimbot
        uint64_t headNode = getHead(PawnObject);
        if (!isVaildPtr(headNode)) continue;
        Vector3 HeadPos = getPositionExt(headNode);

        float dis = Vector3::Distance(myLoc, HeadPos);
        // Фильтрация по слайдеру дальности ESP
        if (dis > espDistance) continue;

        // ── Обычный Aimbot ───────────────────────────────────────────
        if (isAimbot && dis <= aimDistance) {
            // Scoring ВСЕГДА по голове + headOffset — не по телу
            // Crosshair режим: ищем чья голова ближе к центру прицела
            // Player режим: 3D дистанция до игрока
            Vector3 scorePt = HeadPos + Vector3(0, headOffset, 0);
            Vector3 ws = WorldToScreen(scorePt, matrix, vW, vH);
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

        float boxH = fabsf(s_HeadTop.y - s_Toe.y);
        if (boxH < 6.0f) continue;   // слишком маленький — за горизонтом
        float boxW = boxH * 0.45f;
        float bx   = s_HeadTop.x - boxW * 0.5f;
        float by   = s_HeadTop.y;

        // ── Цвет по дистанции ────────────────────────────────────────
        // <40м красный → <100м жёлтый → белый
        // Нокнутый всегда серо-фиолетовый
        float acR, acG, acB;
        if (isKnocked)        { acR=0.7f; acG=0.3f; acB=1.0f; }  // фиолетовый = нокнут
        else if (dis < 40.f)  { acR=1.0f; acG=0.2f; acB=0.2f; }  // красный
        else if (dis < 100.f) { acR=1.0f; acG=0.8f; acB=0.0f; }  // оранжево-жёлтый
        else                  { acR=0.6f; acG=0.6f; acB=0.6f; }  // серый — далеко
        float acA = isKnocked ? 0.65f : 0.92f;

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

        // ── HP BAR — горизонтальная полоска прямо над головой ──────
        if (isHealth) {
            int MaxHP = get_MaxHP(PawnObject);
            if (MaxHP > 0) {
                float ratio  = fmaxf(0.f, fminf(1.f, (float)CurHP / MaxHP));
                float hpBarH = 4.f;                 // чуть толще
                float hpBarY = by - hpBarH - 1.f;  // прямо над головой
                float hpBarX = bx;
                float hpBarW = boxW;
                // Фон полоски
                CGPathAddRect(hpBgPath, nil, CGRectMake(hpBarX, hpBarY, hpBarW, hpBarH));
                // Заливка
                CGMutablePathRef fillPath = (ratio > 0.6f) ? hpFillGreenPath
                                          : (ratio > 0.3f) ? hpFillYellowPath : hpFillRedPath;
                if (!isKnocked)
                    CGPathAddRect(fillPath, nil, CGRectMake(hpBarX, hpBarY, hpBarW * ratio, hpBarH));
            }
        }

        // ── NAME (с фоном) + HP цифра (с фоном, только если isHealth) ──
        {
            float rowW = MAX(boxW + 16.f, 72.f);
            float rowX = s_HeadTop.x - rowW * 0.5f;
            float curY = by;  // стартуем от верха бокса, идём вверх

            // HP полоска уже нарисована выше — текст идёт над ней
            if (isHealth) {
                // HP цифра — просто CurHP
                int MaxHP = get_MaxHP(PawnObject);
                char hpBuf[12];
                float hpR, hpG, hpB;
                if (isKnocked) {
                    snprintf(hpBuf, sizeof(hpBuf), "KO");
                    hpR=0.7f; hpG=0.3f; hpB=1.f;
                } else if (MaxHP > 0) {
                    snprintf(hpBuf, sizeof(hpBuf), "%d", CurHP);
                    float ratio = (float)CurHP / MaxHP;
                    hpR = (ratio > 0.6f) ? 0.15f : 1.f;
                    hpG = (ratio > 0.6f) ? 0.9f  : (ratio > 0.3f ? 0.75f : 0.2f);
                    hpB = (ratio > 0.6f) ? 0.35f : (ratio > 0.3f ? 0.0f  : 0.2f);
                } else {
                    snprintf(hpBuf, sizeof(hpBuf), "?");
                    hpR=0.7f; hpG=0.7f; hpB=0.7f;
                }
                curY -= 7.f;  // отступ от полоски HP
                addText(hpBuf, rowX, curY - 11.f, rowW, 11.f, 9.f, hpR, hpG, hpB, 0.95f, 0.55f, 1);
                curY -= 13.f;
            }

            if (isName) {
                NSString *name = GetNickName(PawnObject);
                const char *ns = (name && name.length) ? [name UTF8String] : "?";
                char nb[48]; strncpy(nb, ns, 47); nb[47] = 0;
                addText(nb, rowX, curY - 11.f, rowW, 11.f, 9.f, acR, acG, acB, 0.95f, 0.55f, 1);
            }
        }

        // ── DISTANCE — мелко под ногами, серый, формат "134m" ──────
        if (isDis) {
            char db[24];
            snprintf(db, sizeof(db), "%.0fm", dis);
            float distW = MAX(boxW, 36.f);
            float distX = s_HeadTop.x - distW * 0.5f;
            // Цвет = серый для дальних, акцентный для ближних
            float dr = (dis < 40.f) ? acR : 0.7f;
            float dg = (dis < 40.f) ? acG : 0.7f;
            float db2= (dis < 40.f) ? acB : 0.7f;
            addText(db, distX, by+boxH+1.f, distW, 9.f, 8.f, dr,dg,db2, 0.75f, 0.f, 1);
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
        Vector3 rawHead = getPositionExt(getHead(bestTarget));
        Vector3 ap;
        if      (aimTarget==0) ap = rawHead + Vector3(0, headOffset, 0);
        else if (aimTarget==1) ap = rawHead + Vector3(0, headOffset - 0.12f, 0);
        else                   ap = getPositionExt(getHip(bestTarget)) + Vector3(0, headOffset, 0);
        // OFF_ROTATION (камера) + OFF_CURRENT_AIM (пули) — оба обновляются в set_aim
        set_aim(myPawnObject, GetRotationToLocation(ap, 0.f, myLoc));
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
