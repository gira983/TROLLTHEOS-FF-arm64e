#import "esp.h"
#import "mahoa.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

uint64_t Moudule_Base = -1;

static bool isBox      = YES;
static bool isBone     = YES;
static bool isHealth   = YES;
static bool isName     = YES;
static bool isDis      = YES;
static bool isAimbot   = NO;
static float aimFov      = 150.0f;
static float aimDistance = 200.0f;

// ─────────────────────────────────────────────
// MARK: - NeonSwitch (CustomSwitch, точно работает)
// ─────────────────────────────────────────────
@interface NeonSwitch : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@end
@implementation NeonSwitch { UIView *_thumb; BOOL _on; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, frame.size.height-4, frame.size.height-4)];
        _thumb.layer.cornerRadius = (frame.size.height-4)/2;
        _thumb.backgroundColor = [UIColor whiteColor];
        _thumb.layer.shadowColor = [UIColor whiteColor].CGColor;
        _thumb.layer.shadowOffset = CGSizeZero;
        _thumb.layer.shadowRadius = 4;
        _thumb.layer.shadowOpacity = 0;
        [self addSubview:_thumb];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_toggle)];
        [self addGestureRecognizer:tap];
        [self setNeedsDisplay];
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.bounds.size.height/2];
    if (_on) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat c[] = {0.0, 0.85, 0.45, 1.0, 0.0, 0.6, 0.3, 1.0};
        CGGradientRef gr = CGGradientCreateWithColorComponents(cs, c, NULL, 2);
        CGContextSaveGState(ctx);
        [bg addClip];
        CGContextDrawLinearGradient(ctx, gr, CGPointMake(0,0), CGPointMake(self.bounds.size.width,0), 0);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gr);
        CGColorSpaceRelease(cs);
    } else {
        [[UIColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:1] setFill];
        [bg fill];
    }
}
- (void)setOn:(BOOL)on {
    if (_on == on) return;
    _on = on;
    [self setNeedsDisplay];
    [self _animateThumb];
}
- (BOOL)isOn { return _on; }
- (void)_toggle {
    self.on = !_on;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)_animateThumb {
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        CGFloat r = self.bounds.size.height - 4;
        self->_thumb.frame = CGRectMake(self->_on ? self.bounds.size.width - r - 2 : 2, 2, r, r);
        self->_thumb.backgroundColor = UIColor.whiteColor;
        self->_thumb.layer.shadowOpacity = self->_on ? 0.8f : 0.0f;
    } completion:nil];
}
@end

// ─────────────────────────────────────────────
// MARK: - MenuBox с рекурсивным hitTest
// ─────────────────────────────────────────────
@interface MenuBox : UIView
@end
@implementation MenuBox
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    if (![self pointInside:point withEvent:event]) return nil;
    UIView *deep = [self _deepFind:point inView:self event:event];
    return deep ?: self;
}
- (UIView *)_deepFind:(CGPoint)pt inView:(UIView *)v event:(UIEvent *)e {
    for (UIView *s in v.subviews.reverseObjectEnumerator) {
        if (s.hidden || !s.userInteractionEnabled || s.alpha < 0.01) continue;
        CGPoint p = [v convertPoint:pt toView:s];
        if (![s pointInside:p withEvent:e]) continue;
        UIView *d = [self _deepFind:p inView:s event:e];
        if (d) return d;
        if ([s isKindOfClass:[UIControl class]] || s.gestureRecognizers.count > 0) return s;
    }
    return nil;
}
@end

// ─────────────────────────────────────────────
// MARK: - MenuView
// ─────────────────────────────────────────────
@interface MenuView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers;
@end

@implementation MenuView {
    // Float button
    UIButton  *_btnFloat;
    CGPoint    _dragStart;
    CGPoint    _btnCenterAtDrag;
    BOOL       _dragging;

    // Menu
    MenuBox   *_menuBox;
    UIView    *_tabMain, *_tabAim, *_tabSetting;
    UIButton  *_btnTabMain, *_btnTabAim, *_btnTabSetting;

    // Accent color
    UIColor   *_accent;
}

