#import "esp.h"

// Лог в файл (определён в HUDApp.mm)
extern void writeLog(NSString *msg);
// Fallback если не линкуется
static void espLog(NSString *msg) {
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
}
#import "mahoa.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h> 
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

uint64_t Moudule_Base = -1;

// --- ESP Config ---
static bool isBox = YES;
static bool isBone = YES;
static bool isHealth = YES;
static bool isName = YES;
static bool isDis = YES;

// --- Aimbot Config ---
static bool isAimbot = NO;
static float aimFov = 150.0f; // Bán kính vòng tròn FOV
static float aimDistance = 200.0f; // Khoảng cách aim mặc định

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
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.bounds.size.height/2];
    CGContextSetFillColorWithColor(context, (self.isOn ? [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor colorWithWhite:0.15 alpha:1.0]).CGColor);
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
        CGRect frame = self->_thumb.frame;
        frame.origin.x = self.isOn ? self.bounds.size.width - frame.size.width - 2 : 2;
        self->_thumb.frame = frame;
        self->_thumb.backgroundColor = self.isOn ? UIColor.whiteColor : [UIColor colorWithWhite:0.75 alpha:1.0];
    }];
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


@implementation MenuView {
    UIView *menuContainer;
    UIView *floatingButton;
    CGPoint _initialTouchPoint;
    
    // Tab Views
    UIView *mainTabContainer;
    UIView *aimTabContainer;
    UIView *settingTabContainer;
    UIView *_sidebar;

    UIView *previewView;
    UIView *previewContentContainer;
    
    UILabel *previewNameLabel;
    UILabel *previewDistLabel;
    UIView *healthBarContainer;
    UIView *boxContainer;
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
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [self setupFloatingButton];
        [self setupMenuUI];
        [self layoutSubviews];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
    
    // Меню открыто
    if (menuContainer && !menuContainer.hidden) {
        CGPoint pInMenu = [self convertPoint:point toView:menuContainer];
        if ([menuContainer pointInside:pInMenu withEvent:event]) {
        
        espLog([NSString stringWithFormat:@"[HITTEST] point=(%.0f,%.0f) menuContainer OK", pInMenu.x, pInMenu.y]);
        
        // 1. ПРИОРИТЕТ: sidebar с кнопками табов (Main/AIM/Setting)
        if (_sidebar && !_sidebar.hidden) {
            CGPoint pInSidebar = [menuContainer convertPoint:pInMenu toView:_sidebar];
            if ([_sidebar pointInside:pInSidebar withEvent:event]) {
                for (UIView *btn in _sidebar.subviews.reverseObjectEnumerator) {
                    if (btn.hidden || !btn.userInteractionEnabled) continue;
                    CGPoint pInBtn = [_sidebar convertPoint:pInSidebar toView:btn];
                    if ([btn pointInside:pInBtn withEvent:event]) {
                        espLog([NSString stringWithFormat:@"[HITTEST] → sidebar btn tag=%ld", (long)btn.tag]);
                        return btn;
                    }
                }
                espLog(@"[HITTEST] → sidebar itself");
                return _sidebar;
            }
        }
        
        // 2. Активный таб контейнер
        UIView *activeTab = nil;
        if (mainTabContainer && !mainTabContainer.hidden) activeTab = mainTabContainer;
        else if (aimTabContainer && !aimTabContainer.hidden) activeTab = aimTabContainer;
        else if (settingTabContainer && !settingTabContainer.hidden) activeTab = settingTabContainer;
        
        if (activeTab) {
            CGPoint pInTab = [menuContainer convertPoint:pInMenu toView:activeTab];
            if ([activeTab pointInside:pInTab withEvent:event]) {
                for (UIView *sub in activeTab.subviews.reverseObjectEnumerator) {
                    if (sub.hidden || !sub.userInteractionEnabled || sub.alpha < 0.01) continue;
                    CGPoint pInSub = [activeTab convertPoint:pInTab toView:sub];
                    if (![sub pointInside:pInSub withEvent:event]) continue;
                    // HUDSlider — возвращаем сразу, он сам обрабатывает drag через touchesMoved
                    if ([sub isKindOfClass:[HUDSlider class]]) {
                        espLog([NSString stringWithFormat:@"[HITTEST] → HUDSlider frame=(%.0f,%.0f,%.0f,%.0f)", sub.frame.origin.x, sub.frame.origin.y, sub.frame.size.width, sub.frame.size.height]);
                        return sub;
                    }
                    for (UIView *leaf in sub.subviews.reverseObjectEnumerator) {
                        if (leaf.hidden || !leaf.userInteractionEnabled || leaf.alpha < 0.01) continue;
                        CGPoint pInLeaf = [sub convertPoint:pInSub toView:leaf];
                        if (![leaf pointInside:pInLeaf withEvent:event]) continue;
                        // UISlider или UISwitch внутри контейнера
                        if ([leaf isKindOfClass:[UISlider class]] ||
                            [leaf isKindOfClass:[UISwitch class]]) return leaf;
                        return leaf;
                    }
                    return sub;
                }
                return activeTab;
            }
        }
        
        // 3. Остальное в menuContainer (header, close button)
        for (UIView *sub in menuContainer.subviews.reverseObjectEnumerator) {
            if (sub == _sidebar || sub == mainTabContainer || 
                sub == aimTabContainer || sub == settingTabContainer) continue;
            if (sub.hidden || !sub.userInteractionEnabled || sub.alpha < 0.01) continue;
            CGPoint pInSub = [menuContainer convertPoint:pInMenu toView:sub];
            if (![sub pointInside:pInSub withEvent:event]) continue;
            // Углубляемся в sub (напр. headerView → circle кнопки)
            for (UIView *leaf in sub.subviews.reverseObjectEnumerator) {
                if (leaf.hidden || leaf.alpha < 0.01) continue;
                CGPoint pInLeaf = [sub convertPoint:pInSub toView:leaf];
                if ([leaf pointInside:pInLeaf withEvent:event]) return leaf;
            }
            return sub;
        }
        
            return menuContainer;
        } // конец if pointInside menuContainer
    }
    
    // Кнопка M
    if (floatingButton && !floatingButton.hidden) {
        CGPoint p = [self convertPoint:point toView:floatingButton];
        if ([floatingButton pointInside:p withEvent:event]) return floatingButton;
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

- (void)setupMenuUI {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat menuWidth = MIN(550, screenW - 10);
    CGFloat menuHeight = MIN(320, screenH * 0.55);
    
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
    subTitle.text = @"Cheat by LDVQuang";
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
        }
        [circle addSubview:btnIcon];
        [headerView addSubview:circle];
    }
    
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [headerView addGestureRecognizer:menuPan];
    
    // Sidebar Buttons
    CGFloat sidebarW = 75 * scale;
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectMake(menuWidth - sidebarW - 10, 50, sidebarW, 250 * scale)];
    sidebar.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    sidebar.layer.cornerRadius = 10;
    sidebar.userInteractionEnabled = YES;
    _sidebar = sidebar;
    [menuContainer addSubview:sidebar];
    
    NSArray *tabs = @[@"Main", @"AIM", @"Setting"];
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
        [sidebar addSubview:btn];
    }

    // --- MAIN TAB (ESP) ---
    CGFloat tabW = menuWidth - sidebarW - 25;
    CGFloat tabH = menuHeight - 55;
    mainTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
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

    // Size slider убран — не влияет на функционал

    // --- AIM TAB ---
    aimTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    aimTabContainer.backgroundColor = [UIColor blackColor];
    aimTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    aimTabContainer.layer.borderWidth = 1;
    aimTabContainer.layer.cornerRadius = 10;
    aimTabContainer.hidden = YES;
    [menuContainer addSubview:aimTabContainer];
    
    UILabel *aimTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    aimTitle.text = @"Aimbot Logic";
    aimTitle.textColor = [UIColor whiteColor];
    aimTitle.font = [UIFont boldSystemFontOfSize:16];
    [aimTabContainer addSubview:aimTitle];
    
    UIView *aimLine = [[UIView alloc] initWithFrame:CGRectMake(15, 35, tabW - 20, 1)];
    aimLine.backgroundColor = [UIColor whiteColor];
    [aimTabContainer addSubview:aimLine];
    
    [self addFeatureToView:aimTabContainer withTitle:@"Enable Aimbot" atY:45 initialValue:isAimbot andAction:@selector(toggleAimbot:)];
    
    // FOV Slider
    UILabel *fovLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 85, 200, 20)];
    fovLabel.text = @"FOV Radius:";
    fovLabel.textColor = [UIColor whiteColor];
    fovLabel.font = [UIFont systemFontOfSize:13];
    [aimTabContainer addSubview:fovLabel];
    
    __weak typeof(self) weakSelf = self;
    HUDSlider *fovSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(15, 110, tabW - 20, 44)];
    fovSlider.minimumValue = 10.0;
    fovSlider.maximumValue = 400.0;
    fovSlider.value = aimFov;
    fovSlider.thumbTintColor = [UIColor whiteColor];
    fovSlider.minimumTrackTintColor = [UIColor redColor];
    fovSlider.tag = 300;
    fovSlider.onValueChanged = ^(float v) { weakSelf->aimFov = v; };
    [aimTabContainer addSubview:fovSlider];
    
    // Distance Slider
    UILabel *distLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 145, 200, 20)];
    distLabel.text = @"Aim Distance (m):";
    distLabel.textColor = [UIColor whiteColor];
    distLabel.font = [UIFont systemFontOfSize:13];
    [aimTabContainer addSubview:distLabel];
    
    HUDSlider *distSlider = [[HUDSlider alloc] initWithFrame:CGRectMake(15, 170, tabW - 20, 44)];
    distSlider.minimumValue = 10.0;
    distSlider.maximumValue = 500.0;
    distSlider.value = aimDistance;
    distSlider.thumbTintColor = [UIColor whiteColor];
    distSlider.minimumTrackTintColor = [UIColor blueColor];
    distSlider.tag = 301;
    distSlider.onValueChanged = ^(float v) { weakSelf->aimDistance = v; };
    [aimTabContainer addSubview:distSlider];


    // --- SETTING TAB (Empty for now) ---
    settingTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, tabW, tabH)];
    settingTabContainer.backgroundColor = [UIColor blackColor];
    settingTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    settingTabContainer.layer.borderWidth = 1;
    settingTabContainer.layer.cornerRadius = 10;
    settingTabContainer.hidden = YES;
    [menuContainer addSubview:settingTabContainer];
    
    // Поднять sidebar поверх всех табов
    [menuContainer bringSubviewToFront:sidebar];
    
    UILabel *stTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    stTitle.text = @"Settings";
    stTitle.textColor = [UIColor whiteColor];
    stTitle.font = [UIFont boldSystemFontOfSize:16];
    [settingTabContainer addSubview:stTitle];
}

