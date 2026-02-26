#import "esp.h"
#import "mahoa.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

uint64_t Moudule_Base = -1;

static bool isBox = YES;
static bool isBone = YES;
static bool isHealth = YES;
static bool isName = YES;
static bool isDis = YES;
static bool isAimbot = NO;
static float aimFov = 150.0f;
static float aimDistance = 200.0f;

// ============================================================
// CustomSwitch
// ============================================================
@interface CustomSwitch : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@end

@implementation CustomSwitch { UIView *_thumb; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 22, 22)];
        _thumb.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _thumb.layer.cornerRadius = 11;
        [self addSubview:_thumb];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.bounds.size.height/2];
    CGContextSetFillColorWithColor(ctx, (self.isOn ? [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor colorWithWhite:0.25 alpha:1.0]).CGColor);
    [path fill];
}
- (void)setOn:(BOOL)on {
    if (_on != on) { _on = on; [self setNeedsDisplay]; [self updateThumb]; }
}
- (void)toggle { self.on = !self.on; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)updateThumb {
    [UIView animateWithDuration:0.2 animations:^{
        CGRect f = self->_thumb.frame;
        f.origin.x = self.isOn ? self.bounds.size.width - f.size.width - 2 : 2;
        self->_thumb.frame = f;
        self->_thumb.backgroundColor = self.isOn ? [UIColor whiteColor] : [UIColor colorWithWhite:0.75 alpha:1.0];
    }];
}
@end

// ============================================================
// MenuView
// ============================================================
@interface MenuView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers;
@end

@implementation MenuView {
    // Floating button
    UIButton *_btnFloat;
    CGPoint   _floatCenter;
    BOOL      _dragging;
    CGPoint   _dragStart;
    CGPoint   _btnCenterStart;

    // Menu window (separate UIWindow so it always gets touches)
    UIWindow *_menuWindow;
    UIViewController *_menuVC;

    // Tab containers
    UIView *_tabMain;
    UIView *_tabAim;
    UIView *_tabSetting;
    UIButton *_btnMain, *_btnAim, *_btnSetting;

    // Preview labels
    UILabel *_pvName, *_pvDist;
    UIView  *_pvHealth, *_pvBox, *_pvBone;
}

// ============================================================
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.drawingLayers = [NSMutableArray array];
        [self SetUpBase];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [self buildFloatingButton];
        [self buildMenuWindow];
    }
    return self;
}