// ─── init ───────────────────────────────────
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _accent = [UIColor colorWithRed:0.0 green:0.85 blue:0.45 alpha:1.0];
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.drawingLayers = [NSMutableArray array];
        [self SetUpBase];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [self _buildButton];
        [self _buildMenu];
    }
    return self;
}

// ─── hitTest ────────────────────────────────
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden) return nil;
    if (_menuBox && !_menuBox.hidden) {
        CGPoint p = [self convertPoint:point toView:_menuBox];
        UIView *h = [_menuBox hitTest:p withEvent:event];
        if (h) return h;
    }
    if (_btnFloat && !_btnFloat.hidden) {
        CGPoint p = [self convertPoint:point toView:_btnFloat];
        if ([_btnFloat pointInside:p withEvent:event]) return _btnFloat;
    }
    return nil;
}

// ─── FLOAT BUTTON ───────────────────────────
- (void)_buildButton {
    _btnFloat = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnFloat.frame = CGRectMake(20, 130, 56, 56);
    _btnFloat.backgroundColor = _accent;
    _btnFloat.layer.cornerRadius = 28;
    _btnFloat.layer.borderWidth = 1.5;
    _btnFloat.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    // glow
    _btnFloat.layer.shadowColor = _accent.CGColor;
    _btnFloat.layer.shadowOffset = CGSizeZero;
    _btnFloat.layer.shadowRadius = 10;
    _btnFloat.layer.shadowOpacity = 0.7;
    _btnFloat.clipsToBounds = NO;
    [_btnFloat setTitle:@"M" forState:UIControlStateNormal];
    [_btnFloat setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnFloat.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [_btnFloat addTarget:self action:@selector(_floatTap) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_floatPan:)];
    pan.cancelsTouchesInView = NO;
    [_btnFloat addGestureRecognizer:pan];
    [self addSubview:_btnFloat];
    // pulse animation
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    pulse.fromValue = @8; pulse.toValue = @16;
    pulse.duration = 1.4; pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_btnFloat.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)_floatTap { [self _showMenu]; }

- (void)_floatPan:(UIPanGestureRecognizer *)gr {
    CGPoint loc = [gr locationInView:self];
    if (gr.state == UIGestureRecognizerStateBegan) {
        _dragStart = loc; _btnCenterAtDrag = _btnFloat.center; _dragging = NO;
    } else if (gr.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = loc.x - _dragStart.x, dy = loc.y - _dragStart.y;
        if (!_dragging && sqrtf(dx*dx+dy*dy) < 6) return;
        _dragging = YES;
        CGFloat r = 28; CGRect b = self.bounds;
        _btnFloat.center = CGPointMake(MAX(r, MIN(b.size.width-r, _btnCenterAtDrag.x+dx)),
                                        MAX(r, MIN(b.size.height-r,_btnCenterAtDrag.y+dy)));
    } else { _dragging = NO; }
}

