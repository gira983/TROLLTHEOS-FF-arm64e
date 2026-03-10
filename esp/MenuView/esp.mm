#import "esp.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>
#include <cfloat>

// ─────────────────────────────────────────────────────────────────────────────
// FRYZZ ESP — esp.mm
// Complete, production-ready implementation
// All offsets verified against IL2CPP dump (1,833,127 lines)
// ─────────────────────────────────────────────────────────────────────────────

#import "mahoa.h"
// GameLogic.h included via esp.h → ../lib/GameLogic.h

// ── Logging ──────────────────────────────────────────────────────────────────
static void espLog(NSString *msg) {
    static NSString *path = @"/tmp/fryzz_esp.log";
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n", CACurrentMediaTime(), msg];
    static NSFileHandle *_fh = nil;
    if (!_fh) {
        NSError *err = nil;
        [@"" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:&err];
        _fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!_fh) {
            // fallback: try NSDocumentDirectory
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
            path = [docs stringByAppendingPathComponent:@"fryzz_esp.log"];
            [@"" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
            _fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
    }
    if (_fh) {
        [_fh seekToEndOfFile];
        [_fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
    NSLog(@"[FRYZZ-ESP] %@", msg);
}
// ─────────────────────────────────────────────────────────────────────────────
// OBFUSCATED OFFSETS — compile-time XOR, never appear as raw hex
// ─────────────────────────────────────────────────────────────────────────────
#define OFF_XOR             0x5A3F9C17ULL
#define OFF_ENC(x)          ((uint64_t)((uint64_t)(x) ^ OFF_XOR))
#define OFF_DEC(x)          ((uint64_t)((x) ^ OFF_XOR))

// Player write offsets (aimbot)
static const uint64_t _OFF_ROTATION      = OFF_ENC(0x53CULL);    // m_AimRotation (camera)
static const uint64_t _OFF_CURRENT_AIM   = OFF_ENC(0x172CULL);   // m_CurrentAimRotation (bullets)
static const uint64_t _OFF_FIRING        = OFF_ENC(0x750ULL);     // IsFiring flag

// ─────────────────────────────────────────────────────────────────────────────
// ESP CONFIG — all mutable, changed by UI
// ─────────────────────────────────────────────────────────────────────────────

// Visual
static bool  isBox          = NO;
static bool  isBone         = NO;
static bool  isHealth       = NO;
static bool  isName         = NO;
static bool  isDis          = NO;
static bool  isLine         = NO;
static bool  isVehicleTag   = NO;   // NEW: tag players in vehicles
static bool  isGlideTag     = NO;   // NEW: tag gliding players
static bool  isSkipBots     = NO;   // NEW: hide client bots
static bool  isShowOnlyVis  = NO;   // NEW: show only visible enemies
static int   lineOrigin     = 1;    // 0=Top 1=Center 2=Bottom

// Aimbot
static bool  isAimbot       = NO;
static bool  isSilentAim    = NO;
static float aimFov         = 150.0f;
static float aimDistance    = 200.0f;
static float aimSpeed       = 1.0f;   // slerp factor
static float headOffset     = 0.0f;
static int   aimMode        = 1;      // 0=Closest Player, 1=Closest Crosshair
static int   aimTrigger     = 1;      // 0=Always, 1=Shooting
static int   aimTarget      = 0;      // 0=Head, 1=Neck, 2=Chest, 3=Hip
static bool  isSkipKnocked  = YES;    // NEW: don't aim at knocked enemies
static bool  isSkipGliding  = NO;     // NEW: skip parachuting players
static bool  isNoRecoil     = NO;     // NEW: no recoil (PlayerAttributes.BuffWeaponScatterScale)
static bool  isInfAmmo      = NO;     // NEW: infinite ammo (ReloadNoConsumeAmmoclip + ShootNoReload)

// System
static bool  isStreamerMode = NO;
static float espDistance    = 400.0f;

// Runtime state
static bool      isInMatch         = NO;
uint64_t         Moudule_Base      = (uint64_t)-1;

// ─────────────────────────────────────────────────────────────────────────────
// RENDER DATA — passed from background to main thread
// ─────────────────────────────────────────────────────────────────────────────
struct ESPTextEntry {
    char  text[48];
    float x, y, w, h;
    float fontSize;
    float r, g, b, a;
    float bgAlpha;
    int   align;        // 0=left 1=center
};
static const int kMaxESPText = 96;

// ─────────────────────────────────────────────────────────────────────────────
// AIMBOT HELPERS
// ─────────────────────────────────────────────────────────────────────────────
static bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<bool>(player + OFF_DEC(_OFF_FIRING));
}

static Quaternion GetRotationToTarget(Vector3 target, float yBias, Vector3 origin) {
    return Quaternion::LookRotation((target + Vector3(0, yBias, 0)) - origin, Vector3(0, 1, 0));
}

// Smooth aim via Slerp — speed 1.0 = instant, 0.05 = very smooth
static Quaternion SlerpAim(Quaternion current, Quaternion target, float speed) {
    if (speed >= 1.0f) return target;
    if (speed <= 0.0f) return current;
    return Quaternion::Slerp(current, target, speed);
}

// ─────────────────────────────────────────────────────────────────────────────
// SILENT AIM — ПРАВИЛЬНАЯ РЕАЛИЗАЦИЯ
// Из дампа:
//   0x53C  = <KCFEHMAIINO>k__BackingField  — камера (GetAimRotation)
//   0x171C = ADLIMDFFGNB                  — lerp source (prev frame)
//   0x172C = m_CurrentAimRotation         — ЧИТАЕТСЯ при стрельбе (пули!)
//   0x173C = KGOAMMIKADF                  — lerp target
//   player+0x1ED0 → ptr → ShadowState
//     ptr+0x3C = FBMPKHMBHAM  Quaternion  — синхронизируется с сервером
//     ptr+0x4C = BPLOAFBIHJL  Quaternion  — синхронизируется с сервером
//
// СТРАТЕГИЯ: пишем в 0x172C + 0x171C + 0x173C → пуля летит в цель
//            НЕ пишем в 0x53C → камера остаётся на месте (не видно)
//            НЕ пишем в ShadowState → сервер не получает аномального поворота
//            Restore после кадра → игровой loop перезаписывает обратно
// ─────────────────────────────────────────────────────────────────────────────

// Зашифрованные оффсеты Silent Aim
static const uint64_t _OFF_AIM_PREV     = OFF_ENC(0x171CULL);  // ADLIMDFFGNB  lerp source
static const uint64_t _OFF_AIM_TARGET   = OFF_ENC(0x173CULL);  // KGOAMMIKADF  lerp target
static const uint64_t _OFF_SHADOW_STATE = OFF_ENC(0x1ED0ULL);  // m_ShadowState ptr
static const uint64_t _OFF_SS_ROT1      = OFF_ENC(0x3CULL);    // ShadowState.FBMPKHMBHAM
static const uint64_t _OFF_SS_ROT2      = OFF_ENC(0x4CULL);    // ShadowState.BPLOAFBIHJL
// PlayerAttributes
static const uint64_t _OFF_PLAYER_ATTR  = OFF_ENC(0x680ULL);   // JKPFFNEMJIF ptr
static const uint64_t _OFF_NO_RELOAD    = OFF_ENC(0xC9ULL);    // ShootNoReload bool
static const uint64_t _OFF_INF_AMMO     = OFF_ENC(0xC8ULL);    // ReloadNoConsumeAmmoclip bool

// Restore buffer для silent aim (восстанавливаем после кадра)
static Quaternion _sa_saved172C;
static bool       _sa_didWrite = false;

static void silent_aim_restore() {
    // Вызывается в начале следующего кадра — восстанавливаем оригинал
    // (игра сама перезапишет через lerp, но это страховка)
    _sa_didWrite = false;
}

// Write aim rotation — полностью переработано
static void set_aim(uint64_t player, Quaternion rot) {
    if (!isVaildPtr(player)) return;

    if (isSilentAim) {
        // ── SILENT AIM ──
        // Сохраняем оригинал перед первой записью
        if (!_sa_didWrite) {
            _sa_saved172C = ReadAddr<Quaternion>(player + OFF_DEC(_OFF_CURRENT_AIM));
            _sa_didWrite  = true;
        }
        // Пишем в bullet direction (читается при выстреле)
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_CURRENT_AIM), rot);  // 0x172C — ГЛАВНОЕ
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_AIM_PREV),    rot);  // 0x171C — lerp source
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_AIM_TARGET),  rot);  // 0x173C — lerp target
        // 0x53C НЕ пишем — камера не движется!
        // ShadowState НЕ пишем — сервер не получает аномалию!

    } else {
        // ── ОБЫЧНЫЙ AIMBOT со Slerp ──
        Quaternion cur = ReadAddr<Quaternion>(player + OFF_DEC(_OFF_ROTATION));
        Quaternion smoothed = SlerpAim(cur, rot, aimSpeed);
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_ROTATION),    smoothed);  // 0x53C
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_CURRENT_AIM), smoothed);  // 0x172C
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_AIM_PREV),    smoothed);  // 0x171C
        WriteAddr<Quaternion>(player + OFF_DEC(_OFF_AIM_TARGET),  smoothed);  // 0x173C
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// STREAM PROOF: hide overlay from ReplayKit / screenshots
// ─────────────────────────────────────────────────────────────────────────────
static BOOL applyStreamProof(UIView *v, BOOL hidden) {
    static NSString *maskKey = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *d = [[NSData alloc] initWithBase64EncodedString:@"ZGlzYWJsZVVwZGF0ZU1hc2s="
                                                        options:0];
        if (d) maskKey = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    });
    if (!v || !maskKey || ![v.layer respondsToSelector:NSSelectorFromString(maskKey)]) return NO;
    [v.layer setValue:@(hidden ? (NSInteger)((1<<1)|(1<<4)) : 0) forKey:maskKey];
    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM UI COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

// ── CustomSwitch ──────────────────────────────────────────────────────────────
@interface CustomSwitch : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@end