- (void)switchToTab:(NSInteger)tabIndex {
    mainTabContainer.hidden = YES;
    aimTabContainer.hidden = YES;
    settingTabContainer.hidden = YES;
    mainTabContainer.userInteractionEnabled = NO;
    aimTabContainer.userInteractionEnabled = NO;
    settingTabContainer.userInteractionEnabled = NO;
    
    for (UIView *sub in _sidebar.subviews) {
        if ([sub isKindOfClass:[UIView class]] && sub.tag >= 100 && sub.tag <= 102) {
            sub.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        }
    }
    UIView *activeBtn = [_sidebar viewWithTag:100 + tabIndex];
    activeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
    
    if (tabIndex == 0) { mainTabContainer.hidden = NO; mainTabContainer.userInteractionEnabled = YES; }
    if (tabIndex == 1) { aimTabContainer.hidden = NO; aimTabContainer.userInteractionEnabled = YES; }
    if (tabIndex == 2) { settingTabContainer.hidden = NO; settingTabContainer.userInteractionEnabled = YES; }
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
- (void)toggleAimbot:(CustomSwitch *)sender { isAimbot = sender.isOn; }

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
// Обработка touches напрямую — надёжнее чем gesture recognizers в HUD процессе
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // Передаём вверх — UISlider/UISwitch сами начнут обработку
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    espLog([NSString stringWithFormat:@"[MOVED] view=%@ class=%@", t.view, NSStringFromClass([t.view class])]);
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    UIView *hitView = touch.view;
    espLog([NSString stringWithFormat:@"[ENDED] view=%@ class=%@ tag=%ld", hitView, NSStringFromClass([hitView class]), (long)hitView.tag]);
    if (!hitView) {
        [super touchesEnded:touches withEvent:event];
        return;
    }
    
    // HUDSlider и UISwitch — не перехватываем, они обрабатывают touches сами
    if ([hitView isKindOfClass:[HUDSlider class]] ||
        [hitView isKindOfClass:[UISwitch class]] ||
        [hitView.superview isKindOfClass:[HUDSlider class]] ||
        [hitView.superview isKindOfClass:[UISwitch class]]) {
        [super touchesEnded:touches withEvent:event];
        return;
    }
    
    NSInteger tag = hitView.tag;
    
    // Таб кнопки: 100=Main, 101=AIM, 102=Setting
    if (tag >= 100 && tag <= 102) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToTab:tag - 100];
        });
        return;
    }
    
    // Close button X (tag=200) или его подпись (супerview имеет tag 200)
    UIView *checkView = hitView;
    while (checkView && checkView != menuContainer) {
        if (checkView.tag == 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideMenu];
            });
            return;
        }
        checkView = checkView.superview;
    }
    
    [super touchesEnded:touches withEvent:event];
}

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
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth");
    });
}

