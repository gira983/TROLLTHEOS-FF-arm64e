#import "esp.h"
#import "../../mahoa.h"
#import "../lib/GameLogic.h"
#import "../lib/UnityMath.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

#ifdef __cplusplus
extern "C" {
#endif
    bool get_IsFiring(uint64_t player);
    void set_aim(uint64_t player, Vector3 angle);
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wreturn-type-c-linkage"
    Vector3 GetRotationToLocation(Vector3 targetPos, float speed, Vector3 myPos);
    #pragma clang diagnostic pop
#ifdef __cplusplus
}
#endif

uint64_t Moudule_Base = -1;

static bool isBox = YES;
static bool isBone = YES;
static bool isHealth = YES;
static bool isName = YES;
static bool isDis = YES;
static bool isAimbot = NO;
static float aimFov = 150.0f;
static float aimDistance = 200.0f;

@interface MenuView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
@end

@implementation MenuView {
    UIButton *_btnFloat;
    CGPoint   _dragStart;
    CGPoint   _btnCenterAtDrag;
    BOOL      _isDragging;

    UIView  *_menuBox;
    UIView  *_tabMain;
    UIView  *_tabAim;
    UIView  *_tabSetting;
    UIButton *_btnTabMain, *_btnTabAim, *_btnTabSetting;
}

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
        [self buildMenuBox];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)appDidBecomeActive {
    if (self.displayLink) {
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self.displayLink.paused = NO;
    }
}

- (void)buildFloatingButton {
    _btnFloat = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnFloat.frame = CGRectMake(30, 120, 54, 54);
    
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = _btnFloat.bounds;
    grad.colors = @[(id)[UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0].CGColor, 
                    (id)[UIColor colorWithRed:0.0 green:0.5 blue:0.2 alpha:1.0].CGColor];
    grad.cornerRadius = 27;
    [_btnFloat.layer addSublayer:grad];
    
    _btnFloat.layer.cornerRadius = 27;
    _btnFloat.layer.borderWidth = 2;
    _btnFloat.layer.borderColor = [UIColor whiteColor].CGColor;
    _btnFloat.layer.shadowColor = [UIColor blackColor].CGColor;
    _btnFloat.layer.shadowOffset = CGSizeMake(0, 3);
    _btnFloat.layer.shadowOpacity = 0.5;
    _btnFloat.layer.shadowRadius = 5;
    
    [_btnFloat setTitle:@"M" forState:UIControlStateNormal];
    [_btnFloat setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnFloat.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    
    [_btnFloat addTarget:self action:@selector(floatTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(floatPan:)];
    pan.cancelsTouchesInView = YES;
    [_btnFloat addGestureRecognizer:pan];
    
    [self addSubview:_btnFloat];
}

- (void)floatTapped {
    if (!_isDragging) {
        [self showMenu];
    }
}

- (void)floatPan:(UIPanGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        _isDragging = YES;
        _dragStart = [gr locationInView:self];
        _btnCenterAtDrag = _btnFloat.center;
        [UIView animateWithDuration:0.2 animations:^{
            self->_btnFloat.transform = CGAffineTransformMakeScale(1.1, 1.1);
        }];
    } else if (gr.state == UIGestureRecognizerStateChanged) {
        CGPoint loc = [gr locationInView:self];
        CGFloat r = 27;
        CGRect b = self.bounds;
        CGPoint c = CGPointMake(
            MAX(r, MIN(b.size.width  - r, _btnCenterAtDrag.x + loc.x - _dragStart.x)),
            MAX(r, MIN(b.size.height - r, _btnCenterAtDrag.y + loc.y - _dragStart.y))
        );
        _btnFloat.center = c;
    } else if (gr.state == UIGestureRecognizerStateEnded || gr.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.2 animations:^{
            self->_btnFloat.transform = CGAffineTransformIdentity;
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self->_isDragging = NO;
        });
    }
}

