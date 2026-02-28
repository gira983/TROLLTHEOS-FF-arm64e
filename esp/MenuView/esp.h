#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../lib/GameLogic.h"

struct ESPBox {
    Vector3 pos;
    CGFloat width;
    CGFloat height;
};
@interface MenuView : UIView

- (instancetype)initWithFrame:(CGRect)frame;
- (void)hideMenu;
- (void)showMenu;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
- (void)layoutSubviews;
- (void)centerMenu;

@end