- (void)updateFrame {
    if (!self.window) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in self.drawingLayers) {
        [layer removeFromSuperlayer];
    }
    [self.drawingLayers removeAllObjects];
    
    // Draw FOV Circle
    if (isAimbot) {
        float screenX = self.bounds.size.width / 2;
        float screenY = self.bounds.size.height / 2;
        
        CAShapeLayer *circleLayer = [CAShapeLayer layer];
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(screenX, screenY) radius:aimFov startAngle:0 endAngle:2 * M_PI clockwise:YES];
        circleLayer.path = path.CGPath;
        circleLayer.fillColor = [UIColor clearColor].CGColor;
        circleLayer.strokeColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.5].CGColor;
        circleLayer.lineWidth = 1.0;
        [self.drawingLayers addObject:circleLayer];
    }
    
    [self renderESPToLayers:self.drawingLayers];
    
    for (CALayer *layer in self.drawingLayers) {
        [self.layer addSublayer:layer];
    }
    [CATransaction commit];
    [self setNeedsDisplay];
}

- (void)dealloc {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

static inline void DrawBoneLine(
    NSMutableArray<CALayer *> *layers,
    CGPoint p1,
    CGPoint p2,
    UIColor *color,
    CGFloat width
) {
    CGFloat dx = p2.x - p1.x;
    CGFloat dy = p2.y - p1.y;
    CGFloat len = sqrt(dx*dx + dy*dy);
    if (len < 2.0f) return;

    CALayer *line = [CALayer layer];
    line.backgroundColor = color.CGColor;
    line.bounds = CGRectMake(0, 0, len, width);
    line.position = p1;
    line.anchorPoint = CGPointMake(0, 0.5);
    line.transform = CATransform3DMakeRotation(atan2(dy, dx), 0, 0, 1);
    [layers addObject:line];
}


Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias, Vector3 myLoc){
    return Quaternion::LookRotation((targetLocation + Vector3(0, y_bias, 0)) - myLoc, Vector3(0, 1, 0));
}