// ─── MENU ────────────────────────────────────
- (void)_buildMenu {
    CGRect sc = [UIScreen mainScreen].bounds;
    CGFloat W = MIN(sc.size.width - 24, 360);
    CGFloat H = MIN(sc.size.height * 0.62, 320);
    CGFloat X = (sc.size.width - W) / 2;
    CGFloat Y = (sc.size.height - H) / 2;

    _menuBox = [[MenuBox alloc] initWithFrame:CGRectMake(X, Y, W, H)];
    _menuBox.hidden = YES;
    _menuBox.layer.cornerRadius = 16;
    // glass background
    _menuBox.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.1 alpha:0.96];
    _menuBox.layer.borderWidth = 1;
    _menuBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    _menuBox.layer.shadowColor = [UIColor blackColor].CGColor;
    _menuBox.layer.shadowOffset = CGSizeMake(0,8);
    _menuBox.layer.shadowRadius = 24;
    _menuBox.layer.shadowOpacity = 0.6;
    _menuBox.clipsToBounds = NO;
    [self addSubview:_menuBox];

    // Drag header
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 44)];
    hdr.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
    hdr.layer.cornerRadius = 16;
    hdr.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [_menuBox addSubview:hdr];
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_menuDrag:)];
    [hdr addGestureRecognizer:drag];

    // Title
    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, W-60, 44)];
    ttl.text = @"✦ XYRIS";
    ttl.textColor = _accent;
    ttl.font = [UIFont boldSystemFontOfSize:17];
    [hdr addSubview:ttl];

    // Subtitle
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, W-60, 44)];
    sub.text = @"  ESP & AIM";
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.3];
    sub.font = [UIFont systemFontOfSize:10];
    sub.textAlignment = NSTextAlignmentRight;
    sub.frame = CGRectMake(0, 0, W-50, 44);
    [hdr addSubview:sub];

    // Close btn
    UIButton *cls = [UIButton buttonWithType:UIButtonTypeCustom];
    cls.frame = CGRectMake(W-38, 8, 28, 28);
    cls.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:0.85];
    cls.layer.cornerRadius = 14;
    [cls setTitle:@"✕" forState:UIControlStateNormal];
    [cls setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cls.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [cls addTarget:self action:@selector(_hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:cls];

    // Separator
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 44, W, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    [_menuBox addSubview:sep];

    // Tab bar
    UIView *tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 45, W, 38)];
    tabBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];
    [_menuBox addSubview:tabBar];

    CGFloat tw = W / 3;
    _btnTabMain    = [self _tabBtn:@"ESP"      frame:CGRectMake(0,    0, tw, 38) active:YES  tag:0];
    _btnTabAim     = [self _tabBtn:@"AIM"      frame:CGRectMake(tw,   0, tw, 38) active:NO   tag:1];
    _btnTabSetting = [self _tabBtn:@"Settings" frame:CGRectMake(tw*2, 0, tw, 38) active:NO   tag:2];
    [tabBar addSubview:_btnTabMain];
    [tabBar addSubview:_btnTabAim];
    [tabBar addSubview:_btnTabSetting];

    // Tab indicator line
    UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(4, 35, tw-8, 2)];
    ind.backgroundColor = _accent;
    ind.layer.cornerRadius = 1;
    ind.tag = 777;
    [tabBar addSubview:ind];

    // Content
    CGFloat cy = 83, ch = H - cy;
    _tabMain    = [[UIView alloc] initWithFrame:CGRectMake(0, cy, W, ch)];
    _tabAim     = [[UIView alloc] initWithFrame:CGRectMake(0, cy, W, ch)];
    _tabSetting = [[UIView alloc] initWithFrame:CGRectMake(0, cy, W, ch)];
    _tabAim.hidden = YES; _tabSetting.hidden = YES;
    for (UIView *v in @[_tabMain, _tabAim, _tabSetting]) {
        v.backgroundColor = [UIColor clearColor];
        v.userInteractionEnabled = YES;
        v.clipsToBounds = NO;
        [_menuBox addSubview:v];
    }

    [self _buildESPTab:ch W:W];
    [self _buildAIMTab:ch W:W];
    [self _buildSettingsTab:ch W:W];
}