// ============================================================
// FLOATING BUTTON  — UIButton, самый простой вариант
// ============================================================
- (void)buildFloatingButton {
    _btnFloat = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnFloat.frame = CGRectMake(30, 120, 54, 54);
    _btnFloat.backgroundColor = [UIColor colorWithRed:0.0 green:0.78 blue:0.0 alpha:1.0];
    _btnFloat.layer.cornerRadius = 27;
    _btnFloat.layer.borderWidth = 2;
    _btnFloat.layer.borderColor = [UIColor whiteColor].CGColor;
    _btnFloat.clipsToBounds = YES;
    [_btnFloat setTitle:@"M" forState:UIControlStateNormal];
    [_btnFloat setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnFloat.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [_btnFloat addTarget:self action:@selector(floatTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(floatPan:)];
    [_btnFloat addGestureRecognizer:pan];

    [self addSubview:_btnFloat];
}

- (void)floatTapped {
    [self showMenu];
}

- (void)floatPan:(UIPanGestureRecognizer *)gr {
    CGPoint loc = [gr locationInView:self];
    if (gr.state == UIGestureRecognizerStateBegan) {
        _dragStart = loc;
        _btnCenterStart = _btnFloat.center;
        _dragging = YES;
    } else if (gr.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = loc.x - _dragStart.x;
        CGFloat dy = loc.y - _dragStart.y;
        CGPoint newC = CGPointMake(_btnCenterStart.x + dx, _btnCenterStart.y + dy);
        CGFloat r = 27;
        CGRect b = self.bounds;
        newC.x = MAX(r, MIN(b.size.width - r, newC.x));
        newC.y = MAX(r, MIN(b.size.height - r, newC.y));
        _btnFloat.center = newC;
    } else {
        _dragging = NO;
    }
}

// ============================================================
// MENU WINDOW — отдельное окно поверх всего
// ============================================================
- (void)buildMenuWindow {
    CGRect screen = [UIScreen mainScreen].bounds;

    _menuWindow = [[UIWindow alloc] initWithFrame:screen];
    _menuWindow.windowLevel = UIWindowLevelAlert + 1;
    _menuWindow.backgroundColor = [UIColor clearColor];
    _menuWindow.hidden = YES;

    _menuVC = [[UIViewController alloc] init];
    _menuVC.view.backgroundColor = [UIColor clearColor];
    _menuWindow.rootViewController = _menuVC;

    [self buildMenuContent];
}

- (void)buildMenuContent {
    UIView *root = _menuVC.view;
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat W = MIN(screen.size.width - 20, 400);
    CGFloat H = 300;
    CGFloat X = (screen.size.width - W) / 2;
    CGFloat Y = (screen.size.height - H) / 2;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(X, Y, W, H)];
    box.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:0.97];
    box.layer.cornerRadius = 14;
    box.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    box.layer.borderWidth = 1.5;
    box.clipsToBounds = YES;
    box.tag = 999;
    [root addSubview:box];

    // drag меню
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(menuDrag:)];
    [box addGestureRecognizer:drag];

    // Header
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 38)];
    hdr.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    [box addSubview:hdr];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, W - 60, 38)];
    title.text = @"MENU TIPA";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    [hdr addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(W - 40, 5, 30, 28);
    closeBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1.0];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [closeBtn addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:closeBtn];

    // Tab bar
    CGFloat tabH = 36;
    UIView *tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 38, W, tabH)];
    tabBar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    [box addSubview:tabBar];

    CGFloat tabW = W / 3;
    NSArray *tabTitles = @[@"ESP", @"AIM", @"Settings"];
    UIColor *activeColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.0 alpha:1.0];
    UIColor *inactiveColor = [UIColor colorWithWhite:0.2 alpha:1.0];

    _btnMain    = [self makeTabBtn:tabTitles[0] frame:CGRectMake(0,       0, tabW, tabH) color:activeColor   tag:0];
    _btnAim     = [self makeTabBtn:tabTitles[1] frame:CGRectMake(tabW,    0, tabW, tabH) color:inactiveColor tag:1];
    _btnSetting = [self makeTabBtn:tabTitles[2] frame:CGRectMake(tabW*2,  0, tabW, tabH) color:inactiveColor tag:2];
    [tabBar addSubview:_btnMain];
    [tabBar addSubview:_btnAim];
    [tabBar addSubview:_btnSetting];

    // Content area
    CGFloat contentY = 38 + tabH;
    CGFloat contentH = H - contentY;

    _tabMain    = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, W, contentH)];
    _tabAim     = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, W, contentH)];
    _tabSetting = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, W, contentH)];
    _tabAim.hidden = YES;
    _tabSetting.hidden = YES;
    for (UIView *v in @[_tabMain, _tabAim, _tabSetting]) {
        v.backgroundColor = [UIColor clearColor];
        [box addSubview:v];
    }

    [self buildTabMain:contentH width:W];
    [self buildTabAim:contentH width:W];
    [self buildTabSetting:contentH width:W];
}

- (UIButton *)makeTabBtn:(NSString *)title frame:(CGRect)frame color:(UIColor *)color tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.backgroundColor = color;
    btn.tag = tag;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [btn addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)tabTapped:(UIButton *)btn {
    _tabMain.hidden = YES; _tabAim.hidden = YES; _tabSetting.hidden = YES;
    UIColor *on  = [UIColor colorWithRed:0.0 green:0.7 blue:0.0 alpha:1.0];
    UIColor *off = [UIColor colorWithWhite:0.2 alpha:1.0];
    _btnMain.backgroundColor = off; _btnAim.backgroundColor = off; _btnSetting.backgroundColor = off;

    if (btn.tag == 0) { _tabMain.hidden    = NO; _btnMain.backgroundColor    = on; }
    if (btn.tag == 1) { _tabAim.hidden     = NO; _btnAim.backgroundColor     = on; }
    if (btn.tag == 2) { _tabSetting.hidden = NO; _btnSetting.backgroundColor = on; }
}

// ============================================================
// ESP TAB
// ============================================================
- (void)buildTabMain:(CGFloat)H width:(CGFloat)W {
    CGFloat y = 8;
    y = [self addRow:_tabMain title:@"Box"      y:y on:isBox      sel:@selector(toggleBox:)];
    y = [self addRow:_tabMain title:@"Bone"     y:y on:isBone     sel:@selector(toggleBone:)];
    y = [self addRow:_tabMain title:@"Health"   y:y on:isHealth   sel:@selector(toggleHealth:)];
    y = [self addRow:_tabMain title:@"Name"     y:y on:isName     sel:@selector(toggleName:)];
    y = [self addRow:_tabMain title:@"Distance" y:y on:isDis      sel:@selector(toggleDist:)];

    UILabel *sL = [[UILabel alloc] initWithFrame:CGRectMake(16, y+4, 60, 24)];
    sL.text = @"Size:"; sL.textColor = [UIColor whiteColor]; sL.font = [UIFont systemFontOfSize:13];
    [_tabMain addSubview:sL];

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(70, y, W - 90, 32)];
    sl.minimumValue = 0.5; sl.maximumValue = 1.5; sl.value = 1.0;
    sl.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.0 alpha:1.0];
    [sl addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
    [_tabMain addSubview:sl];
}