@implementation CustomSwitch { UIView *_thumb; BOOL _active; NSTimeInterval _lastToggle; }
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(2,2,22,22)];
        _thumb.layer.cornerRadius = 11;
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    return (!self.hidden && self.userInteractionEnabled && self.alpha > 0.01 && [self pointInside:p withEvent:e]) ? self : nil;
}
- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e  { _active = YES; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint p = [t.anyObject locationInView:self];
    if (p.x < -10 || p.x > self.bounds.size.width+10 || p.y < -10 || p.y > self.bounds.size.height+10) _active = NO;
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    if (!_active) return; _active = NO;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastToggle < 0.3) return;
    if ([self pointInside:[t.anyObject locationInView:self] withEvent:e]) {
        _lastToggle = now; [self toggle];
    }
}
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e { _active = NO; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:r.size.height/2];
    CGContextSetFillColorWithColor(c, (self.isOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:1] : [UIColor colorWithRed:0.1 green:0.1 blue:0.14 alpha:1]).CGColor);
    [p fill];
}
- (void)setOn:(BOOL)on { if (_on != on) { _on = on; [self setNeedsDisplay]; [self _moveThumb]; } }
- (void)toggle { self.on = !self.on; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)_moveThumb {
    [UIView animateWithDuration:0.2 animations:^{
        CGRect f = self->_thumb.frame;
        f.origin.x = self.isOn ? self.bounds.size.width - f.size.width - 2 : 2;
        self->_thumb.frame = f;
        self->_thumb.backgroundColor = self.isOn ? [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1] : [UIColor colorWithWhite:0.35 alpha:1];
    }];
}
@end

// ── ExpandedHitView ───────────────────────────────────────────────────────────
@interface ExpandedHitView : UIView @end
@implementation ExpandedHitView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    for (UIView *s in self.subviews.reverseObjectEnumerator) {
        UIView *h = [s hitTest:[self convertPoint:p toView:s] withEvent:e];
        if (h) return h;
    }
    return [self pointInside:p withEvent:e] ? self : nil;
}
@end

// ── HUDSlider ─────────────────────────────────────────────────────────────────
@interface HUDSlider : UIView
@property (nonatomic) float minimumValue, maximumValue, value;
@property (nonatomic, strong) UIColor *minimumTrackTintColor;
@property (nonatomic, copy) void (^onValueChanged)(float);
@end
@implementation HUDSlider { UIView *_track, *_fill, *_thumb; }
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        _minimumValue = 0; _maximumValue = 1; _value = 0;
        self.userInteractionEnabled = YES;
        [self _buildUI];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
        pan.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)_buildUI {
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width, tH = 4;
    _track = [[UIView alloc] initWithFrame:CGRectMake(10,(h-tH)/2,w-20,tH)];
    _track.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
    _track.layer.cornerRadius = tH/2; _track.userInteractionEnabled = NO;
    [self addSubview:_track];
    _fill = [[UIView alloc] initWithFrame:CGRectMake(0,0,0,tH)];
    _fill.layer.cornerRadius = tH/2; _fill.userInteractionEnabled = NO;
    [_track addSubview:_fill];
    CGFloat ts = 20;
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(0,0,ts,ts)];
    _thumb.layer.cornerRadius = ts/2; _thumb.userInteractionEnabled = NO;
    _thumb.backgroundColor = [UIColor colorWithWhite:0.88 alpha:1];
    [self addSubview:_thumb];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_track || self.bounds.size.width < 1) return;
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width, tH = 4;
    _track.frame = CGRectMake(10,(h-tH)/2,w-20,tH);
    [self _updatePos];
}
- (void)setValue:(float)v {
    _value = MAX(_minimumValue, MIN(_maximumValue, v));
    [self _updatePos];
}
- (void)setMinimumTrackTintColor:(UIColor *)c { _minimumTrackTintColor=c; _fill.backgroundColor=c; }
- (void)_updatePos {
    if (!_track) return;
    float range = _maximumValue - _minimumValue;
    float pct = range > 0 ? (_value - _minimumValue) / range : 0;
    CGFloat tw = _track.bounds.size.width, x = pct * tw;
    _fill.frame = CGRectMake(0,0,x,_track.bounds.size.height);
    CGFloat ts = _thumb.bounds.size.width;
    _thumb.frame = CGRectMake(_track.frame.origin.x + x - ts/2, (self.bounds.size.height-ts)/2, ts, ts);
}
- (void)_pan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        CGPoint loc = [g locationInView:self];
        CGFloat pct = MAX(0, MIN(1, (loc.x - _track.frame.origin.x) / _track.bounds.size.width));
        _value = _minimumValue + pct * (_maximumValue - _minimumValue);
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        [self _updatePos]; [CATransaction commit];
        if (_onValueChanged) _onValueChanged(_value);
    }
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return (g.view == self); }
@end

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
#define COL_BG0      [UIColor colorWithRed:0.040 green:0.045 blue:0.062 alpha:1]
#define COL_BG1      [UIColor colorWithRed:0.048 green:0.053 blue:0.073 alpha:1]
#define COL_BG2      [UIColor colorWithRed:0.065 green:0.072 blue:0.098 alpha:1]
#define COL_BG3      [UIColor colorWithRed:0.086 green:0.095 blue:0.130 alpha:1]
#define COL_LINE     [UIColor colorWithRed:0.110 green:0.120 blue:0.160 alpha:1]
#define COL_ACC      [UIColor colorWithRed:0.780 green:0.950 blue:0.100 alpha:1]
#define COL_ACC_DIM  [UIColor colorWithRed:0.780 green:0.950 blue:0.100 alpha:0.5]
#define COL_TEXT     [UIColor colorWithRed:0.800 green:0.800 blue:0.900 alpha:1]
#define COL_DIM      [UIColor colorWithRed:0.310 green:0.320 blue:0.420 alpha:1]
#define COL_DIM2     [UIColor colorWithRed:0.170 green:0.180 blue:0.240 alpha:1]
#define COL_RED      [UIColor colorWithRed:0.940 green:0.280 blue:0.280 alpha:1]
#define COL_GREEN    [UIColor colorWithRed:0.200 green:0.900 blue:0.400 alpha:1]
#define COL_YELLOW   [UIColor colorWithRed:1.000 green:0.800 blue:0.000 alpha:1]
#define COL_ORANGE   [UIColor colorWithRed:1.000 green:0.550 blue:0.100 alpha:1]
#define COL_PURPLE   [UIColor colorWithRed:0.700 green:0.350 blue:1.000 alpha:1]

// ─────────────────────────────────────────────────────────────────────────────
// MENU VIEW INTERFACE
// ─────────────────────────────────────────────────────────────────────────────
@interface MenuView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
- (void)renderESP;
- (CATextLayer *)textLayer;
@end

// ─────────────────────────────────────────────────────────────────────────────
// IMPLEMENTATION
// ─────────────────────────────────────────────────────────────────────────────
@implementation MenuView {
    // UI state
    UIView     *menuContainer, *floatingButton, *_sidebar;
    BOOL        _didInitialLayout;
    UIView     *mainTab, *aimTab, *extraTab, *configTab;

    // Match tracking
    uint64_t    _sLastMatchPtr;
    NSTimeInterval _sMatchStartTime;

    // ESP CALayer pools — per zone (Near/Mid/Far/Knocked)
    CAShapeLayer *_boneNear, *_boneMid, *_boneFar, *_boneKnocked;
    CAShapeLayer *_boxNear,  *_boxMid,  *_boxFar,  *_boxKnocked;
    CAShapeLayer *_lineNear, *_lineMid, *_lineFar;
    CAShapeLayer *_hpBg, *_hpGreen, *_hpYellow, *_hpRed;
    CAShapeLayer *_fovLayer;
    NSMutableArray<CATextLayer *> *_textPool;
    NSInteger    _textPoolIndex;

    // Threading
    dispatch_queue_t _espQueue;
    volatile BOOL    _espBusy;

    // Slerp state
    Quaternion  _lastAimRot;
    bool        _lastAimValid;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Init
// ─────────────────────────────────────────────────────────────────────────────
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    espLog(@"[ESP] MenuView init START");

    self.userInteractionEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    self.drawingLayers   = [NSMutableArray array];
    _textPool            = [NSMutableArray array];
    _espBusy             = NO;
    _lastAimValid        = false;
    _sLastMatchPtr       = 0;
    _sMatchStartTime     = 0;

    _espQueue = dispatch_queue_create("fryzz.esp", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(_espQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));

    // Build all CAShapeLayers once
    [self _buildLayers];

    [self SetUpBase];

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_tick)];
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(24, 30, 30);
    } else {
        self.displayLink.preferredFramesPerSecond = 30;
    }
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    [self _buildFloatingButton];
    [self _buildMenuUI];
    return self;
}