- (UIButton *)_tabBtn:(NSString *)title frame:(CGRect)f active:(BOOL)a tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = f; btn.tag = tag;
    btn.backgroundColor = [UIColor clearColor];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:(a ? _accent : [UIColor colorWithWhite:1 alpha:0.4]) forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [btn addTarget:self action:@selector(_tabTap:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)_tabTap:(UIButton *)btn {
    _tabMain.hidden = YES; _tabAim.hidden = YES; _tabSetting.hidden = YES;
    for (UIButton *b in @[_btnTabMain, _btnTabAim, _btnTabSetting])
        [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.4] forState:UIControlStateNormal];
    [btn setTitleColor:_accent forState:UIControlStateNormal];
    if (btn.tag == 0) _tabMain.hidden    = NO;
    if (btn.tag == 1) _tabAim.hidden     = NO;
    if (btn.tag == 2) _tabSetting.hidden = NO;
    // Move indicator
    UIView *tabBar = btn.superview;
    UIView *ind = [tabBar viewWithTag:777];
    CGFloat tw = btn.bounds.size.width;
    [UIView animateWithDuration:0.2 animations:^{
        ind.frame = CGRectMake(btn.frame.origin.x + 4, 35, tw - 8, 2);
    }];
}

// ─── ESP TAB ─────────────────────────────────
- (void)_buildESPTab:(CGFloat)H W:(CGFloat)W {
    CGFloat rowH = 36, y = 8;
    y = [self _row:_tabMain title:@"Box ESP"    icon:@"⬜" y:y on:isBox    sel:@selector(_togBox:)    W:W h:rowH];
    y = [self _row:_tabMain title:@"Skeleton"   icon:@"🦴" y:y on:isBone   sel:@selector(_togBone:)   W:W h:rowH];
    y = [self _row:_tabMain title:@"Health Bar" icon:@"❤" y:y on:isHealth sel:@selector(_togHP:)     W:W h:rowH];
    y = [self _row:_tabMain title:@"Name Tag"   icon:@"🏷" y:y on:isName   sel:@selector(_togName:)  W:W h:rowH];
    y = [self _row:_tabMain title:@"Distance"   icon:@"📏" y:y on:isDis    sel:@selector(_togDis:)   W:W h:rowH];

    UIView *sliderRow = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 38)];
    sliderRow.backgroundColor = [UIColor colorWithWhite:1 alpha:0.03];
    sliderRow.layer.cornerRadius = 8;
    [_tabMain addSubview:sliderRow];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 60, 38)];
    lbl.text = @"Size"; lbl.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    lbl.font = [UIFont systemFontOfSize:12]; [sliderRow addSubview:lbl];

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(60, 7, W-76, 24)];
    sl.minimumValue = 0.5; sl.maximumValue = 1.5; sl.value = 1.0;
    sl.minimumTrackTintColor = _accent;
    sl.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
    sl.thumbTintColor = [UIColor whiteColor];
    [sl addTarget:self action:@selector(_sizeChanged:) forControlEvents:UIControlEventValueChanged];
    [sliderRow addSubview:sl];
}

// ─── AIM TAB ─────────────────────────────────
- (void)_buildAIMTab:(CGFloat)H W:(CGFloat)W {
    CGFloat y = 8;
    y = [self _row:_tabAim title:@"Aimbot" icon:@"🎯" y:y on:isAimbot sel:@selector(_togAim:) W:W h:38];

    // FOV
    [self _sliderSection:_tabAim title:@"FOV Radius" y:y+4 W:W
              minVal:10 maxVal:400 val:aimFov color:[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]
              sel:@selector(_fovChanged:)];
    y += 68;
    // Distance
    [self _sliderSection:_tabAim title:@"Aim Distance (m)" y:y+4 W:W
              minVal:10 maxVal:500 val:aimDistance color:[UIColor colorWithRed:0.3 green:0.6 blue:1 alpha:1]
              sel:@selector(_distChanged:)];
}

- (void)_sliderSection:(UIView *)parent title:(NSString *)t y:(CGFloat)y W:(CGFloat)W
               minVal:(float)mn maxVal:(float)mx val:(float)v color:(UIColor *)c sel:(SEL)sel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y, W-28, 18)];
    l.text = t; l.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    l.font = [UIFont systemFontOfSize:11]; [parent addSubview:l];
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(12, y+20, W-24, 28)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = v;
    s.minimumTrackTintColor = c;
    s.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.12];
    s.thumbTintColor = [UIColor whiteColor];
    [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [parent addSubview:s];
}