- (void)buildMenuBox {
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat W = MIN(screen.size.width - 40, 380);
    CGFloat H = 320;
    CGFloat X = (screen.size.width  - W) / 2;
    CGFloat Y = (screen.size.height - H) / 2;

    _menuBox = [[UIView alloc] initWithFrame:CGRectMake(X, Y, W, H)];
    _menuBox.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.12 alpha:0.98];
    _menuBox.layer.cornerRadius = 20;
    _menuBox.layer.borderColor  = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.6].CGColor;
    _menuBox.layer.borderWidth  = 2.0;
    _menuBox.layer.shadowColor = [UIColor blackColor].CGColor;
    _menuBox.layer.shadowRadius = 15;
    _menuBox.layer.shadowOpacity = 0.8;
    _menuBox.userInteractionEnabled = YES;
    _menuBox.hidden = YES;
    [self addSubview:_menuBox];

    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(menuDrag:)];
    drag.cancelsTouchesInView = NO;
    [_menuBox addGestureRecognizer:drag];

    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 50)];
    hdr.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:hdr.bounds byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight) cornerRadii:CGSizeMake(20, 20)];
    CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
    maskLayer.frame = hdr.bounds;
    maskLayer.path = maskPath.CGPath;
    hdr.layer.mask = maskLayer;
    hdr.userInteractionEnabled = YES;
    [_menuBox addSubview:hdr];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, W-80, 50)];
    ttl.text = @"XYRIS PREMIUM"; ttl.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.5 alpha:1.0];
    ttl.font = [UIFont fontWithName:@"AvenirNext-Bold" size:18];
    [hdr addSubview:ttl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(W-45, 10, 30, 30);
    closeBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.8];
    closeBtn.layer.cornerRadius = 15;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:closeBtn];

    UIView *tabBar = [[UIView alloc] initWithFrame:CGRectMake(10, 60, W-20, 40)];
    tabBar.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    tabBar.layer.cornerRadius = 10;
    tabBar.userInteractionEnabled = YES;
    [_menuBox addSubview:tabBar];

    CGFloat tw = (W-20) / 3;
    _btnTabMain    = [self tabBtn:@"ESP"      frame:CGRectMake(0,   0, tw, 40) tag:0];
    _btnTabAim     = [self tabBtn:@"AIM"      frame:CGRectMake(tw,  0, tw, 40) tag:1];
    _btnTabSetting = [self tabBtn:@"CONFIG"   frame:CGRectMake(tw*2,0, tw, 40) tag:2];
    [tabBar addSubview:_btnTabMain];
    [tabBar addSubview:_btnTabAim];
    [tabBar addSubview:_btnTabSetting];
    [self updateTabUI:0];

    CGFloat cy = 110, ch = H - cy - 10;
    _tabMain    = [[UIView alloc] initWithFrame:CGRectMake(0, cy, W, ch)];
    _tabAim     = [[UIView alloc] initWithFrame:CGRectMake(0, cy, W, ch)];
    _tabSetting = [[UIView alloc] initWithFrame:CGRectMake(0, cy, W, ch)];
    _tabAim.hidden = YES; _tabSetting.hidden = YES;
    for (UIView *v in @[_tabMain, _tabAim, _tabSetting]) {
        v.backgroundColor = [UIColor clearColor];
        v.userInteractionEnabled = YES;
        [_menuBox addSubview:v];
    }

    [self buildESPTab:ch width:W];
    [self buildAIMTab:ch width:W];
    [self buildSettingsTab];
}

- (UIButton *)tabBtn:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = f; btn.tag = tag;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [btn addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)tabTapped:(UIButton *)btn {
    [self updateTabUI:btn.tag];
}

- (void)updateTabUI:(NSInteger)tag {
    _tabMain.hidden = (tag != 0);
    _tabAim.hidden = (tag != 1);
    _tabSetting.hidden = (tag != 2);
    
    UIColor *activeColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    UIColor *inactiveColor = [UIColor grayColor];
    
    [_btnTabMain setTitleColor:(tag == 0 ? activeColor : inactiveColor) forState:UIControlStateNormal];
    [_btnTabAim setTitleColor:(tag == 1 ? activeColor : inactiveColor) forState:UIControlStateNormal];
    [_btnTabSetting setTitleColor:(tag == 2 ? activeColor : inactiveColor) forState:UIControlStateNormal];
}