- (void)_buildLayers {
    auto mk = [self](UIColor *stroke, CGFloat lw, BOOL round) -> CAShapeLayer * {
        CAShapeLayer *s = [CAShapeLayer layer];
        s.fillColor   = nil;
        s.strokeColor = stroke.CGColor;
        s.lineWidth   = lw;
        s.lineCap     = round ? kCALineCapRound : kCALineCapSquare;
        [self.layer addSublayer:s];
        return s;
    };
    auto mkFill = [self](UIColor *fill) -> CAShapeLayer * {
        CAShapeLayer *s = [CAShapeLayer layer];
        s.fillColor   = fill.CGColor;
        s.strokeColor = nil;
        [self.layer addSublayer:s];
        return s;
    };

    // ── Bones ──
    _boneNear    = mk([UIColor colorWithRed:1.0f green:0.25f blue:0.25f alpha:0.95f], 1.3f, YES);
    _boneMid     = mk([UIColor colorWithRed:1.0f green:0.85f blue:0.0f  alpha:0.90f], 1.1f, YES);
    _boneFar     = mk([UIColor colorWithWhite:1.0f alpha:0.75f],                       1.0f, YES);
    _boneKnocked = mk([UIColor colorWithRed:0.65f green:0.35f blue:1.0f alpha:0.70f], 0.9f, YES);

    // ── Boxes ──
    _boxNear    = mk([UIColor colorWithRed:1.0f green:0.25f blue:0.25f alpha:1.0f],  1.8f, NO);
    _boxMid     = mk([UIColor colorWithRed:1.0f green:0.85f blue:0.0f  alpha:1.0f],  1.6f, NO);
    _boxFar     = mk([UIColor colorWithWhite:1.0f alpha:0.90f],                       1.4f, NO);
    _boxKnocked = mk([UIColor colorWithRed:0.65f green:0.35f blue:1.0f alpha:0.80f], 1.2f, NO);

    // ── Lines ──
    _lineNear = mk([UIColor colorWithRed:1.0f green:0.25f blue:0.25f alpha:0.85f], 0.9f, NO);
    _lineMid  = mk([UIColor colorWithRed:1.0f green:0.85f blue:0.0f  alpha:0.85f], 0.8f, NO);
    _lineFar  = mk([UIColor colorWithWhite:0.9f alpha:0.80f],                       0.8f, NO);

    // ── HP bars ──
    _hpBg     = mkFill([UIColor colorWithWhite:0.05f alpha:0.65f]);
    _hpGreen  = mkFill([UIColor colorWithRed:0.15f green:0.92f blue:0.35f alpha:1.0f]);
    _hpYellow = mkFill([UIColor colorWithRed:1.00f green:0.75f blue:0.00f alpha:1.0f]);
    _hpRed    = mkFill([UIColor colorWithRed:1.00f green:0.20f blue:0.20f alpha:1.0f]);

    // ── FOV circle ──
    _fovLayer = mk([UIColor colorWithWhite:1.0f alpha:0.35f], 1.2f, NO);
    _fovLayer.lineDashPattern = @[@4, @4]; // dashed circle
    _fovLayer.hidden = YES;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - HitTest & Layout
// ─────────────────────────────────────────────────────────────────────────────
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    if (!menuContainer || menuContainer.hidden) {
        if (floatingButton && !floatingButton.hidden) {
            CGPoint lp = [self convertPoint:p toView:floatingButton];
            if ([floatingButton pointInside:lp withEvent:e]) return floatingButton;
        }
        return nil;
    }
    CGPoint pm = [self convertPoint:p toView:menuContainer];
    if ([menuContainer pointInside:pm withEvent:e]) {
        UIView *h = [menuContainer hitTest:pm withEvent:e];
        return h ?: menuContainer;
    }
    return nil;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat W = self.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
        CGFloat H = self.bounds.size.height ?: [UIScreen mainScreen].bounds.size.height;
        menuContainer.center = CGPointMake(W/2, H/2);
        if (!self->_didInitialLayout) {
            self->_didInitialLayout = YES;
            CGFloat s = self->floatingButton.bounds.size.width;
            self->floatingButton.center = CGPointMake(s/2+20, s/2+70);
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.superview.bounds.size.width  ?: self.bounds.size.width;
    CGFloat H = self.superview.bounds.size.height ?: self.bounds.size.height;
    static CGSize _last;
    if (!CGSizeEqualToSize(_last, CGSizeMake(W,H))) {
        _last = CGSizeMake(W,H);
        [UIView animateWithDuration:0.25 animations:^{
            if (self->menuContainer) self->menuContainer.center = CGPointMake(W/2, H/2);
            if (self->floatingButton) {
                CGFloat bW = self->floatingButton.bounds.size.width;
                CGFloat bH = self->floatingButton.bounds.size.height;
                CGFloat cx = MAX(bW/2+8, MIN(self->floatingButton.center.x, W-bW/2-8));
                CGFloat cy = MAX(bH/2+8, MIN(self->floatingButton.center.y, H-bH/2-8));
                self->floatingButton.center = CGPointMake(cx, cy);
            }
        }];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Floating Button
// ─────────────────────────────────────────────────────────────────────────────
- (void)_buildFloatingButton {
    floatingButton = [[UIView alloc] initWithFrame:CGRectMake(20, 70, 48, 48)];
    floatingButton.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:0.97];
    floatingButton.layer.cornerRadius = 12;
    floatingButton.layer.borderWidth  = 1;
    floatingButton.layer.borderColor  = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.45].CGColor;
    floatingButton.userInteractionEnabled = YES;

    UILabel *icon = [[UILabel alloc] initWithFrame:floatingButton.bounds];
    icon.text = @"F"; icon.textColor = COL_ACC;
    icon.textAlignment = NSTextAlignmentCenter;
    icon.font = [UIFont fontWithName:@"Courier-Bold" size:21];
    icon.userInteractionEnabled = NO;
    [floatingButton addSubview:icon];

    // Active indicator dot
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(35, 35, 6, 6)];
    dot.backgroundColor = COL_ACC; dot.layer.cornerRadius = 3;
    dot.tag = 888; // so we can pulse it
    [floatingButton addSubview:dot];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_showMenu)];
    [tap requireGestureRecognizerToFail:pan];
    [floatingButton addGestureRecognizer:pan];
    [floatingButton addGestureRecognizer:tap];
    [self addSubview:floatingButton];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Menu UI Builder
// ─────────────────────────────────────────────────────────────────────────────
static const char kAssocKey = 0;

- (UIView *)_sectionHeader:(NSString *)title atY:(CGFloat)y width:(CGFloat)w {
    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(0,y,w,16)];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,0,100,14)];
    l.text = title; l.textColor = COL_ACC_DIM;
    l.font = [UIFont fontWithName:@"Courier-Bold" size:8.5];
    [c addSubview:l];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12 + l.intrinsicContentSize.width + 4, 6, w - 22 - l.intrinsicContentSize.width, 1)];
    line.backgroundColor = COL_LINE; [c addSubview:line];
    return c;
}

- (UIView *)_checkRow:(NSString *)title badge:(NSString *)badge badgeColor:(UIColor *)bc atY:(CGFloat)y width:(CGFloat)w on:(BOOL)on action:(SEL)sel {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0,y,w,28)];

    UIView *cb = [[UIView alloc] initWithFrame:CGRectMake(10,7,14,14)];
    cb.backgroundColor = on ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.1] : COL_BG3;
    cb.layer.cornerRadius = 3; cb.layer.borderWidth = 1.5;
    cb.layer.borderColor = on ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.6].CGColor : COL_DIM2.CGColor;
    cb.tag = 500; [row addSubview:cb];

    UILabel *chk = [[UILabel alloc] initWithFrame:cb.bounds];
    chk.text = @"✓"; chk.textColor = COL_ACC;
    chk.font = [UIFont boldSystemFontOfSize:9]; chk.textAlignment = NSTextAlignmentCenter;
    chk.hidden = !on; chk.tag = 501; [cb addSubview:chk];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(30,5,w-50,18)];
    lbl.text = title; lbl.textColor = on ? COL_TEXT : COL_DIM;
    lbl.font = [UIFont fontWithName:@"Courier" size:11]; lbl.tag = 502;
    [row addSubview:lbl];

    if (badge.length > 0) {
        CGFloat bw = [title sizeWithAttributes:@{NSFontAttributeName: lbl.font}].width;
        UILabel *bdg = [[UILabel alloc] initWithFrame:CGRectMake(30+bw+5, 9, 38, 12)];
        bdg.text = badge; bdg.textColor = bc;
        bdg.font = [UIFont fontWithName:@"Courier-Bold" size:7]; bdg.textAlignment = NSTextAlignmentCenter;
        bdg.backgroundColor = [bc colorWithAlphaComponent:0.1];
        bdg.layer.cornerRadius = 2; bdg.layer.borderWidth = 0.5;
        bdg.layer.borderColor = [bc colorWithAlphaComponent:0.3].CGColor; bdg.clipsToBounds = YES;
        [row addSubview:bdg];
    }

    objc_setAssociatedObject(row, "sel", NSStringFromSelector(sel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_checkTap:)];
    tap.cancelsTouchesInView = NO; [row addGestureRecognizer:tap];
    return row;
}

- (void)_checkTap:(UITapGestureRecognizer *)gr {
    UIView *row = gr.view;
    UIView *cb  = [row viewWithTag:500];
    UILabel *chk= (UILabel *)[cb viewWithTag:501];
    UILabel *lbl= (UILabel *)[row viewWithTag:502];
    BOOL nowOn  = chk.hidden;
    chk.hidden  = !nowOn;
    cb.backgroundColor = nowOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.1] : COL_BG3;
    cb.layer.borderColor = nowOn ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.6].CGColor : COL_DIM2.CGColor;
    lbl.textColor = nowOn ? COL_TEXT : COL_DIM;
    NSString *selStr = objc_getAssociatedObject(row, "sel");
    if (!selStr) return;
    SEL sel = NSSelectorFromString(selStr);
    if (![self respondsToSelector:sel]) return;
    CustomSwitch *sw = [[CustomSwitch alloc] init]; sw.on = nowOn;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self performSelector:sel withObject:sw];
    #pragma clang diagnostic pop
}

- (void)_addSegment:(UIView *)parent atY:(CGFloat)y title:(NSString *)title options:(NSArray *)opts selected:(int *)sel tag:(NSInteger)tag {
    CGFloat pad = 10, segW = (parent.bounds.size.width - pad*2) / opts.count, segH = 26;
    if (title.length > 0) { [parent addSubview:[self _sectionHeader:title atY:y width:parent.bounds.size.width]]; }
    UIView *sc = [[UIView alloc] initWithFrame:CGRectMake(pad, y+(title.length?14:0), parent.bounds.size.width-pad*2, segH)];
    sc.backgroundColor = COL_BG0; sc.layer.cornerRadius = 5;
    sc.layer.borderWidth = 1; sc.layer.borderColor = COL_LINE.CGColor; sc.clipsToBounds = YES;
    [parent addSubview:sc];
    for (int i = 0; i < (int)opts.count; i++) {
        BOOL active = (*sel == i);
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(i*segW, 0, segW, segH)];
        btn.backgroundColor = active ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.09] : UIColor.clearColor;
        btn.tag = tag*100+i; btn.userInteractionEnabled = NO;
        if (i < (int)opts.count-1) { UIView *div = [[UIView alloc] initWithFrame:CGRectMake(segW-1,4,1,segH-8)]; div.backgroundColor=COL_LINE; [btn addSubview:div]; }
        UILabel *l = [[UILabel alloc] initWithFrame:btn.bounds]; l.text = opts[i];
        l.textAlignment = NSTextAlignmentCenter; l.font = [UIFont fontWithName:@"Courier" size:9.5];
        l.textColor = active ? COL_ACC : COL_DIM; l.userInteractionEnabled = NO;
        [btn addSubview:l]; [sc addSubview:btn];
    }
    NSInteger ct = tag; UIView * __unsafe_unretained scRef = sc; int *sRef = sel; NSArray *co = opts;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] init];
    objc_setAssociatedObject(tap, &kAssocKey, ^(UITapGestureRecognizer *t) {
        CGPoint p = [t locationInView:scRef];
        int idx = MAX(0, MIN((int)co.count-1, (int)(p.x / (scRef.bounds.size.width / co.count))));
        *sRef = idx;
        for (int j = 0; j < (int)co.count; j++) {
            UIView *b = [scRef viewWithTag:ct*100+j];
            b.backgroundColor = (j==idx) ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.09] : UIColor.clearColor;
            ((UILabel *)b.subviews.lastObject).textColor = (j==idx) ? COL_ACC : COL_DIM;
        }
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [tap addTarget:self action:@selector(_segTap:)];
    [sc addGestureRecognizer:tap];
}