// ─── SETTINGS TAB ────────────────────────────
- (void)_buildSettingsTab:(CGFloat)H W:(CGFloat)W {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 20, W-32, 40)];
    l.text = @"More settings coming soon…";
    l.textColor = [UIColor colorWithWhite:1 alpha:0.25];
    l.font = [UIFont italicSystemFontOfSize:13];
    [_tabSetting addSubview:l];
}

// ─── Row helper ──────────────────────────────
- (CGFloat)_row:(UIView *)p title:(NSString *)t icon:(NSString *)icon
              y:(CGFloat)y on:(BOOL)on sel:(SEL)sel W:(CGFloat)W h:(CGFloat)h {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, y, W-16, h)];
    row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.03];
    row.layer.cornerRadius = 8;
    row.userInteractionEnabled = YES;
    [p addSubview:row];

    UILabel *ic = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 28, h)];
    ic.text = icon; ic.font = [UIFont systemFontOfSize:14];
    ic.textAlignment = NSTextAlignmentCenter;
    [row addSubview:ic];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(38, 0, W-110, h)];
    lbl.text = t; lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:14];
    [row addSubview:lbl];

    NeonSwitch *sw = [[NeonSwitch alloc] initWithFrame:CGRectMake(W-16-58, (h-26)/2, 52, 26)];
    sw.on = on;
    sw.userInteractionEnabled = YES;
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    return y + h + 4;
}

// ─── Show / Hide / Drag ──────────────────────
- (void)_showMenu {
    _menuBox.hidden = NO;
    _btnFloat.hidden = YES;
    _menuBox.transform = CGAffineTransformMakeScale(0.85, 0.85);
    _menuBox.alpha = 0;
    [UIView animateWithDuration:0.28 delay:0
         usingSpringWithDamping:0.75 initialSpringVelocity:0.3
                        options:0 animations:^{
        self->_menuBox.transform = CGAffineTransformIdentity;
        self->_menuBox.alpha = 1;
    } completion:nil];
}

- (void)_hideMenu {
    [UIView animateWithDuration:0.2 animations:^{
        self->_menuBox.transform = CGAffineTransformMakeScale(0.9, 0.9);
        self->_menuBox.alpha = 0;
    } completion:^(BOOL done){
        self->_menuBox.hidden = YES;
        self->_menuBox.transform = CGAffineTransformIdentity;
        self->_btnFloat.hidden = NO;
    }];
}

- (void)_menuDrag:(UIPanGestureRecognizer *)gr {
    CGPoint d = [gr translationInView:self];
    CGRect b = self.bounds;
    CGPoint c = _menuBox.center;
    c.x = MAX(_menuBox.bounds.size.width/2, MIN(b.size.width  - _menuBox.bounds.size.width/2,  c.x + d.x));
    c.y = MAX(_menuBox.bounds.size.height/2,MIN(b.size.height - _menuBox.bounds.size.height/2, c.y + d.y));
    _menuBox.center = c;
    [gr setTranslation:CGPointZero inView:self];
}

// ─── Toggles ─────────────────────────────────
- (void)_togBox:(NeonSwitch *)s  { isBox    = s.isOn; }
- (void)_togBone:(NeonSwitch *)s { isBone   = s.isOn; }
- (void)_togHP:(NeonSwitch *)s   { isHealth = s.isOn; }
- (void)_togName:(NeonSwitch *)s { isName   = s.isOn; }
- (void)_togDis:(NeonSwitch *)s  { isDis    = s.isOn; }
- (void)_togAim:(NeonSwitch *)s  { isAimbot = s.isOn; }
- (void)_sizeChanged:(UISlider *)s   { }
- (void)_fovChanged:(UISlider *)s    { aimFov      = s.value; }
- (void)_distChanged:(UISlider *)s   { aimDistance = s.value; }