- (void)buildESPTab:(CGFloat)H width:(CGFloat)W {
    CGFloat y = 5;
    y = [self row:_tabMain title:@"Player Box"      y:y val:isBox    sel:@selector(toggleBox:)    W:W];
    y = [self row:_tabMain title:@"Skeleton"        y:y val:isBone   sel:@selector(toggleBone:)   W:W];
    y = [self row:_tabMain title:@"Health Bar"      y:y val:isHealth sel:@selector(toggleHealth:) W:W];
    y = [self row:_tabMain title:@"Player Name"     y:y val:isName   sel:@selector(toggleName:)   W:W];
    y = [self row:_tabMain title:@"Distance Info"   y:y val:isDis    sel:@selector(toggleDist:)   W:W];
}

- (void)buildAIMTab:(CGFloat)H width:(CGFloat)W {
    CGFloat y = 10;
    y = [self row:_tabAim title:@"Enable Aimbot" y:y val:isAimbot sel:@selector(toggleAimbot:) W:W];

    UILabel *fl = [[UILabel alloc] initWithFrame:CGRectMake(20, y+5, 120, 20)];
    fl.text = @"FOV Radius"; fl.textColor = [UIColor lightGrayColor]; fl.font = [UIFont systemFontOfSize:12];
    [_tabAim addSubview:fl];
    UISlider *fs = [[UISlider alloc] initWithFrame:CGRectMake(20, y+25, W-40, 30)];
    fs.minimumValue = 10; fs.maximumValue = 400; fs.value = aimFov;
    fs.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    [fs addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];
    [_tabAim addSubview:fs];
    y += 60;

    UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(20, y+5, 160, 20)];
    dl.text = @"Max Distance"; dl.textColor = [UIColor lightGrayColor]; dl.font = [UIFont systemFontOfSize:12];
    [_tabAim addSubview:dl];
    UISlider *ds = [[UISlider alloc] initWithFrame:CGRectMake(20, y+25, W-40, 30)];
    ds.minimumValue = 10; ds.maximumValue = 500; ds.value = aimDistance;
    ds.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    [ds addTarget:self action:@selector(distChanged:) forControlEvents:UIControlEventValueChanged];
    [_tabAim addSubview:ds];
}

- (void)buildSettingsTab {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, 380, 30)];
    l.text = @"DESIGNED BY MANUS AI";
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor colorWithWhite:0.4 alpha:1.0]; l.font = [UIFont italicSystemFontOfSize:14];
    [_tabSetting addSubview:l];
}

- (CGFloat)row:(UIView *)parent title:(NSString *)t y:(CGFloat)y val:(BOOL)v sel:(SEL)sel W:(CGFloat)W {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 35)];
    l.text = t; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:15];
    [parent addSubview:l];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(W-75, y+2, 51, 31)];
    sw.on = v;
    sw.onTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sw];
    
    return y + 40;
}

- (void)showMenu {
    _menuBox.hidden = NO;
    _btnFloat.hidden = YES;
    _menuBox.transform = CGAffineTransformMakeScale(0.8, 0.8);
    _menuBox.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        self->_menuBox.transform = CGAffineTransformIdentity;
        self->_menuBox.alpha = 1;
    } completion:nil];
}

- (void)hideMenu {
    [UIView animateWithDuration:0.2 animations:^{
        self->_menuBox.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self->_menuBox.alpha = 0;
    } completion:^(BOOL done){
        self->_menuBox.hidden = YES;
        self->_btnFloat.hidden = NO;
    }];
}

- (void)menuDrag:(UIPanGestureRecognizer *)gr {
    CGPoint d = [gr translationInView:self];
    _menuBox.center = CGPointMake(_menuBox.center.x + d.x, _menuBox.center.y + d.y);
    [gr setTranslation:CGPointZero inView:self];
}

