// Display links without a display. A no-boot process has no render server that answers for
// displays, so +[CADisplay mainDisplay] would wait forever and a CADisplayLink would never fire.
// Apps that draw from a display link (Compose Multiplatform's Metal views, game loops) get one
// driven by a run-loop timer at 60 Hz instead, with CADisplayLink's API.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface SwiftshotDisplayLink : NSObject
@property(nonatomic, strong) id target;   // retained until invalidated, as CADisplayLink does
@property(nonatomic) SEL selector;
@property(nonatomic, getter=isPaused) BOOL paused;
@property(nonatomic) CFTimeInterval timestamp;
@property(nonatomic) CFTimeInterval targetTimestamp;
@property(nonatomic, readonly) CFTimeInterval duration;
@property(nonatomic) NSInteger preferredFramesPerSecond;
@property(nonatomic) NSInteger frameInterval;
@property(nonatomic) CAFrameRateRange preferredFrameRateRange;
@property(nonatomic, strong) NSTimer *timer;
@end

static BOOL debugLinks(void) { return getenv("SWIFTSHOT_DEBUG_LINKS") != NULL; }

// Every link that is on a run loop, for swiftshot_display_links_running.
static NSHashTable<SwiftshotDisplayLink *> *links(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

@implementation SwiftshotDisplayLink
- (CFTimeInterval)duration { return 1.0 / 60.0; }
- (void)setPaused:(BOOL)paused {
    if (debugLinks() && paused != _paused) fprintf(stderr, "[swiftshot] link %p paused=%d\n", (__bridge void *)self, paused);
    _paused = paused;
}
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode {
    if (debugLinks()) fprintf(stderr, "[swiftshot] link %p added (%s) target %s main runloop %d main thread %d\n", (__bridge void *)self, mode.UTF8String, object_getClassName(self.target), runloop == NSRunLoop.mainRunLoop, NSThread.isMainThread);
    if (!self.timer) {
        __weak SwiftshotDisplayLink *weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    }
    [runloop addTimer:self.timer forMode:mode];
    @synchronized (links()) { [links() addObject:self]; }
}
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode {}
- (void)invalidate {
    if (debugLinks()) fprintf(stderr, "[swiftshot] link %p invalidated\n", (__bridge void *)self);
    [self.timer invalidate];
    self.timer = nil;
    self.target = nil;
    @synchronized (links()) { [links() removeObject:self]; }
}
- (void)tick {
    if (self.paused) return;
    id target = self.target;
    if (!target) return;
    static int ticks = 0;
    if (debugLinks()) fprintf(stderr, "[swiftshot] link %p tick %d\n", (__bridge void *)self, ++ticks);
    self.timestamp = CACurrentMediaTime();
    self.targetTimestamp = self.timestamp + self.duration;
    ((void (*)(id, SEL, id))objc_msgSend)(target, self.selector, self);
}
@end

// Links that still want frames: an app that draws from a display link pauses it when it has
// nothing more to draw (Compose once its animations have finished).
int swiftshot_display_links_running(void) {
    int n = 0;
    @synchronized (links()) {
        for (SwiftshotDisplayLink *link in links()) if (!link.paused && link.timer && link.target) n++;
    }
    return n;
}

void swiftshot_install_display_link(void) {
    Class display = NSClassFromString(@"CADisplay");
    Method main = display ? class_getClassMethod(display, NSSelectorFromString(@"mainDisplay")) : NULL;
    if (main) method_setImplementation(main, imp_implementationWithBlock(^id(id cls) { return nil; }));
    Method make = class_getClassMethod([CADisplayLink class], @selector(displayLinkWithTarget:selector:));
    if (make) method_setImplementation(make, imp_implementationWithBlock(^id(id cls, id target, SEL selector) {
        SwiftshotDisplayLink *link = [SwiftshotDisplayLink new];
        link.target = target;
        link.selector = selector;
        return link;
    }));
}

// Without a simulator there is no backboardd: making a window key (Compose's dialogs and sheets
// do, to move focus) starts keyboard event deferring through BackBoard, which fails here. Which
// window is key doesn't change what is drawn, so making one key does nothing.
void swiftshot_install_no_key_window(void) {
    Method make = class_getInstanceMethod([UIWindow class], @selector(makeKeyWindow));
    if (make) method_setImplementation(make, imp_implementationWithBlock(^(id window) {}));
    if (getenv("SWIFTSHOT_DEBUG")) fprintf(stderr, "[swiftshot] key window patch: %s\n", make ? "applied" : "method not found");
}
