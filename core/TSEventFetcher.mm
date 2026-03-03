#import <dlfcn.h>
#import <string.h>
#import "TSEventFetcher.h"
#import "CoreFoundation/CFRunLoop.h"
#import "UIApplication+Private.h"
#import "UIEvent+Private.h"
#import "UITouch-KIFAdditions.h"


static NSArray        *_safeTouchAry    = nil;
static NSMutableArray *_touchAry        = nil;
static NSMutableArray *_livingTouchAry  = nil;
static CFRunLoopSourceRef _source       = NULL;

static UITouch *toRemove       = nil;
static UITouch *toStationarify = nil;

// ---------------------------------------------------------------
// ФИКС МУЛЬТИТАЧ ЗАЛИПАНИЯ
// Когда игра отправляет несколько Ended/Cancelled подряд быстро,
// CFRunLoopSourceSignal может не успеть отработать каждый touch
// отдельно. Используем очередь pending ended touches и сбрасываем
// их все разом в одном событии.
// ---------------------------------------------------------------
static NSMutableArray *_pendingEndTouches = nil;

static void __TSEventFetcherCallback(void *info)
{
    static UIApplication *app = [UIApplication sharedApplication];
    UIEvent *event = [app _touchesEvent];
    [event _clearTouches];

    // Сначала отправляем все pending Ended touches разом
    if (_pendingEndTouches.count > 0) {
        for (UITouch *t in _pendingEndTouches) {
            [t setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
            [event _addTouch:t forDelayedDelivery:NO];
            [_livingTouchAry removeObjectIdenticalTo:t];
        }
        [_pendingEndTouches removeAllObjects];

        // Обновляем safeTouchAry после удаления
        CFTypeRef delayRelease = CFBridgingRetain(_safeTouchAry);
        _safeTouchAry = [[NSArray alloc] initWithArray:_livingTouchAry copyItems:NO];
        CFBridgingRelease(delayRelease);

        [app sendEvent:event];

        // Сбрасываем event и продолжаем с живыми touches
        event = [app _touchesEvent];
        [event _clearTouches];
    }

    NSArray *myAry = _safeTouchAry;
    for (UITouch *aTouch in myAry) {
        switch (aTouch.phase) {
            case UITouchPhaseEnded:
            case UITouchPhaseCancelled:
                toRemove = aTouch;
                break;
            case UITouchPhaseBegan:
                toStationarify = aTouch;
                break;
            default:
                break;
        }
        [event _addTouch:aTouch forDelayedDelivery:NO];
    }

    [app sendEvent:event];
}

@implementation TSEventFetcher

+ (void)load
{
    _livingTouchAry      = [[NSMutableArray alloc] init];
    _touchAry            = [[NSMutableArray alloc] init];
    _pendingEndTouches   = [[NSMutableArray alloc] init];

    for (NSInteger i = 0; i < 100; i++) {
        UITouch *touch = [[UITouch alloc] initTouch];
        [touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
        [_touchAry addObject:touch];
    }

    CFRunLoopSourceContext context;
    memset(&context, 0, sizeof(CFRunLoopSourceContext));
    context.perform = __TSEventFetcherCallback;

    _source = CFRunLoopSourceCreate(kCFAllocatorDefault, -2, &context);
    CFRunLoopRef loop = CFRunLoopGetMain();
    CFRunLoopAddSource(loop, _source, kCFRunLoopCommonModes);
}

+ (NSInteger)receiveAXEventID:(NSInteger)eventId
           atGlobalCoordinate:(CGPoint)coordinate
               withTouchPhase:(UITouchPhase)phase
                     inWindow:(UIWindow *)window
                       onView:(UIView *)view
{
    BOOL deleted  = NO;
    UITouch *touch = nil;
    BOOL needsCopy = NO;

    // ---------------------------------------------------------------
    // ФИКС: при Ended/Cancelled немедленно форсируем завершение touch
    // не дожидаясь следующего цикла runloop — это убирает залипание
    // при быстром мультитач (джойстик + второй палец одновременно)
    // ---------------------------------------------------------------
    if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
        eventId -= 1;
        if (eventId >= 0 && eventId < (NSInteger)_touchAry.count) {
            UITouch *endTouch = _touchAry[eventId];
            if ([_livingTouchAry containsObject:endTouch]) {
                // Ставим в pending очередь — все они уйдут разом в следующем callback
                if (![_pendingEndTouches containsObject:endTouch]) {
                    [endTouch setPhaseAndUpdateTimestamp:phase];
                    [_pendingEndTouches addObject:endTouch];
                }
                CFRunLoopSourceSignal(_source);
                CFRunLoopWakeUp(CFRunLoopGetMain());
                return deleted;
            }
        }
        return deleted;
    }

    if (toRemove != nil) {
        touch = toRemove;
        toRemove = nil;
        [_livingTouchAry removeObjectIdenticalTo:touch];
        deleted  = YES;
        needsCopy = YES;
    }

    if (toStationarify != nil) {
        touch = toStationarify;
        toStationarify = nil;
        if (touch.phase == UITouchPhaseBegan)
            [touch setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
    }

    eventId -= 1;

    touch = _touchAry[eventId];
    BOOL oldState = [_livingTouchAry containsObject:touch];
    BOOL newState = !oldState;

    if (newState) {
        // Новый touch
        touch = [[UITouch alloc] initAtPoint:coordinate inWindow:window onView:view];
        [_livingTouchAry addObject:touch];
        [_touchAry setObject:touch atIndexedSubscript:eventId];
        needsCopy = YES;
    } else {
        if (touch.phase == UITouchPhaseBegan && phase == UITouchPhaseMoved)
            return deleted;
        [touch setLocationInWindow:coordinate];
    }

    [touch setPhaseAndUpdateTimestamp:phase];

    if (needsCopy) {
        CFTypeRef delayRelease = CFBridgingRetain(_safeTouchAry);
        _safeTouchAry = [[NSArray alloc] initWithArray:_livingTouchAry copyItems:NO];
        CFBridgingRelease(delayRelease);
    }

    CFRunLoopSourceSignal(_source);
    // ДОБАВЛЕНО: явный wake — без него runloop может не среагировать
    // сразу при быстром мультитач (залипание на 1-2 сек)
    CFRunLoopWakeUp(CFRunLoopGetMain());
    return deleted;
}

@end