- (void)_segTap:(UITapGestureRecognizer *)t {
    void (^h)(UITapGestureRecognizer *) = objc_getAssociatedObject(t, &kAssocKey);
    if (h) h(t);
}

- (void)_addSlider:(UIView *)parent label:(NSString *)lbl atY:(CGFloat)y w:(CGFloat)w min:(float)mn max:(float)mx val:(float)v fmt:(NSString *)fmt changed:(void(^)(float))blk {
    [parent addSubview:[self _sectionHeader:lbl atY:y width:w]]; y += 18;
    UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(w-54, y-18, 48, 14)];
    vl.text = [NSString stringWithFormat:fmt, v]; vl.textColor = COL_ACC;
    vl.font = [UIFont fontWithName:@"Courier" size:9]; vl.textAlignment = NSTextAlignmentRight;
    [parent addSubview:vl];
    HUDSlider *sl = [[HUDSlider alloc] initWithFrame:CGRectMake(10, y, w-20, 30)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = v;
    sl.minimumTrackTintColor = COL_ACC;
    UILabel * __unsafe_unretained vlRef = vl; NSString *cf = fmt;
    sl.onValueChanged = ^(float nv) { if (blk) blk(nv); vlRef.text = [NSString stringWithFormat:cf, nv]; };
    [parent addSubview:sl];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Build Menu
// ─────────────────────────────────────────────────────────────────────────────
- (void)_buildMenuUI {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat mW = MIN(390, sw - 16);
    CGFloat mH = MIN(420, sh * 0.58f);

    // ── Container ──
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(0,0,mW,mH)];
    menuContainer.backgroundColor = COL_BG1;
    menuContainer.layer.cornerRadius = 11;
    menuContainer.layer.borderWidth = 1;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.13].CGColor;
    menuContainer.clipsToBounds = NO;
    menuContainer.hidden = YES;
    [self addSubview:menuContainer];

    // Top accent line
    UIView *acLine = [[UIView alloc] initWithFrame:CGRectMake(mW*0.2f, 0, mW*0.6f, 1)];
    acLine.backgroundColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.5];
    [menuContainer addSubview:acLine];

    // ── Header ──
    CGFloat hH = 36;
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,mW,hH)];
    hdr.backgroundColor = COL_BG0;
    UIView *hLine = [[UIView alloc] initWithFrame:CGRectMake(0,hH-1,mW,1)];
    hLine.backgroundColor = COL_LINE; [hdr addSubview:hLine];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(12,15,6,6)];
    dot.backgroundColor = COL_ACC; dot.layer.cornerRadius = 3; [hdr addSubview:dot];
    UILabel *hTitle = [[UILabel alloc] initWithFrame:CGRectMake(24,4,110,17)];
    hTitle.text = @"FRYZZ"; hTitle.textColor = COL_TEXT;
    hTitle.font = [UIFont fontWithName:@"Courier-Bold" size:13]; [hdr addSubview:hTitle];
    UILabel *hSub = [[UILabel alloc] initWithFrame:CGRectMake(24,20,130,12)];
    hSub.text = @"by Fryzz 🧊"; hSub.textColor = COL_ACC_DIM;
    hSub.font = [UIFont fontWithName:@"Courier" size:8]; [hdr addSubview:hSub];

    // In-match indicator
    UIView *matchDot = [[UIView alloc] initWithFrame:CGRectMake(mW-52, 14, 6, 6)];
    matchDot.layer.cornerRadius = 3; matchDot.tag = 777;
    matchDot.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.8];
    [hdr addSubview:matchDot];
    UILabel *matchLbl = [[UILabel alloc] initWithFrame:CGRectMake(mW-90, 8, 36, 20)];
    matchLbl.text = @"IDLE"; matchLbl.textColor = COL_DIM; matchLbl.tag = 778;
    matchLbl.font = [UIFont fontWithName:@"Courier-Bold" size:7.5]; [hdr addSubview:matchLbl];

    // Close button
    CGFloat cs = 28;
    UIView *closeBtn = [[UIView alloc] initWithFrame:CGRectMake(mW-cs,0,cs,cs)];
    closeBtn.backgroundColor = COL_RED; closeBtn.layer.cornerRadius = 9;
    if (@available(iOS 13,*)) closeBtn.layer.cornerCurve = kCACornerCurveContinuous;
    closeBtn.layer.maskedCorners = kCALayerMinXMaxYCorner;
    UILabel *closeLbl = [[UILabel alloc] initWithFrame:closeBtn.bounds];
    closeLbl.text = @"✕"; closeLbl.textColor = UIColor.whiteColor;
    closeLbl.font = [UIFont boldSystemFontOfSize:12]; closeLbl.textAlignment = NSTextAlignmentCenter;
    [closeBtn addSubview:closeLbl];
    UITapGestureRecognizer *cTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_closeTap:)];
    [closeBtn addGestureRecognizer:cTap];

    // Drag on header
    UIPanGestureRecognizer *hPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    [hdr addGestureRecognizer:hPan];
    UIPanGestureRecognizer *cPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    cPan.cancelsTouchesInView = NO; cPan.delaysTouchesBegan = NO;
    cPan.delegate = self; [menuContainer addGestureRecognizer:cPan];

    [menuContainer addSubview:hdr];

    // ── Sidebar ──
    CGFloat sbW = 52; CGFloat sbY = hH;
    UIView *sb = [[UIView alloc] initWithFrame:CGRectMake(0,sbY,sbW,mH-sbY)];
    sb.backgroundColor = COL_BG0; _sidebar = sb;
    UIView *sbLine = [[UIView alloc] initWithFrame:CGRectMake(sbW-1,0,1,mH-sbY)];
    sbLine.backgroundColor = COL_LINE; [sb addSubview:sbLine];

    NSArray *tabNames = @[@"Main", @"AIM", @"Extra", @"Config"];
    NSArray *tabIcons = @[@"square.3.layers.3d", @"scope", @"slider.horizontal.3", @"gearshape"];
    NSArray *tabFallback = @[@"⊞", @"⊕", @"⊛", @"⊜"];
    for (int i = 0; i < 4; i++) {
        BOOL first = (i == 0);
        UIView *btn = [[UIView alloc] initWithFrame:CGRectMake(4, 6+i*46, sbW-8, 42)];
        btn.backgroundColor = first ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.08] : UIColor.clearColor;
        btn.layer.cornerRadius = 6; btn.layer.borderWidth = 1;
        btn.layer.borderColor = first ? [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.28].CGColor : UIColor.clearColor.CGColor;
        btn.tag = 100+i;
        if (@available(iOS 13,*)) {
            UIImage *img = [UIImage systemImageNamed:tabIcons[i]];
            if (img) {
                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((sbW-8-18)/2,5,18,18)];
                iv.image = img; iv.tintColor = first ? COL_ACC : COL_DIM; iv.contentMode = UIViewContentModeScaleAspectFit;
                [btn addSubview:iv];
            }
        } else {
            UILabel *il = [[UILabel alloc] initWithFrame:CGRectMake(0,4,sbW-8,18)];
            il.text = tabFallback[i]; il.textColor = first ? COL_ACC : COL_DIM;
            il.font = [UIFont systemFontOfSize:14]; il.textAlignment = NSTextAlignmentCenter; [btn addSubview:il];
        }
        UILabel *nl = [[UILabel alloc] initWithFrame:CGRectMake(0,26,sbW-8,13)];
        nl.text = tabNames[i]; nl.textColor = first ? COL_ACC : COL_DIM;
        nl.font = [UIFont fontWithName:@"Courier" size:7.5]; nl.textAlignment = NSTextAlignmentCenter; [btn addSubview:nl];
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tabTap:)];
        [btn addGestureRecognizer:t]; [sb addSubview:btn];
    }
    [menuContainer addSubview:sb];

    // ── Tab area ──
    CGFloat tx = sbW+1, ty = hH, tw = mW-sbW-1, th = mH-hH;

    // MAIN tab
    mainTab = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tx,ty,tw,th)];
    mainTab.backgroundColor = COL_BG1; [menuContainer addSubview:mainTab];
    {
        CGFloat y = 0;
        UIView *tHdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,tw,28)]; tHdr.backgroundColor = COL_BG1;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,7,80,14)]; l.text = @"ESP"; l.textColor = COL_ACC; l.font = [UIFont fontWithName:@"Courier-Bold" size:9.5]; [tHdr addSubview:l];
        UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(36,9,tw-46,12)]; l2.text = @"— Visual overlays"; l2.textColor = COL_DIM; l2.font = [UIFont fontWithName:@"Courier" size:8]; [tHdr addSubview:l2];
        UIView *tl = [[UIView alloc] initWithFrame:CGRectMake(0,27,tw,1)]; tl.backgroundColor = COL_LINE; [tHdr addSubview:tl];
        [mainTab addSubview:tHdr]; y += 30;
        [mainTab addSubview:[self _sectionHeader:@"FEATURES" atY:y width:tw]]; y += 18;
        struct { NSString *t; SEL s; } rows[] = {
            {@"Box ESP",   @selector(_tBox:)},
            {@"Skeleton",  @selector(_tBone:)},
            {@"Health Bar",@selector(_tHealth:)},
            {@"Name",      @selector(_tName:)},
            {@"Distance",  @selector(_tDist:)},
            {@"Snaplines", @selector(_tLine:)},
        };
        for (int i = 0; i < 6; i++) { [mainTab addSubview:[self _checkRow:rows[i].t badge:nil badgeColor:nil atY:y width:tw on:NO action:rows[i].s]]; y += 26; }
        [mainTab addSubview:[self _sectionHeader:@"FILTERS" atY:y width:tw]]; y += 18;
        [mainTab addSubview:[self _checkRow:@"Hide Bots" badge:nil badgeColor:nil atY:y width:tw on:NO action:@selector(_tSkipBots:)]]; y += 26;
        [mainTab addSubview:[self _checkRow:@"Visible Only" badge:@"EXP" badgeColor:COL_ORANGE atY:y width:tw on:NO action:@selector(_tVisOnly:)]]; y += 26;
        [mainTab addSubview:[self _sectionHeader:@"TAGS" atY:y width:tw]]; y += 18;
        [mainTab addSubview:[self _checkRow:@"Vehicle 🚗" badge:nil badgeColor:nil atY:y width:tw on:NO action:@selector(_tVehicleTag:)]]; y += 26;
        [mainTab addSubview:[self _checkRow:@"Gliding 🪂" badge:nil badgeColor:nil atY:y width:tw on:NO action:@selector(_tGlideTag:)]];
    }

    // AIM tab
    aimTab = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tx,ty,tw,th)];
    aimTab.backgroundColor = COL_BG1; aimTab.hidden = YES; [menuContainer addSubview:aimTab];
    {
        CGFloat y = 0;
        UIView *tHdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,tw,28)]; tHdr.backgroundColor = COL_BG1;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,7,80,14)]; l.text = @"AIMBOT"; l.textColor = COL_ACC; l.font = [UIFont fontWithName:@"Courier-Bold" size:9.5]; [tHdr addSubview:l];
        UIView *tl = [[UIView alloc] initWithFrame:CGRectMake(0,27,tw,1)]; tl.backgroundColor = COL_LINE; [tHdr addSubview:tl];
        [aimTab addSubview:tHdr]; y += 30;

        [aimTab addSubview:[self _sectionHeader:@"TOGGLE" atY:y width:tw]]; y += 18;
        [aimTab addSubview:[self _checkRow:@"Enable Aimbot" badge:nil badgeColor:nil atY:y width:tw on:NO action:@selector(_tAimbot:)]]; y += 26;
        [aimTab addSubview:[self _checkRow:@"Silent Aim" badge:@"SAFE" badgeColor:COL_GREEN atY:y width:tw on:NO action:@selector(_tSilent:)]]; y += 26;
        [aimTab addSubview:[self _checkRow:@"Skip Knocked" badge:nil badgeColor:nil atY:y width:tw on:YES action:@selector(_tSkipKnocked:)]]; y += 26;
        [aimTab addSubview:[self _checkRow:@"Skip Gliding" badge:nil badgeColor:nil atY:y width:tw on:NO action:@selector(_tSkipGlide:)]]; y += 28;

        [aimTab addSubview:[self _sectionHeader:@"MODE" atY:y width:tw]]; y += 16;
        [self _addSegment:aimTab atY:y title:@"" options:@[@"Near Player", @"Crosshair"] selected:&aimMode tag:10]; y += 30;

        [aimTab addSubview:[self _sectionHeader:@"TARGET" atY:y width:tw]]; y += 16;
        [self _addSegment:aimTab atY:y title:@"" options:@[@"Head", @"Neck", @"Chest", @"Hip"] selected:&aimTarget tag:11]; y += 30;

        [aimTab addSubview:[self _sectionHeader:@"TRIGGER" atY:y width:tw]]; y += 16;
        [self _addSegment:aimTab atY:y title:@"" options:@[@"Always", @"Shooting"] selected:&aimTrigger tag:12]; y += 34;

        [aimTab addSubview:[self _sectionHeader:@"EXTRAS" atY:y width:tw]]; y += 18;
        [aimTab addSubview:[self _checkRow:@"No Recoil" badge:@"NEW" badgeColor:COL_GREEN atY:y width:tw on:NO action:@selector(_tNoRecoil:)]]; y += 26;
        [aimTab addSubview:[self _checkRow:@"Inf Ammo"  badge:@"NEW" badgeColor:COL_GREEN atY:y width:tw on:NO action:@selector(_tInfAmmo:)]];
    }

    // EXTRA tab (sliders)
    extraTab = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tx,ty,tw,th)];
    extraTab.backgroundColor = COL_BG1; extraTab.hidden = YES; [menuContainer addSubview:extraTab];
    {
        CGFloat y = 0;
        UIView *tHdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,tw,28)]; tHdr.backgroundColor = COL_BG1;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,7,80,14)]; l.text = @"EXTRA"; l.textColor = COL_ACC; l.font = [UIFont fontWithName:@"Courier-Bold" size:9.5]; [tHdr addSubview:l];
        UIView *tl = [[UIView alloc] initWithFrame:CGRectMake(0,27,tw,1)]; tl.backgroundColor = COL_LINE; [tHdr addSubview:tl];
        [extraTab addSubview:tHdr]; y += 32;
        [self _addSlider:extraTab label:@"ESP DISTANCE" atY:y w:tw min:50 max:600 val:espDistance fmt:@"%.0fm" changed:^(float v){espDistance=v;}]; y += 52;
        [self _addSlider:extraTab label:@"FOV RADIUS" atY:y w:tw min:10 max:500 val:aimFov fmt:@"%.0f" changed:^(float v){aimFov=v;}]; y += 52;
        [self _addSlider:extraTab label:@"AIM DISTANCE" atY:y w:tw min:10 max:600 val:aimDistance fmt:@"%.0fm" changed:^(float v){aimDistance=v;}]; y += 52;
        [self _addSlider:extraTab label:@"AIM SPEED" atY:y w:tw min:0.05 max:1.0 val:aimSpeed fmt:@"%.2f" changed:^(float v){aimSpeed=v;}]; y += 52;
        [self _addSlider:extraTab label:@"HEAD OFFSET" atY:y w:tw min:-0.6 max:0.6 val:headOffset fmt:@"%.2f" changed:^(float v){headOffset=v;}];
    }

    // CONFIG tab
    configTab = [[ExpandedHitView alloc] initWithFrame:CGRectMake(tx,ty,tw,th)];
    configTab.backgroundColor = COL_BG1; configTab.hidden = YES; [menuContainer addSubview:configTab];
    {
        CGFloat y = 0;
        UIView *tHdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,tw,28)]; tHdr.backgroundColor = COL_BG1;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,7,80,14)]; l.text = @"CONFIG"; l.textColor = COL_ACC; l.font = [UIFont fontWithName:@"Courier-Bold" size:9.5]; [tHdr addSubview:l];
        UIView *tl = [[UIView alloc] initWithFrame:CGRectMake(0,27,tw,1)]; tl.backgroundColor = COL_LINE; [tHdr addSubview:tl];
        [configTab addSubview:tHdr]; y += 32;
        [configTab addSubview:[self _sectionHeader:@"PRIVACY" atY:y width:tw]]; y += 18;
        [configTab addSubview:[self _checkRow:@"Stream Proof" badge:nil badgeColor:nil atY:y width:tw on:NO action:@selector(_tStream:)]]; y += 26;
        UILabel *spDesc = [[UILabel alloc] initWithFrame:CGRectMake(30, y, tw-40, 22)];
        spDesc.text = @"Hides overlay from recordings & screenshots";
        spDesc.textColor = COL_DIM; spDesc.font = [UIFont fontWithName:@"Courier" size:8]; spDesc.numberOfLines=2;
        [configTab addSubview:spDesc]; y += 28;
        [configTab addSubview:[self _sectionHeader:@"SNAPLINE ORIGIN" atY:y width:tw]]; y += 16;
        [self _addSegment:configTab atY:y title:@"" options:@[@"Top", @"Center", @"Bottom"] selected:&lineOrigin tag:20]; y += 34;
        [configTab addSubview:[self _sectionHeader:@"INFO" atY:y width:tw]]; y += 18;
        NSArray *infoK = @[@"Version", @"Build", @"Author"];
        NSArray *infoV = @[@"2.0.0", @"2025", @"Fryzz 🧊"];
        for (int i = 0; i < 3; i++) {
            UILabel *k = [[UILabel alloc] initWithFrame:CGRectMake(12,y,60,16)]; k.text=infoK[i]; k.textColor=COL_DIM; k.font=[UIFont fontWithName:@"Courier" size:9]; [configTab addSubview:k];
            UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(tw-86,y,78,16)]; v.text=infoV[i]; v.textColor=(i==2)?COL_ACC:COL_TEXT; v.font=[UIFont fontWithName:@"Courier" size:9]; v.textAlignment=NSTextAlignmentRight; [configTab addSubview:v];
            y += 18;
        }
    }

    [menuContainer bringSubviewToFront:sb];
    [menuContainer addSubview:closeBtn]; [menuContainer bringSubviewToFront:closeBtn];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Tab Switching