// ============================================================
// AIM TAB
// ============================================================
- (void)buildTabAim:(CGFloat)H width:(CGFloat)W {
    CGFloat y = 8;
    y = [self addRow:_tabAim title:@"Enable Aimbot" y:y on:isAimbot sel:@selector(toggleAimbot:)];

    UILabel *fL = [[UILabel alloc] initWithFrame:CGRectMake(16, y+4, 120, 24)];
    fL.text = @"FOV Radius:"; fL.textColor = [UIColor whiteColor]; fL.font = [UIFont systemFontOfSize:13];
    [_tabAim addSubview:fL];
    UISlider *fs = [[UISlider alloc] initWithFrame:CGRectMake(16, y+28, W - 32, 32)];
    fs.minimumValue = 10; fs.maximumValue = 400; fs.value = aimFov;
    fs.minimumTrackTintColor = [UIColor redColor];
    [fs addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];
    [_tabAim addSubview:fs];
    y += 68;

    UILabel *dL = [[UILabel alloc] initWithFrame:CGRectMake(16, y+4, 150, 24)];
    dL.text = @"Aim Distance (m):"; dL.textColor = [UIColor whiteColor]; dL.font = [UIFont systemFontOfSize:13];
    [_tabAim addSubview:dL];
    UISlider *ds = [[UISlider alloc] initWithFrame:CGRectMake(16, y+28, W - 32, 32)];
    ds.minimumValue = 10; ds.maximumValue = 500; ds.value = aimDistance;
    ds.minimumTrackTintColor = [UIColor blueColor];
    [ds addTarget:self action:@selector(distChanged:) forControlEvents:UIControlEventValueChanged];
    [_tabAim addSubview:ds];
}

// ============================================================
// SETTINGS TAB
// ============================================================
- (void)buildTabSetting:(CGFloat)H width:(CGFloat)W {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, W - 32, 40)];
    l.text = @"Settings — coming soon";
    l.textColor = [UIColor lightGrayColor];
    l.font = [UIFont systemFontOfSize:14];
    [_tabSetting addSubview:l];
}

// ============================================================
// Row helper
// ============================================================
- (CGFloat)addRow:(UIView *)parent title:(NSString *)title y:(CGFloat)y on:(BOOL)on sel:(SEL)sel {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 32)];
    lbl.text = title; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont systemFontOfSize:14];
    [parent addSubview:lbl];

    CustomSwitch *sw = [[CustomSwitch alloc] initWithFrame:CGRectMake(parent.bounds.size.width - 68, y+3, 52, 26)];
    sw.on = on;
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sw];
    return y + 36;
}

// ============================================================
// Show / Hide
// ============================================================
- (void)showMenu {
    _menuWindow.hidden = NO;
    [_menuWindow makeKeyAndVisible];
    UIView *box = [_menuVC.view viewWithTag:999];
    box.transform = CGAffineTransformMakeScale(0.1, 0.1);
    box.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{
        box.transform = CGAffineTransformIdentity;
        box.alpha = 1;
    }];
    _btnFloat.hidden = YES;
}

- (void)hideMenu {
    UIView *box = [_menuVC.view viewWithTag:999];
    [UIView animateWithDuration:0.2 animations:^{
        box.transform = CGAffineTransformMakeScale(0.1, 0.1);
        box.alpha = 0;
    } completion:^(BOOL done){
        self->_menuWindow.hidden = YES;
        self->_btnFloat.hidden = NO;
    }];
}

- (void)menuDrag:(UIPanGestureRecognizer *)gr {
    UIView *box = [_menuVC.view viewWithTag:999];
    CGPoint delta = [gr translationInView:_menuVC.view];
    box.center = CGPointMake(box.center.x + delta.x, box.center.y + delta.y);
    [gr setTranslation:CGPointZero inView:_menuVC.view];
}