- (void)toggleBox:(UISwitch *)s    { isBox    = s.isOn; }
- (void)toggleBone:(UISwitch *)s   { isBone   = s.isOn; }
- (void)toggleHealth:(UISwitch *)s { isHealth = s.isOn; }
- (void)toggleName:(UISwitch *)s   { isName   = s.isOn; }
- (void)toggleDist:(UISwitch *)s   { isDis    = s.isOn; }
- (void)toggleAimbot:(UISwitch *)s { isAimbot = s.isOn; }
- (void)fovChanged:(UISlider *)s       { aimFov      = s.value; }
- (void)distChanged:(UISlider *)s      { aimDistance = s.value; }

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) self.frame = self.superview.bounds;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;

    if (_btnFloat && !_btnFloat.hidden) {
        CGPoint p = [self convertPoint:point toView:_btnFloat];
        if ([_btnFloat pointInside:p withEvent:event]) return _btnFloat;
    }

    if (_menuBox && !_menuBox.hidden) {
        CGPoint p = [self convertPoint:point toView:_menuBox];
        if ([_menuBox pointInside:p withEvent:event]) {
            UIView *hit = [_menuBox hitTest:p withEvent:event];
            return hit ?: _menuBox;
        }
    }
    return nil;
}

- (void)SetUpBase {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth");
    });
}

- (void)updateFrame {
    if (!self.window) return;
    if (self.displayLink && self.displayLink.paused) { self.displayLink.paused = NO; }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *l in self.drawingLayers) [l removeFromSuperlayer];
    [self.drawingLayers removeAllObjects];
    
    if (isAimbot) {
        float cx = self.bounds.size.width/2, cy = self.bounds.size.height/2;
        CAShapeLayer *circle = [CAShapeLayer layer];
        circle.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx,cy) radius:aimFov startAngle:0 endAngle:2*M_PI clockwise:YES].CGPath;
        circle.fillColor = [UIColor clearColor].CGColor;
        circle.strokeColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.4].CGColor;
        circle.lineWidth = 1.5;
        [self.drawingLayers addObject:circle];
    }
    
    [self renderESPToLayers:self.drawingLayers];
    for (CALayer *l in self.drawingLayers) [self.layer addSublayer:l];
    [CATransaction commit];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate]; self.displayLink = nil;
}

- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers {
    if(Moudule_Base==(uint64_t)-1)return;
    uint64_t mg=getMatchGame(Moudule_Base),cam=CameraMain(mg);
    if(!isVaildPtr(cam))return;
    uint64_t match=getMatch(mg);if(!isVaildPtr(match))return;
    uint64_t me=getLocalPlayer(match);if(!isVaildPtr(me))return;
    Vector3 myL=getPositionExt(ReadAddr<uint64_t>(me+0x318));
    uint64_t pl=ReadAddr<uint64_t>(match+0x120),tv=ReadAddr<uint64_t>(pl+0x28);
    int cnt=ReadAddr<int>(tv+0x18);
    float*mx=GetViewMatrix(cam),vW=self.bounds.size.width,vH=self.bounds.size.height;
    CGPoint sc=CGPointMake(vW/2,vH/2);
    uint64_t best=0;int minHP=99999;bool fire=false;
    for(int i=0;i<cnt;i++){
        uint64_t P=ReadAddr<uint64_t>(tv+0x20+8*i);
        if(!isVaildPtr(P)||isLocalTeamMate(me,P))continue;
        int hp=get_CurHP(P);if(hp<=0)continue;
        Vector3 hd=getPositionExt(getHead(P));
        fire=get_IsFiring(me);
        float dis=Vector3::Distance(myL,hd);if(dis>400)continue;
        if(isAimbot&&dis<=aimDistance){
            Vector3 s=WorldToScreen(hd,mx,vW,vH);float dx=s.x-sc.x,dy=s.y-sc.y;
            if(sqrt(dx*dx+dy*dy)<=aimFov&&hp<minHP){minHP=hp;best=P;}
        }
        if(dis>220)continue;
        Vector3 toe=getPositionExt(getRightToeNode(P)),hip=getPositionExt(getHip(P));
        Vector3 sh=WorldToScreen(hd,mx,vW,vH),st=WorldToScreen(toe,mx,vW,vH);
        float bH=fabs(sh.y-st.y),bW=bH*0.5f,bx=sh.x-bW/2,by=sh.y;
        if(isBox){CALayer*l=[CALayer layer];l.frame=CGRectMake(bx,by,bW,bH);l.borderColor=[UIColor redColor].CGColor;l.borderWidth=1;l.cornerRadius=2;[layers addObject:l];}
        if(isName){NSString*n=GetNickName(P);if(n.length){CATextLayer*t=[CATextLayer layer];t.string=n;t.fontSize=10;t.frame=CGRectMake(bx-20,by-14,bW+40,14);t.alignmentMode=kCAAlignmentCenter;t.foregroundColor=[UIColor greenColor].CGColor;[layers addObject:t];}}
        if(isHealth){int mhp=get_MaxHP(P);if(mhp>0){float r=MAX(0,MIN(1,(float)hp/mhp)),brl=4,brh=bH,fh=brh*r;CALayer*bg=[CALayer layer];bg.frame=CGRectMake(bx-6,by,brl,brh);bg.backgroundColor=[UIColor redColor].CGColor;[layers addObject:bg];CALayer*fg=[CALayer layer];fg.frame=CGRectMake(bx-6,by+brh-fh,brl,fh);fg.backgroundColor=[UIColor greenColor].CGColor;[layers addObject:fg];}}
        if(isDis){CATextLayer*t=[CATextLayer layer];t.string=[NSString stringWithFormat:@"%.0fm",dis];t.fontSize=9;t.frame=CGRectMake(bx-10,by+bH+2,bW+20,12);t.alignmentMode=kCAAlignmentCenter;t.foregroundColor=[UIColor whiteColor].CGColor;[layers addObject:t];}
        if(isBone){
            #define W2S(v) WorldToScreen(v,mx,vW,vH)
            #define CP(v) CGPointMake(W2S(v).x,W2S(v).y)
            UIColor*bc=[UIColor whiteColor];
            BoneLine(layers,CP(hd),CP(hip),bc,1);
            Vector3 ls=getPositionExt(getLeftShoulder(P)),rs=getPositionExt(getRightShoulder(P));
            Vector3 le=getPositionExt(getLeftElbow(P)),re=getPositionExt(getRightElbow(P));
            Vector3 lh2=getPositionExt(getLeftHand(P)),rh2=getPositionExt(getRightHand(P));
            Vector3 la=getPositionExt(getLeftAnkle(P)),ra=getPositionExt(getRightAnkle(P));
            BoneLine(layers,CP(ls),CP(rs),bc,1);
            BoneLine(layers,CP(ls),CP(le),bc,1);BoneLine(layers,CP(le),CP(lh2),bc,1);
            BoneLine(layers,CP(rs),CP(re),bc,1);BoneLine(layers,CP(re),CP(rh2),bc,1);
            BoneLine(layers,CP(hip),CP(la),bc,1);BoneLine(layers,CP(hip),CP(ra),bc,1);
            #undef W2S
            #undef CP
        }
    }
    if(isAimbot&&isVaildPtr(best)&&fire){set_aim(me,GetRotationToLocation(getPositionExt(getHead(best)),0.1f,myL));}
}

static inline void BoneLine(NSMutableArray<CALayer*>*L,CGPoint a,CGPoint b,UIColor*c,CGFloat w){
    CGFloat dx=b.x-a.x,dy=b.y-a.y,len=sqrt(dx*dx+dy*dy);
    if(len<2)return;
    CALayer*l=[CALayer layer];l.backgroundColor=c.CGColor;
    l.bounds=CGRectMake(0,0,len,w);l.position=a;l.anchorPoint=CGPointMake(0,0.5);
    l.transform=CATransform3DMakeRotation(atan2(dy,dx),0,0,1);[L addObject:l];
}

@end