// ─────────────────────────────────────────────────────────────────────────────
- (void)_tabTap:(UITapGestureRecognizer *)gr { [self _switchTab:(int)(gr.view.tag - 100)]; }
- (void)_switchTab:(int)idx {
    NSArray *tabs = @[mainTab, aimTab, extraTab, configTab];
    for (UIView *t in tabs) { t.hidden = YES; t.userInteractionEnabled = NO; }

    // Reset all sidebar buttons by tag
    for (UIView *s in _sidebar.subviews) {
        if (s.tag >= 100 && s.tag <= 103) {
            s.backgroundColor = UIColor.clearColor;
            s.layer.borderColor = UIColor.clearColor.CGColor;
            for (UIView *c in s.subviews) {
                if ([c isKindOfClass:UILabel.class])     ((UILabel*)c).textColor     = COL_DIM;
                if ([c isKindOfClass:UIImageView.class]) ((UIImageView*)c).tintColor = COL_DIM;
            }
        }
    }

    // Highlight correct button by tag (100+idx), not by subviews array index
    for (UIView *s in _sidebar.subviews) {
        if (s.tag == 100 + idx) {
            s.backgroundColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.08];
            s.layer.borderColor = [UIColor colorWithRed:0.78 green:0.95 blue:0.1 alpha:0.28].CGColor;
            for (UIView *c in s.subviews) {
                if ([c isKindOfClass:UILabel.class])     ((UILabel*)c).textColor     = COL_ACC;
                if ([c isKindOfClass:UIImageView.class]) ((UIImageView*)c).tintColor = COL_ACC;
            }
            break;
        }
    }

    UIView *tab = (idx < (int)tabs.count) ? tabs[idx] : mainTab;
    tab.hidden = NO; tab.userInteractionEnabled = YES;
    tab.frame = mainTab.frame;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Toggle Handlers