// ============================================================
// Toggle handlers
// ============================================================
- (void)toggleBox:(CustomSwitch *)s    { isBox    = s.isOn; }
- (void)toggleBone:(CustomSwitch *)s   { isBone   = s.isOn; }
- (void)toggleHealth:(CustomSwitch *)s { isHealth = s.isOn; }
- (void)toggleName:(CustomSwitch *)s   { isName   = s.isOn; }
- (void)toggleDist:(CustomSwitch *)s   { isDis    = s.isOn; }
- (void)toggleAimbot:(CustomSwitch *)s { isAimbot = s.isOn; }
- (void)sizeChanged:(UISlider *)s      { }
- (void)fovChanged:(UISlider *)s       { aimFov      = s.value; }
- (void)distChanged:(UISlider *)s      { aimDistance = s.value; }

// ============================================================
// layoutSubviews — resize MenuView, keep button on screen
// ============================================================
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) self.frame = self.superview.bounds;
    if (_btnFloat) {
        CGRect b = self.bounds;
        CGPoint c = _btnFloat.center;
        c.x = MAX(27, MIN(b.size.width  - 27, c.x));
        c.y = MAX(27, MIN(b.size.height - 27, c.y));
        _btnFloat.center = c;
    }
}

// ============================================================
// hitTest — только floatingButton, меню в отдельном окне
// ============================================================
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden) return nil;
    if (_btnFloat && !_btnFloat.hidden) {
        CGPoint p = [self convertPoint:point toView:_btnFloat];
        if ([_btnFloat pointInside:p withEvent:event]) return _btnFloat;
    }
    return nil;
}

// ============================================================
// SetUpBase + updateFrame + ESP render
// ============================================================
- (void)SetUpBase {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth");
    });
}

- (void)updateFrame {
    if (!self.window) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *l in self.drawingLayers) [l removeFromSuperlayer];
    [self.drawingLayers removeAllObjects];

    if (isAimbot) {
        float cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
        CAShapeLayer *circle = [CAShapeLayer layer];
        circle.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx,cy) radius:aimFov startAngle:0 endAngle:2*M_PI clockwise:YES].CGPath;
        circle.fillColor = [UIColor clearColor].CGColor;
        circle.strokeColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
        circle.lineWidth = 1;
        [self.drawingLayers addObject:circle];
    }

    [self renderESPToLayers:self.drawingLayers];
    for (CALayer *l in self.drawingLayers) [self.layer addSublayer:l];
    [CATransaction commit];
}