void set_aim(uint64_t player, Quaternion rotation) {
    if (!isVaildPtr(player)) return;
    
    WriteAddr<Quaternion>(player + 0x53C, rotation);
}

bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    bool fireState = ReadAddr<bool>(player + 0x750);
    return fireState;
}


bool get_IsVisible(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    
    uint64_t visibleObj = ReadAddr<uint64_t>(player + 0x9B0);
    if (!isVaildPtr(visibleObj)) return false;

    int visibleFlags = ReadAddr<int>(visibleObj + 0x10); 
    return (visibleFlags & 0x1) == 0;
}


- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers {
    if (Moudule_Base == -1) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);
    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) return;

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) return;

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) return;
    
    uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + 0x318);
    Vector3 myLocation = getPositionExt(mainCameraTransform);
    
    uint64_t player = ReadAddr<uint64_t>(match + 0x120);
    uint64_t tValue = ReadAddr<uint64_t>(player + 0x28);
    int coutValue = ReadAddr<int>(tValue + 0x18);
    
    float *matrix = GetViewMatrix(camera);
    float viewWidth = self.bounds.size.width;
    float viewHeight = self.bounds.size.height;
    CGPoint screenCenter = CGPointMake(viewWidth / 2, viewHeight / 2);

    // Variables for Aimbot
    uint64_t bestTarget = 0;
    int minHP = 99999;
    bool isVis = false;
    bool isFire = false;
    
    for (int i = 0; i < coutValue; i++) {
        uint64_t PawnObject = ReadAddr<uint64_t>(tValue + 0x20 + 8 * i);
        if (!isVaildPtr(PawnObject)) continue;

        bool isLocalTeam = isLocalTeamMate(myPawnObject, PawnObject);
        if (isLocalTeam) continue;
        
        int CurHP = get_CurHP(PawnObject);
        if (CurHP <= 0) continue; 

        Vector3 HeadPos     = getPositionExt(getHead(PawnObject));
        isFire              = get_IsFiring(myPawnObject);
        
        float dis = Vector3::Distance(myLocation, HeadPos);
        if (dis > 400.0f) continue;

        
        if (isAimbot && dis <= aimDistance) {
            Vector3 w2sAim = WorldToScreen(HeadPos, matrix, viewWidth, viewHeight);

            float deltaX = w2sAim.x - screenCenter.x;
            float deltaY = w2sAim.y - screenCenter.y;
            float distanceFromCenter = sqrt(deltaX * deltaX + deltaY * deltaY);
            
            if (distanceFromCenter <= aimFov) {
                if (CurHP < minHP) {
                    minHP = CurHP;
                    
                    isVis = get_IsVisible(PawnObject);
                    bestTarget = PawnObject;
                }
            }
            
        }

        if (dis > 220.0f) continue; 

        Vector3 RightToePos = getPositionExt(getRightToeNode(PawnObject));
        Vector3 HipPos      = getPositionExt(getHip(PawnObject));
        Vector3 L_Ankle     = getPositionExt(getLeftAnkle(PawnObject));
        Vector3 R_Ankle     = getPositionExt(getRightAnkle(PawnObject));
        
        Vector3 L_Shoulder  = getPositionExt(getLeftShoulder(PawnObject));
        Vector3 R_Shoulder  = getPositionExt(getRightShoulder(PawnObject));
        Vector3 L_Elbow     = getPositionExt(getLeftElbow(PawnObject));
        Vector3 R_Elbow     = getPositionExt(getRightElbow(PawnObject));
        Vector3 L_Hand      = getPositionExt(getLeftHand(PawnObject));
        Vector3 R_Hand      = getPositionExt(getRightHand(PawnObject));

        Vector3 HeadTop     = HeadPos; HeadTop.y += 0.2f;
        Vector3 w2sHead     = WorldToScreen(HeadTop, matrix, viewWidth, viewHeight);
        Vector3 w2sToe      = WorldToScreen(RightToePos, matrix, viewWidth, viewHeight);

        Vector3 wHead       = WorldToScreen(HeadPos, matrix, viewWidth, viewHeight);
        Vector3 wHip        = WorldToScreen(HipPos, matrix, viewWidth, viewHeight);

        if (isBone) {
             Vector3 wLS = WorldToScreen(L_Shoulder, matrix, viewWidth, viewHeight);
             Vector3 wRS = WorldToScreen(R_Shoulder, matrix, viewWidth, viewHeight);
             Vector3 wLE = WorldToScreen(L_Elbow, matrix, viewWidth, viewHeight);
             Vector3 wRE = WorldToScreen(R_Elbow, matrix, viewWidth, viewHeight);
             Vector3 wLH = WorldToScreen(L_Hand, matrix, viewWidth, viewHeight);
             Vector3 wRH = WorldToScreen(R_Hand, matrix, viewWidth, viewHeight);
             Vector3 wLA = WorldToScreen(L_Ankle, matrix, viewWidth, viewHeight);
             Vector3 wRA = WorldToScreen(R_Ankle, matrix, viewWidth, viewHeight);

            UIColor *boneColor = [UIColor whiteColor];
            CGFloat boneWidth = 1.0f;

            DrawBoneLine(layers, CGPointMake(wHead.x, wHead.y), CGPointMake(wHip.x, wHip.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wLS.x, wLS.y), CGPointMake(wRS.x, wRS.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wLS.x, wLS.y), CGPointMake(wLE.x, wLE.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wLE.x, wLE.y), CGPointMake(wLH.x, wLH.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wRS.x, wRS.y), CGPointMake(wRE.x, wRE.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wRE.x, wRE.y), CGPointMake(wRH.x, wRH.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wHip.x, wHip.y), CGPointMake(wLA.x, wLA.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wHip.x, wHip.y), CGPointMake(wRA.x, wRA.y), boneColor, boneWidth);
        }

        float boxHeight = abs(w2sHead.y - w2sToe.y);
        float boxWidth = boxHeight * 0.5f;
        float x = w2sHead.x - boxWidth * 0.5f;
        float y = w2sHead.y;
        
        if (isBox) {
            CALayer *boxLayer = [CALayer layer];
            boxLayer.frame = CGRectMake(x, y, boxWidth, boxHeight);
            boxLayer.borderColor = [UIColor redColor].CGColor;
            boxLayer.borderWidth = 1.0;
            boxLayer.cornerRadius = 3.0;
            [layers addObject:boxLayer];
        }
        
        if (isName) {
            NSString *Name = GetNickName(PawnObject);
            if (Name.length > 0) {
                CATextLayer *nameLayer = [CATextLayer layer];
                nameLayer.string = Name;
                nameLayer.fontSize = 10;
                nameLayer.frame = CGRectMake(x - 20, y - 15, boxWidth + 40, 15);
                nameLayer.alignmentMode = kCAAlignmentCenter;
                nameLayer.foregroundColor = [UIColor greenColor].CGColor;
                [layers addObject:nameLayer];
            }
        }
        
        if (isHealth) {
            int MaxHP = get_MaxHP(PawnObject);
            if (MaxHP > 0) {
                float hpRatio = (float)CurHP / (float)MaxHP;
                if (hpRatio < 0) hpRatio = 0; if (hpRatio > 1) hpRatio = 1;
                
                float barWidth = 4.0;
                float barHeight = boxHeight;
                float filledHeight = barHeight * hpRatio;
                
                CALayer *bgBar = [CALayer layer];
                bgBar.frame = CGRectMake(x - barWidth - 2, y, barWidth, barHeight);
                bgBar.backgroundColor = [UIColor redColor].CGColor;
                [layers addObject:bgBar];
                
                CALayer *hpBar = [CALayer layer];
                hpBar.frame = CGRectMake(x - barWidth - 2, y + (barHeight - filledHeight), barWidth, filledHeight);
                hpBar.backgroundColor = [UIColor greenColor].CGColor;
                [layers addObject:hpBar];
            }
        }
        
        if (isDis) {
            CATextLayer *distLayer = [CATextLayer layer];
            distLayer.string = [NSString stringWithFormat:@"[%.0fm]", dis];
            distLayer.fontSize = 9;
            distLayer.frame = CGRectMake(x - 10, y + boxHeight + 2, boxWidth + 20, 12);
            distLayer.alignmentMode = kCAAlignmentCenter;
            distLayer.foregroundColor = [UIColor whiteColor].CGColor;
            [layers addObject:distLayer];
        }
    }

    if (isAimbot && isVaildPtr(bestTarget) && isFire) {
        Vector3 EnemyHead = getPositionExt(getHead(bestTarget));

        Quaternion targetLook = GetRotationToLocation(EnemyHead, 0.1f, myLocation);

        set_aim(myPawnObject, targetLook);
        
        
    }
}

@end