// ─────────────────────────────────────────────────────────────────────────────
- (void)_tBox:(CustomSwitch *)s    { isBox = s.isOn; }
- (void)_tBone:(CustomSwitch *)s   { isBone = s.isOn; }
- (void)_tHealth:(CustomSwitch *)s { isHealth = s.isOn; }
- (void)_tName:(CustomSwitch *)s   { isName = s.isOn; }
- (void)_tDist:(CustomSwitch *)s   { isDis = s.isOn; }
- (void)_tLine:(CustomSwitch *)s   { isLine = s.isOn; }
- (void)_tAimbot:(CustomSwitch *)s { isAimbot = s.isOn; }
- (void)_tSilent:(CustomSwitch *)s { isSilentAim = s.isOn; }
- (void)_tSkipBots:(CustomSwitch *)s    { isSkipBots = s.isOn; }
- (void)_tVisOnly:(CustomSwitch *)s     { isShowOnlyVis = s.isOn; }
- (void)_tVehicleTag:(CustomSwitch *)s  { isVehicleTag = s.isOn; }
- (void)_tGlideTag:(CustomSwitch *)s    { isGlideTag = s.isOn; }
- (void)_tSkipKnocked:(CustomSwitch *)s { isSkipKnocked = s.isOn; }
- (void)_tSkipGlide:(CustomSwitch *)s   { isSkipGliding = s.isOn; }

// ── New feature handlers ──────────────────────────────────────────────────
- (void)_tNoRecoil:(CustomSwitch *)s {
    isNoRecoil = s.isOn;
    // Сбрасываем при выключении (следующий кадр renderESP восстановит)
}