- (void)dealloc {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

// ============================================================
// ESP helpers + render
// ============================================================
static inline void DrawBoneLine(NSMutableArray<CALayer*>*layers,CGPoint p1,CGPoint p2,UIColor*color,CGFloat w){
    CGFloat dx=p2.x-p1.x,dy=p2.y-p1.y,len=sqrt(dx*dx+dy*dy);
    if(len<2)return;
    CALayer*l=[CALayer layer];
    l.backgroundColor=color.CGColor;
    l.bounds=CGRectMake(0,0,len,w);
    l.position=p1;
    l.anchorPoint=CGPointMake(0,0.5);
    l.transform=CATransform3DMakeRotation(atan2(dy,dx),0,0,1);
    [layers addObject:l];
}

Quaternion GetRotationToLocation(Vector3 t,float b,Vector3 m){return Quaternion::LookRotation((t+Vector3(0,b,0))-m,Vector3(0,1,0));}
void set_aim(uint64_t p,Quaternion r){if(!isVaildPtr(p))return;WriteAddr<Quaternion>(p+0x53C,r);}
bool get_IsFiring(uint64_t p){if(!isVaildPtr(p))return false;return ReadAddr<bool>(p+0x750);}
bool get_IsVisible(uint64_t p){
    if(!isVaildPtr(p))return false;
    uint64_t v=ReadAddr<uint64_t>(p+0x9B0);
    if(!isVaildPtr(v))return false;
    return (ReadAddr<int>(v+0x10)&0x1)==0;
}

- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers {
    if(Moudule_Base==(uint64_t)-1)return;
    uint64_t matchGame=getMatchGame(Moudule_Base);
    uint64_t camera=CameraMain(matchGame);
    if(!isVaildPtr(camera))return;
    uint64_t match=getMatch(matchGame);
    if(!isVaildPtr(match))return;
    uint64_t myPawn=getLocalPlayer(match);
    if(!isVaildPtr(myPawn))return;
    uint64_t camTr=ReadAddr<uint64_t>(myPawn+0x318);
    Vector3 myLoc=getPositionExt(camTr);
    uint64_t player=ReadAddr<uint64_t>(match+0x120);
    uint64_t tVal=ReadAddr<uint64_t>(player+0x28);
    int cnt=ReadAddr<int>(tVal+0x18);
    float*matrix=GetViewMatrix(camera);
    float vW=self.bounds.size.width,vH=self.bounds.size.height;
    CGPoint sc=CGPointMake(vW/2,vH/2);
    uint64_t best=0;int minHP=99999;bool isFire=false;
    for(int i=0;i<cnt;i++){
        uint64_t P=ReadAddr<uint64_t>(tVal+0x20+8*i);
        if(!isVaildPtr(P))continue;
        if(isLocalTeamMate(myPawn,P))continue;
        int hp=get_CurHP(P);if(hp<=0)continue;
        Vector3 head=getPositionExt(getHead(P));
        isFire=get_IsFiring(myPawn);
        float dis=Vector3::Distance(myLoc,head);
        if(dis>400)continue;
        if(isAimbot&&dis<=aimDistance){
            Vector3 s=WorldToScreen(head,matrix,vW,vH);
            float dx=s.x-sc.x,dy=s.y-sc.y;
            if(sqrt(dx*dx+dy*dy)<=aimFov&&hp<minHP){minHP=hp;best=P;}
        }
        if(dis>220)continue;
        Vector3 toe=getPositionExt(getRightToeNode(P));
        Vector3 hip=getPositionExt(getHip(P));
        Vector3 s_head=WorldToScreen(head,matrix,vW,vH);
        Vector3 s_toe=WorldToScreen(toe,matrix,vW,vH);
        Vector3 s_hip=WorldToScreen(hip,matrix,vW,vH);
        float bH=fabs(s_head.y-s_toe.y),bW=bH*0.5f;
        float bx=s_head.x-bW/2,by=s_head.y;
        if(isBox){CALayer*l=[CALayer layer];l.frame=CGRectMake(bx,by,bW,bH);l.borderColor=[UIColor redColor].CGColor;l.borderWidth=1;l.cornerRadius=2;[layers addObject:l];}
        if(isName){NSString*n=GetNickName(P);if(n.length){CATextLayer*t=[CATextLayer layer];t.string=n;t.fontSize=10;t.frame=CGRectMake(bx-20,by-14,bW+40,14);t.alignmentMode=kCAAlignmentCenter;t.foregroundColor=[UIColor greenColor].CGColor;[layers addObject:t];}}
        if(isHealth){int mhp=get_MaxHP(P);if(mhp>0){float r=MAX(0,MIN(1,(float)hp/mhp));float brl=4,brh=bH,fh=brh*r;CALayer*bg=[CALayer layer];bg.frame=CGRectMake(bx-6,by,brl,brh);bg.backgroundColor=[UIColor redColor].CGColor;[layers addObject:bg];CALayer*fg=[CALayer layer];fg.frame=CGRectMake(bx-6,by+brh-fh,brl,fh);fg.backgroundColor=[UIColor greenColor].CGColor;[layers addObject:fg];}}
        if(isDis){CATextLayer*t=[CATextLayer layer];t.string=[NSString stringWithFormat:@"%.0fm",dis];t.fontSize=9;t.frame=CGRectMake(bx-10,by+bH+2,bW+20,12);t.alignmentMode=kCAAlignmentCenter;t.foregroundColor=[UIColor whiteColor].CGColor;[layers addObject:t];}
        if(isBone){
            Vector3 ls=getPositionExt(getLeftShoulder(P)),rs=getPositionExt(getRightShoulder(P));
            Vector3 le=getPositionExt(getLeftElbow(P)),re=getPositionExt(getRightElbow(P));
            Vector3 lh=getPositionExt(getLeftHand(P)),rh=getPositionExt(getRightHand(P));
            Vector3 la=getPositionExt(getLeftAnkle(P)),ra=getPositionExt(getRightAnkle(P));
            #define W2S(v) WorldToScreen(v,matrix,vW,vH)
            #define PT(v) CGPointMake(W2S(v).x,W2S(v).y)
            UIColor*bc=[UIColor whiteColor];
            DrawBoneLine(layers,PT(head),PT(hip),bc,1);
            DrawBoneLine(layers,PT(ls),PT(rs),bc,1);
            DrawBoneLine(layers,PT(ls),PT(le),bc,1);DrawBoneLine(layers,PT(le),PT(lh),bc,1);
            DrawBoneLine(layers,PT(rs),PT(re),bc,1);DrawBoneLine(layers,PT(re),PT(rh),bc,1);
            DrawBoneLine(layers,PT(hip),PT(la),bc,1);DrawBoneLine(layers,PT(hip),PT(ra),bc,1);
            #undef W2S
            #undef PT
        }
    }
    if(isAimbot&&isVaildPtr(best)&&isFire){
        Vector3 eh=getPositionExt(getHead(best));
        set_aim(myPawn,GetRotationToLocation(eh,0.1f,myLoc));
    }
}

@end