// ─── Layout ──────────────────────────────────
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) self.frame = self.superview.bounds;
    if (_btnFloat) {
        CGRect b = self.bounds; CGPoint c = _btnFloat.center; CGFloat r = 28;
        c.x = MAX(r, MIN(b.size.width-r,  c.x));
        c.y = MAX(r, MIN(b.size.height-r, c.y));
        _btnFloat.center = c;
    }
}

// ─── ESP render ──────────────────────────────
- (void)SetUpBase {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth"); });
}

- (void)updateFrame {
    if (!self.window) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (CALayer *l in self.drawingLayers) [l removeFromSuperlayer];
    [self.drawingLayers removeAllObjects];
    if (isAimbot) {
        float cx = self.bounds.size.width/2, cy2 = self.bounds.size.height/2;
        CAShapeLayer *c = [CAShapeLayer layer];
        c.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx,cy2) radius:aimFov startAngle:0 endAngle:2*M_PI clockwise:YES].CGPath;
        c.fillColor = [UIColor clearColor].CGColor;
        c.strokeColor = [UIColor colorWithRed:0 green:0.85 blue:0.45 alpha:0.5].CGColor;
        c.lineWidth = 1.5;
        [self.drawingLayers addObject:c];
    }
    [self renderESPToLayers:self.drawingLayers];
    for (CALayer *l in self.drawingLayers) [self.layer addSublayer:l];
    [CATransaction commit];
}

- (void)dealloc { [self.displayLink invalidate]; self.displayLink = nil; }

static inline void _BL(NSMutableArray<CALayer*>*L,CGPoint a,CGPoint b,UIColor*c,CGFloat w){
    CGFloat dx=b.x-a.x,dy=b.y-a.y,len=sqrtf(dx*dx+dy*dy);
    if(len<2)return;
    CALayer*l=[CALayer layer];l.backgroundColor=c.CGColor;
    l.bounds=CGRectMake(0,0,len,w);l.position=a;l.anchorPoint=CGPointMake(0,0.5);
    l.transform=CATransform3DMakeRotation(atan2f(dy,dx),0,0,1);[L addObject:l];
}
Quaternion _GRL(Vector3 t,float b,Vector3 m){return Quaternion::LookRotation((t+Vector3(0,b,0))-m,Vector3(0,1,0));}
void _SA(uint64_t p,Quaternion r){if(!isVaildPtr(p))return;WriteAddr<Quaternion>(p+0x53C,r);}
bool _GF(uint64_t p){if(!isVaildPtr(p))return false;return ReadAddr<bool>(p+0x750);}

- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers {
    if(Moudule_Base==(uint64_t)-1)return;
    uint64_t mg=getMatchGame(Moudule_Base),cam=CameraMain(mg);
    if(!isVaildPtr(cam))return;
    uint64_t match=getMatch(mg); if(!isVaildPtr(match))return;
    uint64_t me=getLocalPlayer(match); if(!isVaildPtr(me))return;
    Vector3 myL=getPositionExt(ReadAddr<uint64_t>(me+0x318));
    uint64_t pl=ReadAddr<uint64_t>(match+0x120),tv=ReadAddr<uint64_t>(pl+0x28);
    int cnt=ReadAddr<int>(tv+0x18);
    float*mx=GetViewMatrix(cam),vW=self.bounds.size.width,vH=self.bounds.size.height;
    CGPoint sc=CGPointMake(vW/2,vH/2);
    uint64_t best=0; int minHP=99999; bool fire=false;
    for(int i=0;i<cnt;i++){
        uint64_t P=ReadAddr<uint64_t>(tv+0x20+8*i);
        if(!isVaildPtr(P)||isLocalTeamMate(me,P))continue;
        int hp=get_CurHP(P); if(hp<=0)continue;
        Vector3 hd=getPositionExt(getHead(P));
        fire=_GF(me);
        float dis=Vector3::Distance(myL,hd); if(dis>400)continue;
        if(isAimbot&&dis<=aimDistance){
            Vector3 s=WorldToScreen(hd,mx,vW,vH);float dx=s.x-sc.x,dy=s.y-sc.y;
            if(sqrtf(dx*dx+dy*dy)<=aimFov&&hp<minHP){minHP=hp;best=P;}
        }
        if(dis>220)continue;
        Vector3 toe=getPositionExt(getRightToeNode(P));
        Vector3 sh=WorldToScreen(hd,mx,vW,vH),st=WorldToScreen(toe,mx,vW,vH);
        float bH=fabsf(sh.y-st.y),bW=bH*0.5f,bx=sh.x-bW/2,by=sh.y;
        if(isBox){CALayer*l=[CALayer layer];l.frame=CGRectMake(bx,by,bW,bH);
            l.borderColor=[UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.85].CGColor;
            l.borderWidth=1.2;l.cornerRadius=3;[layers addObject:l];}
        if(isName){NSString*n=GetNickName(P);if(n.length){
            CATextLayer*t=[CATextLayer layer];t.string=n;t.fontSize=10;
            t.frame=CGRectMake(bx-20,by-15,bW+40,14);t.alignmentMode=kCAAlignmentCenter;
            t.foregroundColor=_accent.CGColor;[layers addObject:t];}}
        if(isHealth){int mhp=get_MaxHP(P);if(mhp>0){
            float r=MAX(0,MIN(1,(float)hp/mhp)),brh=bH,fh=brh*r;
            CALayer*bg=[CALayer layer];bg.frame=CGRectMake(bx-6,by,3,brh);
            bg.backgroundColor=[UIColor colorWithWhite:0 alpha:0.5].CGColor;[layers addObject:bg];
            CALayer*fg=[CALayer layer];fg.frame=CGRectMake(bx-6,by+brh-fh,3,fh);
            UIColor*hc=r>0.5f?[UIColor colorWithRed:0.2 green:0.9 blue:0.3 alpha:1]:[UIColor colorWithRed:0.9 green:0.3 blue:0.2 alpha:1];
            fg.backgroundColor=hc.CGColor;[layers addObject:fg];}}
        if(isDis){CATextLayer*t=[CATextLayer layer];
            t.string=[NSString stringWithFormat:@"%.0fm",dis];t.fontSize=9;
            t.frame=CGRectMake(bx-10,by+bH+2,bW+20,12);t.alignmentMode=kCAAlignmentCenter;
            t.foregroundColor=[UIColor colorWithWhite:1 alpha:0.7].CGColor;[layers addObject:t];}
        if(isBone){
            Vector3 hip=getPositionExt(getHip(P));
            #define _W(v) WorldToScreen(v,mx,vW,vH)
            #define _C(v) CGPointMake(_W(v).x,_W(v).y)
            UIColor*bc=[UIColor colorWithWhite:1 alpha:0.7];
            _BL(layers,_C(hd),_C(hip),bc,1);
            Vector3 ls=getPositionExt(getLeftShoulder(P)),rs=getPositionExt(getRightShoulder(P));
            Vector3 le=getPositionExt(getLeftElbow(P)),re=getPositionExt(getRightElbow(P));
            Vector3 lh=getPositionExt(getLeftHand(P)),rh=getPositionExt(getRightHand(P));
            Vector3 la=getPositionExt(getLeftAnkle(P)),ra=getPositionExt(getRightAnkle(P));
            _BL(layers,_C(ls),_C(rs),bc,1);
            _BL(layers,_C(ls),_C(le),bc,1);_BL(layers,_C(le),_C(lh),bc,1);
            _BL(layers,_C(rs),_C(re),bc,1);_BL(layers,_C(re),_C(rh),bc,1);
            _BL(layers,_C(hip),_C(la),bc,1);_BL(layers,_C(hip),_C(ra),bc,1);
            #undef _W
            #undef _C
        }
    }
    if(isAimbot&&isVaildPtr(best)&&fire)
        _SA(me,_GRL(getPositionExt(getHead(best)),0.1f,myL));
}
@end