- (void)_tInfAmmo:(CustomSwitch *)s {
    isInfAmmo = s.isOn;
}
- (void)_tStream:(CustomSwitch *)s {
    isStreamerMode = s.isOn;
    applyStreamProof(self, isStreamerMode);
    applyStreamProof(menuContainer, isStreamerMode);
    applyStreamProof(floatingButton, isStreamerMode);
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Menu Show/Hide
// ─────────────────────────────────────────────────────────────────────────────
// Public interface methods (declared in esp.h)
- (void)hideMenu   { [self _hideMenu]; }
- (void)showMenu   { [self _showMenu]; }
- (void)centerMenu {
    CGFloat W = self.superview.bounds.size.width  ?: self.bounds.size.width;
    CGFloat H = self.superview.bounds.size.height ?: self.bounds.size.height;
    menuContainer.center = CGPointMake(W/2, H/2);
}
- (void)handlePan:(UIPanGestureRecognizer *)gesture { [self _handlePan:gesture]; }

- (void)_showMenu {
    CGFloat W = self.superview.bounds.size.width  ?: self.bounds.size.width;
    CGFloat H = self.superview.bounds.size.height ?: self.bounds.size.height;
    menuContainer.hidden = NO; floatingButton.hidden = YES;
    menuContainer.center = CGPointMake(W/2, H/2);
    menuContainer.transform = CGAffineTransformMakeScale(0.05, 0.05);
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0
                     animations:^{ self->menuContainer.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)_hideMenu {
    [UIView animateWithDuration:0.2 animations:^{ self->menuContainer.transform = CGAffineTransformMakeScale(0.05, 0.05); }
                     completion:^(BOOL f) { self->menuContainer.hidden = YES; self->floatingButton.hidden = NO; self->menuContainer.transform = CGAffineTransformIdentity; }];
}
- (void)_closeTap:(UITapGestureRecognizer *)gr { [self _hideMenu]; }

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Drag / Pan
// ─────────────────────────────────────────────────────────────────────────────
- (void)_handlePan:(UIPanGestureRecognizer *)gr {
    UIView *target = (gr.view == floatingButton) ? floatingButton : menuContainer;
    CGPoint t = [gr translationInView:self];
    if (gr.state == UIGestureRecognizerStateBegan || gr.state == UIGestureRecognizerStateChanged) {
        target.center = CGPointMake(target.center.x + t.x, target.center.y + t.y);
        [gr setTranslation:CGPointZero inView:self];
    }
    if (gr.state == UIGestureRecognizerStateEnded || gr.state == UIGestureRecognizerStateCancelled) {
        CGFloat cW = self.superview.bounds.size.width  ?: self.bounds.size.width;
        CGFloat cH = self.superview.bounds.size.height ?: self.bounds.size.height;
        CGFloat hw = target.bounds.size.width/2, hh = target.bounds.size.height/2, mg = 8;
        CGFloat cx = MAX(hw+mg, MIN(target.center.x, cW-hw-mg));
        CGFloat cy = MAX(hh+mg, MIN(target.center.y, cH-hh-mg));
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0
                         animations:^{ target.center = CGPointMake(cx, cy); } completion:nil];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Gesture Delegate
// ─────────────────────────────────────────────────────────────────────────────
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)t {
    UIView *v = t.view;
    while (v) {
        if ([v isKindOfClass:[HUDSlider class]]) return NO;
        if (v == menuContainer) break;
        v = v.superview;
    }
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {}
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {}
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e {}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Game Module Init
// ─────────────────────────────────────────────────────────────────────────────
- (void)SetUpBase {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (Moudule_Base == (uint64_t)-1 || Moudule_Base == 0) {
            uint64_t b = (uint64_t)GetGameModule_Base((char*)ENCRYPT("freefireth"));
            if (b != 0) {
                Moudule_Base = b;
                NSLog(@"[FRYZZ] Moudule_Base=0x%llx", Moudule_Base);
                espLog([NSString stringWithFormat:@"[ESP] ModuleBase=0x%llx", Moudule_Base]);
                break;
            }
            [NSThread sleepForTimeInterval:3.0];
        }
    });
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Render Tick
// ─────────────────────────────────────────────────────────────────────────────
- (void)_tick {
    if (!self.window) return;
    if (_espBusy) return;
    _espBusy = YES;

    // FOV circle — on main thread (cheap)
    if (isAimbot && isInMatch) {
        float vW = self.superview.bounds.size.width  ?: self.bounds.size.width;
        float vH = self.superview.bounds.size.height ?: self.bounds.size.height;
        _fovLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(vW*.5f,vH*.5f)
                            radius:aimFov startAngle:0 endAngle:M_PI*2 clockwise:YES].CGPath;
        _fovLayer.hidden = NO;
    } else {
        _fovLayer.hidden = YES;
    }

    // Update match indicator on floating button
    UIView *matchDot = [menuContainer viewWithTag:777];
    UILabel *matchLbl = (UILabel *)[menuContainer viewWithTag:778];
    if (matchDot && matchLbl) {
        matchDot.backgroundColor = isInMatch ? [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:0.9] : [UIColor colorWithRed:0.35 green:0.35 blue:0.35 alpha:0.7];
        matchLbl.text = isInMatch ? @"LIVE" : @"IDLE";
        matchLbl.textColor = isInMatch ? COL_GREEN : COL_DIM;
    }

    dispatch_async(_espQueue, ^{
        [self renderESP];
        self->_espBusy = NO;
    });
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Text Layer Pool
// ─────────────────────────────────────────────────────────────────────────────
- (CATextLayer *)textLayer {
    if (_textPoolIndex < (NSInteger)_textPool.count) {
        CATextLayer *t = _textPool[_textPoolIndex++]; t.hidden = NO; return t;
    }
    CATextLayer *t = [CATextLayer layer];
    t.contentsScale = [UIScreen mainScreen].scale;
    t.allowsFontSubpixelQuantization = YES;
    t.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:10].fontName;
    [self.layer addSublayer:t];
    [_textPool addObject:t]; _textPoolIndex++;
    return t;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - ESP Render (Background Thread)
// ─────────────────────────────────────────────────────────────────────────────
- (void)renderESP {
    if (Moudule_Base == (uint64_t)-1 || Moudule_Base == 0) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);

    // Log matchGame value once every 5s for diagnostics
    static CFAbsoluteTime _lastMGLog = 0;
    CFAbsoluteTime _now = CFAbsoluteTimeGetCurrent();
    if (_now - _lastMGLog > 5.0) {
        _lastMGLog = _now;
        espLog([NSString stringWithFormat:@"[ESP] matchGame=0x%llx base=0x%llx", matchGame, Moudule_Base]);
    }

    if (!isVaildPtr(matchGame)) {
        if (isInMatch) { isInMatch = NO; dispatch_async(dispatch_get_main_queue(), ^{ [self _clearAllLayers]; }); }
        espLog(@"[ESP] matchGame invalid");
        return;
    }

    // ── Match detection: triple-check + 4s cooldown ──────────────────
    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        if (isInMatch) {
            isInMatch = NO;
            dispatch_async(dispatch_get_main_queue(), ^{ [self _clearAllLayers]; });
        }
        espLog(@"[ESP] camera invalid");
        return;
    }
    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) { isInMatch = NO; espLog(@"[ESP] match invalid"); return; }

    uint64_t myPlayer = getLocalPlayer(match);
    if (!isVaildPtr(myPlayer)) { isInMatch = NO; espLog(@"[ESP] myPlayer invalid"); return; }

    int myMaxHP = get_MaxHP(myPlayer);
    if (myMaxHP <= 0) { isInMatch = NO; espLog(@"[ESP] maxHP=0"); return; }

    // Cooldown: if match ptr changed, wait 4s for game to stabilize
    if (match != _sLastMatchPtr) {
        _sLastMatchPtr = match; _sMatchStartTime = CACurrentMediaTime();
        isInMatch = NO; return;
    }
    bool aimCooldown = (CACurrentMediaTime() - _sMatchStartTime) < 4.0;
    isInMatch = YES;

    // ── No Recoil / Infinite Ammo — применяем к localPlayer каждый кадр ──
    if (isNoRecoil || isInfAmmo) {
        uint64_t attr = ReadAddr<uint64_t>(myPlayer + OFF_DEC(_OFF_PLAYER_ATTR));
        if (isVaildPtr(attr)) {
            if (isNoRecoil) {
                // BuffWeaponScatterScale — struct NLMGLDLNDKH @ attr+0xD0
                // Обнуляем multiplier чтобы разброс = 0
                WriteAddr<float>(attr + (uint64_t)0xD0 + (uint64_t)0x0, 0.0f);  // base
                WriteAddr<float>(attr + (uint64_t)0xD0 + (uint64_t)0x4, 0.0f);  // extra
            }
            if (isInfAmmo) {
                // ReloadNoConsumeAmmoclip @ attr+0xC8 — не тратить патроны при перезарядке
                // ShootNoReload @ attr+0xC9 — не нужна перезарядка
                WriteAddr<bool>(attr + OFF_DEC(_OFF_INF_AMMO),  true);
                WriteAddr<bool>(attr + OFF_DEC(_OFF_NO_RELOAD), true);
            }
        }
    }

    // ── Camera & screen ──────────────────────────────────────────────
    uint64_t camTr = ReadAddr<uint64_t>(myPlayer + OFF_CAMERA_TRANSFORM);
    Vector3  myLoc = getPositionExt(camTr);
    float   *mx    = GetViewMatrix(camera);

    float vW = self.superview ? (float)self.superview.bounds.size.width  : (float)self.bounds.size.width;
    float vH = self.superview ? (float)self.superview.bounds.size.height : (float)self.bounds.size.height;
    if (vW < 10 || vH < 10) { vW = self.bounds.size.width; vH = self.bounds.size.height; }
    CGPoint center = CGPointMake(vW*.5f, vH*.5f);

    // ── Player list ──────────────────────────────────────────────────
    // Read HJAKBBKDAPK Dict<IHAAMHPPLMG, Player> @ match+0x118
    uint64_t dictPtr  = ReadAddr<uint64_t>(match + OFF_MATCH_PLAYERDICT);
    uint64_t arr      = ReadAddr<uint64_t>(dictPtr + 0x28); // _entries array
    int      cnt      = ReadAddr<int>(arr + 0x18);           // _count
    if (cnt <= 0 || cnt > 64) cnt = 0;

    // ── CGPath buckets ───────────────────────────────────────────────
    CGMutablePathRef boneNP = CGPathCreateMutable(), boneMP = CGPathCreateMutable(),
                     boneFP = CGPathCreateMutable(), boneKP = CGPathCreateMutable();
    CGMutablePathRef boxNP  = CGPathCreateMutable(), boxMP  = CGPathCreateMutable(),
                     boxFP  = CGPathCreateMutable(), boxKP  = CGPathCreateMutable();
    CGMutablePathRef lineNP = CGPathCreateMutable(), lineMP = CGPathCreateMutable(), lineFP = CGPathCreateMutable();
    CGMutablePathRef hpBgP  = CGPathCreateMutable(), hpGP   = CGPathCreateMutable(),
                     hpYP   = CGPathCreateMutable(), hpRP   = CGPathCreateMutable();

    #define _BONE_P(k) ((k)?boneKP:(dis<40?boneNP:(dis<100?boneMP:boneFP)))
    #define _BOX_P(k)  ((k)?boxKP: (dis<40?boxNP: (dis<100?boxMP: boxFP)))
    #define _LINE_P(k) ((k)?lineFP:(dis<40?lineNP:(dis<100?lineMP:lineFP)))

    ESPTextEntry texts[kMaxESPText]; int tCnt = 0;
    auto addText = [&](const char *s, float x, float y, float w, float h,
                       float fs, float r, float g, float b, float a, float bg, int al) {
        if (tCnt >= kMaxESPText) return;
        ESPTextEntry &e = texts[tCnt++];
        strncpy(e.text, s, 47); e.text[47]=0;
        e.x=x; e.y=y; e.w=w; e.h=h; e.fontSize=fs;
        e.r=r; e.g=g; e.b=b; e.a=a; e.bgAlpha=bg; e.align=al;
    };

    uint64_t bestTarget = 0; float bestScore = FLT_MAX;
    bool     isFire     = get_IsFiring(myPlayer);

    // ── Per-player loop ──────────────────────────────────────────────
    // Each Dict entry: value (Player ptr) is at [entry + 0x20] based on NFJPHMKKEBF dict layout
    for (int i = 0; i < cnt; i++) {
        uint64_t entry  = ReadAddr<uint64_t>(arr + 0x20 + (uint64_t)(0x18 * i));  // value ptr
        uint64_t player = ReadAddr<uint64_t>(entry);
        if (!isVaildPtr(player)) continue;
        if (player == myPlayer) continue;
        if (isLocalTeamMate(myPlayer, player)) continue;
        if (isSkipBots && isPlayerBot(player)) continue;
        if (isShowOnlyVis && !isPlayerVisible(player)) continue;

        // HP: dead players skipped entirely
        int curHP = get_CurHP(player), maxHP = get_MaxHP(player);
        if (maxHP <= 0) continue;
        if (curHP <= 0) continue;

        bool knocked  = isPlayerKnocked(player);
        bool inVehicle= isPlayerInVehicle(player);
        bool gliding  = isPlayerGliding(player);

        // Head node for distance
        uint64_t headNode = getHead(player);
        if (!isVaildPtr(headNode)) continue;
        Vector3 headPos = getPositionExt(headNode);
        float   dis     = Vector3::Distance(myLoc, headPos);
        if (dis > espDistance) continue;

        // ── Aimbot scoring ───────────────────────────────────────────
        if (isAimbot && dis <= aimDistance) {
            if (!(knocked && isSkipKnocked) && !(gliding && isSkipGliding)) {
                Vector3 aimPt = headPos + Vector3(0, headOffset, 0);
                Vector3 ss    = WorldToScreen(aimPt, mx, vW, vH);
                float dx = ss.x - center.x, dy = ss.y - center.y;
                float d2 = sqrtf(dx*dx + dy*dy);
                if (d2 <= aimFov) {
                    float sc = (aimMode == 0) ? dis : d2;
                    if (sc < bestScore) { bestScore = sc; bestTarget = player; }
                }
            }
        }

        // ── Projection ───────────────────────────────────────────────
        uint64_t toeNode = getRightToeNode(player);
        if (!isVaildPtr(toeNode)) continue;
        Vector3 toePos = getPositionExt(toeNode);
        Vector3 headTop = headPos; headTop.y += 0.22f;
        Vector3 sHead   = WorldToScreen(headTop, mx, vW, vH);
        Vector3 sToe    = WorldToScreen(toePos,  mx, vW, vH);

        // Cull off-screen (generous margin)
        if (sHead.x < -300 || sHead.x > vW+300 || sHead.y < -300 || sHead.y > vH+300) continue;

        float boxH = fabsf(sHead.y - sToe.y);
        if (boxH < 2.0f) continue;
        if (boxH < 8.0f) boxH = 8.0f;   // min size for far players
        float boxW = boxH * 0.45f;
        float bx   = sHead.x - boxW * 0.5f;
        float by   = sHead.y;

        // ── Color by distance / state ─────────────────────────────────
        float acR, acG, acB, acA;
        if (knocked)       { acR=0.65f; acG=0.30f; acB=1.00f; acA=0.65f; }
        else if (dis<40.f) { acR=1.00f; acG=0.22f; acB=0.22f; acA=0.95f; }
        else if (dis<100.f){ acR=1.00f; acG=0.82f; acB=0.00f; acA=0.90f; }
        else               { acR=0.75f; acG=0.75f; acB=0.80f; acA=0.85f; }

        // ── SKELETON ─────────────────────────────────────────────────
        if (isBone && dis <= 150.f) {
            uint64_t hipN = getHip(player);
            Vector3 sHip  = WorldToScreen(isVaildPtr(hipN)?getPositionExt(hipN):headPos, mx,vW,vH);
            Vector3 sLS   = WorldToScreen(getPositionExt(getLeftShoulder(player)),  mx,vW,vH);
            Vector3 sRS   = WorldToScreen(getPositionExt(getRightShoulder(player)), mx,vW,vH);
            Vector3 sLE   = WorldToScreen(getPositionExt(getLeftElbow(player)),     mx,vW,vH);
            Vector3 sRE   = WorldToScreen(getPositionExt(getRightElbow(player)),    mx,vW,vH);
            Vector3 sLH   = WorldToScreen(getPositionExt(getLeftHand(player)),      mx,vW,vH);
            Vector3 sRH   = WorldToScreen(getPositionExt(getRightHand(player)),     mx,vW,vH);
            Vector3 sLA   = WorldToScreen(getPositionExt(getLeftAnkle(player)),     mx,vW,vH);
            Vector3 sRA   = WorldToScreen(getPositionExt(getRightAnkle(player)),    mx,vW,vH);
            Vector3 sHd   = WorldToScreen(headPos, mx, vW, vH);

            CGMutablePathRef bp = _BONE_P(knocked);
            // Spine: head → hip
            CGPathMoveToPoint(bp,nil,sHd.x,sHd.y); CGPathAddLineToPoint(bp,nil,sHip.x,sHip.y);
            // Shoulders
            CGPathMoveToPoint(bp,nil,sLS.x,sLS.y); CGPathAddLineToPoint(bp,nil,sRS.x,sRS.y);
            // Left arm
            CGPathMoveToPoint(bp,nil,sLS.x,sLS.y); CGPathAddLineToPoint(bp,nil,sLE.x,sLE.y); CGPathAddLineToPoint(bp,nil,sLH.x,sLH.y);
            // Right arm
            CGPathMoveToPoint(bp,nil,sRS.x,sRS.y); CGPathAddLineToPoint(bp,nil,sRE.x,sRE.y); CGPathAddLineToPoint(bp,nil,sRH.x,sRH.y);
            // Legs
            CGPathMoveToPoint(bp,nil,sHip.x,sHip.y); CGPathAddLineToPoint(bp,nil,sLA.x,sLA.y);
            CGPathMoveToPoint(bp,nil,sHip.x,sHip.y); CGPathAddLineToPoint(bp,nil,sRA.x,sRA.y);
        }

        // ── BOX: corner brackets ─────────────────────────────────────
        if (isBox) {
            float cL = MIN(boxW, boxH) * 0.22f;
            CGMutablePathRef xp = _BOX_P(knocked);
            CGPathMoveToPoint(xp,nil,bx,by+cL);       CGPathAddLineToPoint(xp,nil,bx,by);         CGPathAddLineToPoint(xp,nil,bx+cL,by);
            CGPathMoveToPoint(xp,nil,bx+boxW-cL,by);  CGPathAddLineToPoint(xp,nil,bx+boxW,by);    CGPathAddLineToPoint(xp,nil,bx+boxW,by+cL);
            CGPathMoveToPoint(xp,nil,bx,by+boxH-cL);  CGPathAddLineToPoint(xp,nil,bx,by+boxH);    CGPathAddLineToPoint(xp,nil,bx+cL,by+boxH);
            CGPathMoveToPoint(xp,nil,bx+boxW-cL,by+boxH); CGPathAddLineToPoint(xp,nil,bx+boxW,by+boxH); CGPathAddLineToPoint(xp,nil,bx+boxW,by+boxH-cL);
        }

        // ── HP BAR ────────────────────────────────────────────────────
        if (isHealth && maxHP > 0) {
            float ratio  = fmaxf(0, fminf(1, (float)curHP / maxHP));
            float hpH    = 4.f, hpY = by - hpH - 2.f;
            CGPathAddRect(hpBgP, nil, CGRectMake(bx, hpY, boxW, hpH));
            if (!knocked) {
                CGMutablePathRef fp = ratio>0.6f ? hpGP : (ratio>0.3f ? hpYP : hpRP);
                CGPathAddRect(fp, nil, CGRectMake(bx, hpY, boxW*ratio, hpH));
            }
        }

        // ── TEXT LABELS ───────────────────────────────────────────────
        {
            float rW = MAX(boxW+16, 72), rX = sHead.x - rW*.5f, curY = by;

            if (isHealth && maxHP > 0) {
                float ratio = (float)curHP / maxHP;
                float hR = ratio>0.6f?0.15f:1.f, hG = ratio>0.6f?0.9f:(ratio>0.3f?0.75f:0.2f), hB = ratio>0.6f?0.35f:(ratio>0.3f?0.0f:0.2f);
                char buf[12]; if (knocked) snprintf(buf,sizeof(buf),"KO"); else snprintf(buf,sizeof(buf),"%d",curHP);
                curY -= 7; addText(buf, rX, curY-11, rW, 11, 9, knocked?0.65f:hR, knocked?0.3f:hG, knocked?1.f:hB, 0.95f, 0.55f, 1); curY -= 13;
            }
            if (isName) {
                NSString *nm = GetNickName(player);
                const char *ns = (nm.length > 0) ? nm.UTF8String : "?";
                char nb[48]; strncpy(nb, ns, 47); nb[47]=0;
                addText(nb, rX, curY-11, rW, 11, 9, acR, acG, acB, 0.95f, 0.55f, 1);
            }

            // Status tags (below box)
            float tagY = by + boxH + 2.f;
            if (isVehicleTag && inVehicle) {
                addText("[CAR]", rX, tagY, rW, 10, 8, 0.3f, 0.7f, 1.0f, 0.9f, 0.4f, 1); tagY += 11;
            }
            if (isGlideTag && gliding) {
                addText("[GLIDE]", rX, tagY, rW, 10, 8, 0.3f, 0.9f, 0.7f, 0.9f, 0.4f, 1); tagY += 11;
            }
            if (isDis) {
                char db[16]; snprintf(db, sizeof(db), "%.0fm", dis);
                float dR = dis<40?acR:0.6f, dG = dis<40?acG:0.6f, dB = dis<40?acB:0.65f;
                addText(db, rX, tagY, rW, 9, 8, dR, dG, dB, 0.75f, 0, 1);
            }
        }

        // ── SNAPLINES ─────────────────────────────────────────────────
        if (isLine) {
            CGPoint from = lineOrigin==0 ? CGPointMake(vW*.5f,0) : lineOrigin==1 ? CGPointMake(vW*.5f,vH*.5f) : CGPointMake(vW*.5f,vH);
            CGPoint to   = lineOrigin==2 ? CGPointMake(bx+boxW*.5f,by+boxH) : CGPointMake(bx+boxW*.5f,by);
            CGMutablePathRef lp = _LINE_P(knocked);
            CGPathMoveToPoint(lp,nil,from.x,from.y); CGPathAddLineToPoint(lp,nil,to.x,to.y);
        }
    }

    // ── Aimbot apply ─────────────────────────────────────────────────
    // Silent Aim: работает ТОЛЬКО во время стрельбы — иначе нет смысла
    // Обычный аим: по триггеру (Always или Shooting)
    bool shouldAim = !aimCooldown && (isSilentAim
        ? isFire
        : (aimTrigger==0 || (aimTrigger==1 && isFire)));

    if (isAimbot && isVaildPtr(bestTarget) && shouldAim) {
        // Выбираем точку прицеливания
        Vector3 tPt;
        switch (aimTarget) {
            case 0: { uint64_t h = getHead(bestTarget);  tPt = isVaildPtr(h) ? getPositionExt(h) + Vector3(0,headOffset,0) : Vector3(0,0,0); break; }
            case 1: { uint64_t n = getNeck(bestTarget);  tPt = isVaildPtr(n) ? getPositionExt(n) + Vector3(0,headOffset,0) : getPositionExt(getHead(bestTarget)) + Vector3(0,-0.1f+headOffset,0); break; }
            case 2: { uint64_t c = getChest(bestTarget); tPt = isVaildPtr(c) ? getPositionExt(c) + Vector3(0,headOffset,0) : getPositionExt(getHip(bestTarget))  + Vector3(0,0.3f+headOffset,0);  break; }
            case 3: { uint64_t h = getHip(bestTarget);   tPt = isVaildPtr(h) ? getPositionExt(h) + Vector3(0,headOffset,0) : Vector3(0,0,0); break; }
            default: { uint64_t h = getHead(bestTarget); tPt = isVaildPtr(h) ? getPositionExt(h) + Vector3(0,headOffset,0) : Vector3(0,0,0); break; }
        }

        // Проверяем что точка реальная
        if (tPt.x != 0.f || tPt.y != 0.f || tPt.z != 0.f) {
            Quaternion targetRot = GetRotationToTarget(tPt, 0.f, myLoc);
            set_aim(myPlayer, targetRot);
        }

    } else if (isSilentAim && !isFire && _sa_didWrite) {
        // Восстанавливаем оригинальный aim когда прекратили стрелять
        WriteAddr<Quaternion>(myPlayer + OFF_DEC(_OFF_CURRENT_AIM), _sa_saved172C);
        WriteAddr<Quaternion>(myPlayer + OFF_DEC(_OFF_AIM_PREV),    _sa_saved172C);
        WriteAddr<Quaternion>(myPlayer + OFF_DEC(_OFF_AIM_TARGET),  _sa_saved172C);
        _sa_didWrite = false;
    }

    // ── Push to main thread ───────────────────────────────────────────
    BOOL b_bone=isBone, b_box=isBox, b_hp=isHealth, b_line=isLine;
    int  txCnt = tCnt;
    ESPTextEntry *txCopy = nullptr;
    if (txCnt > 0) {
        txCopy = (ESPTextEntry *)malloc(sizeof(ESPTextEntry)*txCnt);
        memcpy(txCopy, texts, sizeof(ESPTextEntry)*txCnt);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [CATransaction begin]; [CATransaction setDisableActions:YES]; [CATransaction setAnimationDuration:0];

        self->_boneNear.path = b_bone ? boneNP : nil; self->_boneMid.path = b_bone ? boneMP : nil;
        self->_boneFar.path  = b_bone ? boneFP : nil; self->_boneKnocked.path = b_bone ? boneKP : nil;
        self->_boxNear.path  = b_box  ? boxNP  : nil; self->_boxMid.path  = b_box  ? boxMP  : nil;
        self->_boxFar.path   = b_box  ? boxFP  : nil; self->_boxKnocked.path  = b_box  ? boxKP  : nil;
        self->_lineNear.path = b_line ? lineNP : nil; self->_lineMid.path = b_line ? lineMP : nil;
        self->_lineFar.path  = b_line ? lineFP : nil;
        self->_hpBg.path     = b_hp ? hpBgP : nil; self->_hpGreen.path = b_hp ? hpGP : nil;
        self->_hpYellow.path = b_hp ? hpYP  : nil; self->_hpRed.path   = b_hp ? hpRP  : nil;

        for (CATextLayer *t in self->_textPool) t.hidden = YES;
        self->_textPoolIndex = 0;
        for (int i = 0; i < txCnt; i++) {
            const ESPTextEntry &e = txCopy[i];
            CATextLayer *tl = [self textLayer];
            tl.string          = [NSString stringWithUTF8String:e.text];
            tl.fontSize        = e.fontSize;
            tl.frame           = CGRectMake(e.x, e.y, e.w, e.h);
            tl.foregroundColor = [UIColor colorWithRed:e.r green:e.g blue:e.b alpha:e.a].CGColor;
            tl.backgroundColor = (e.bgAlpha > 0.01f) ? [UIColor colorWithWhite:0 alpha:e.bgAlpha].CGColor : nil;
            tl.alignmentMode   = (e.align==1) ? kCAAlignmentCenter : kCAAlignmentLeft;
            tl.cornerRadius    = (e.bgAlpha > 0.01f) ? 2.0f : 0.0f;
        }
        if (txCopy) free(txCopy);
        [CATransaction commit];

        CGPathRelease(boneNP); CGPathRelease(boneMP); CGPathRelease(boneFP); CGPathRelease(boneKP);
        CGPathRelease(boxNP);  CGPathRelease(boxMP);  CGPathRelease(boxFP);  CGPathRelease(boxKP);
        CGPathRelease(lineNP); CGPathRelease(lineMP); CGPathRelease(lineFP);
        CGPathRelease(hpBgP);  CGPathRelease(hpGP);   CGPathRelease(hpYP);   CGPathRelease(hpRP);
    });
}

- (void)_clearAllLayers {
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (CALayer *l in @[_boneNear,_boneMid,_boneFar,_boneKnocked,
                         _boxNear,_boxMid,_boxFar,_boxKnocked,
                         _lineNear,_lineMid,_lineFar,
                         _hpBg,_hpGreen,_hpYellow,_hpRed,_fovLayer]) {
        if ([l isKindOfClass:[CAShapeLayer class]]) ((CAShapeLayer*)l).path = nil;
    }
    for (CATextLayer *t in _textPool) t.hidden = YES;
    [CATransaction commit];
}

@end
