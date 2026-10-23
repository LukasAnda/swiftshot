// watchOS no-boot capture. The watchOS SDK doesn't expose UIWindow, Metal or CARenderer, but the
// simulator runtime has them (watchOS' UIKit is private, not absent), so this declares the few
// methods it needs and uses them like the iOS agent's GPUCapture: a scene-less window, rendered
// with Core Animation's own renderer into a Metal texture, read back as a CGImage.

#if TARGET_OS_WATCH
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <objc/runtime.h>

typedef struct { NSUInteger x, y, z; } SSOrigin;
typedef struct { NSUInteger width, height, depth; } SSSize;
typedef struct { SSOrigin origin; SSSize size; } SSRegion;

@interface NSObject (SwiftshotWatchCapture)
// UIWindow / UIView
- (instancetype)initWithFrame:(CGRect)frame;
- (void)setRootViewController:(id)vc;
- (void)setHidden:(BOOL)hidden;
- (void)layoutIfNeeded;
- (id)layer;
// CALayer
- (BOOL)isGeometryFlipped;
- (id)delegate;
- (void)setNeedsDisplay;
- (id)contents;
- (NSArray *)sublayers;
- (void)setFrame:(CGRect)frame;
- (void)setGeometryFlipped:(BOOL)flipped;
- (void)addSublayer:(id)layer;
- (void)removeFromSuperlayer;
- (id)superlayer;
- (CGPoint)anchorPoint;
- (void)setAnchorPoint:(CGPoint)p;
- (CGPoint)position;
- (void)setPosition:(CGPoint)p;
- (CGAffineTransform)affineTransform;
- (void)setAffineTransform:(CGAffineTransform)t;
- (void)addSublayer:(id)layer;
- (void)removeFromSuperlayer;
- (id)superlayer;
- (CGPoint)anchorPoint; - (void)setAnchorPoint:(CGPoint)p;
- (CGPoint)position; - (void)setPosition:(CGPoint)p;
- (CGAffineTransform)affineTransform; - (void)setAffineTransform:(CGAffineTransform)t;
// Metal
- (id)newCommandQueue;
- (id)newTextureWithDescriptor:(id)descriptor;
- (id)commandBuffer;
- (void)commit;
- (void)waitUntilCompleted;
- (void)setUsage:(NSUInteger)usage;
- (void)setStorageMode:(NSUInteger)mode;
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)bpr fromRegion:(SSRegion)region mipmapLevel:(NSUInteger)level;
// CARenderer
- (void)setLayer:(id)layer;
- (void)setBounds:(CGRect)bounds;
- (void)beginFrameAtTime:(double)t timeStamp:(void *)ts;
- (void)addUpdateRect:(CGRect)r;
- (void)render;
- (void)endFrame;
@end

@interface NSObject (SwiftshotWatchCaptureClass)
+ (id)texture2DDescriptorWithPixelFormat:(NSUInteger)format width:(NSUInteger)w height:(NSUInteger)h mipmapped:(BOOL)mipmapped;
+ (id)rendererWithMTLTexture:(id)texture options:(NSDictionary *)options;
+ (void)flush;
@end

/// Without a booted watch no application object exists, but watchOS text layout asks it for
/// status-bar metrics. Creates the UIApplication subclass that provides them (UIKit registers the
/// first instance as the shared application). Returns its class name, or nil.
NSString *swiftshot_watch_make_application(void) {
    Class base = NSClassFromString(@"UIApplication");
    if (!base || [base performSelector:NSSelectorFromString(@"sharedApplication")]) return nil;
    void **global = (void **)dlsym(RTLD_DEFAULT, "UIApp");
    if (!global || *global) return nil;
    SEL metrics = NSSelectorFromString(@"defaultStatusBarLayoutMetrics");
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    Class found = Nil;
    for (unsigned i = 0; i < count && !found; i++) {
        for (Class c = class_getSuperclass(classes[i]); c; c = class_getSuperclass(c)) {
            if (c == base) { if (class_getInstanceMethod(classes[i], metrics)) found = classes[i]; break; }
        }
    }
    free(classes);
    if (!found) return nil;
    // Like UIApplicationMain: UIApp must point at the instance before -init (UIKit asserts it).
    id app = [found alloc];
    *global = (__bridge_retained void *)app;
    (void)[app init];
    return NSStringFromClass(found);
}

@interface NSObject (SwiftshotWatchView)
- (id)view;
- (CGRect)bounds;
@end

id swiftshot_watch_make_window(double width, double height) {
    Class cls = NSClassFromString(@"UIWindow");
    id window = cls ? [[cls alloc] initWithFrame:CGRectMake(0, 0, width, height)] : nil;
    // watchOS' UIWindow ignores the frame given to -initWithFrame: (it sizes itself from a scene).
    [window setFrame:CGRectMake(0, 0, width, height)];
    return window;
}

@interface NSObject (SwiftshotWatchFit)
- (CGSize)sizeThatFits:(CGSize)size;
@end

/// The preview's own size for `.sizeThatFits` previews: width of the device, height as needed.
CGSize swiftshot_watch_fitting_size(id controller, double width) {
    return [[controller view] sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
}

typedef struct { CGFloat top, left, bottom, right; } SSInsets;
@interface NSObject (SwiftshotWatchSafeArea)
- (void)setAdditionalSafeAreaInsets:(SSInsets)insets;
@end

void swiftshot_watch_set_safe_area(id controller, double top, double left, double bottom, double right) {
    [controller setAdditionalSafeAreaInsets:(SSInsets){top, left, bottom, right}];
}

void swiftshot_watch_resize(id window, double width, double height) {
    [window setFrame:CGRectMake(0, 0, width, height)];
}

void swiftshot_watch_show(id window, id controller) {
    [window setRootViewController:controller];
    [window setHidden:NO];
    [[controller view] setFrame:[window bounds]];
    [window layoutIfNeeded];
}

static void collect_image_layers(id layer, NSMutableArray *into) {
    if ([NSStringFromClass([layer class]) hasSuffix:@"ImageLayer"] && [layer contents]) [into addObject:layer];
    for (id sub in [layer sublayers]) collect_image_layers(sub, into);
}

// MARK: window server capture (as on iOS: Agent/FakeDisplay.c provides the display)

// The watchOS SDK has no IOSurface library to link; the runtime has the framework.
typedef void *SSSurface;
static size_t (*IOSurfaceGetWidth)(SSSurface), (*IOSurfaceGetHeight)(SSSurface), (*IOSurfaceGetBytesPerRow)(SSSurface);
static void *(*IOSurfaceGetBaseAddress)(SSSurface);
static int (*IOSurfaceLock)(SSSurface, uint32_t, uint32_t *), (*IOSurfaceUnlock)(SSSurface, uint32_t, uint32_t *);
static BOOL load_iosurface(void) {
    if (IOSurfaceGetWidth) return YES;
    void *h = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_NOW);
    if (!h) return NO;
    IOSurfaceGetWidth = dlsym(h, "IOSurfaceGetWidth"); IOSurfaceGetHeight = dlsym(h, "IOSurfaceGetHeight");
    IOSurfaceGetBytesPerRow = dlsym(h, "IOSurfaceGetBytesPerRow"); IOSurfaceGetBaseAddress = dlsym(h, "IOSurfaceGetBaseAddress");
    IOSurfaceLock = dlsym(h, "IOSurfaceLock"); IOSurfaceUnlock = dlsym(h, "IOSurfaceUnlock");
    return IOSurfaceGetWidth && IOSurfaceGetHeight && IOSurfaceGetBytesPerRow && IOSurfaceGetBaseAddress && IOSurfaceLock && IOSurfaceUnlock;
}

static id server_context, server_display;

static SSSurface next_frame(uint64_t *seen, NSUInteger w, NSUInteger h, double timeout) {
    SSSurface (*wait)(int, uint64_t, double, uint64_t *) = dlsym(RTLD_DEFAULT, "swiftshot_fb_wait");
    if (!wait) return NULL;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        uint64_t frame = 0;
        SSSurface s = wait(0, *seen, 0.004, &frame);
        if (s) {
            *seen = frame;
            if (IOSurfaceGetWidth(s) == w && IOSurfaceGetHeight(s) == h) return s;
            CFRelease(s);
        }
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    } while ([deadline timeIntervalSinceNow] > 0);
    return NULL;
}

/// Starts the window server and the context windows are captured through (before any UI exists:
/// with CA_FORCE_LOCAL_SERVER set, SwiftUI's display timing expects the local server to run).
BOOL swiftshot_watch_start_server(double width, double height) {
    if (server_context) return YES;
    if (!load_iosurface()) return NO;
    setenv("SWIFTSHOT_DISPLAYS", [NSString stringWithFormat:@"%lux%lu@326", (unsigned long)llround(width), (unsigned long)llround(height)].UTF8String, 1);
    id server = [NSClassFromString(@"CAWindowServer") performSelector:@selector(server)];
    server_display = [[server valueForKey:@"displays"] firstObject];
    id displayId = [server_display valueForKey:@"displayId"];
    if (!displayId) { fprintf(stderr, "[swiftshot] watch capture: no window server display\n"); return NO; }
    NSString *idKey = *(__unsafe_unretained NSString **)dlsym(RTLD_DEFAULT, "kCAContextDisplayId");
    NSString *displayableKey = *(__unsafe_unretained NSString **)dlsym(RTLD_DEFAULT, "kCAContextDisplayable");
    server_context = [NSClassFromString(@"CAContext") performSelector:@selector(remoteContextWithOptions:) withObject:@{idKey: displayId, displayableKey: @YES}];
    if (!server_context) { fprintf(stderr, "[swiftshot] watch capture: no remote context\n"); return NO; }
    // Shown watch windows get contexts on this display too; the capture context goes above them.
    [server_context setValue:@(1e6) forKey:@"level"];
    return YES;
}

/// The window composited by Core Animation's window server in this process (CA_FORCE_LOCAL_SERVER),
/// as backboardd composites a watch's screen: a CGImage (+1) of the presented framebuffer, or NULL.
CGImageRef swiftshot_watch_server_capture(id window, double width, double height, double scale) {
    NSUInteger w = (NSUInteger)llround(width * scale), h = (NSUInteger)llround(height * scale);
    if (!load_iosurface()) { fprintf(stderr, "[swiftshot] watch capture: no IOSurface\n"); return NULL; }
    if (!swiftshot_watch_start_server(w, h)) return NULL;
    bool (*resize)(int, unsigned, unsigned) = dlsym(RTLD_DEFAULT, "swiftshot_fb_resize");
    if (!resize || !resize(0, (unsigned)w, (unsigned)h)) { fprintf(stderr, "[swiftshot] watch capture: cannot resize the display\n"); return NULL; }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while ([deadline timeIntervalSinceNow] > 0) {
        CGRect b = CGRectZero;
        [(NSValue *)[server_display valueForKey:@"bounds"] getValue:&b size:sizeof b];
        if ((NSUInteger)b.size.width == w && (NSUInteger)b.size.height == h) break;
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    }
    id layer = [window layer], superlayer = [layer superlayer];
    CGPoint anchor = [layer anchorPoint], position = [layer position];
    CGAffineTransform transform = [layer affineTransform];
    id root = [NSClassFromString(@"CALayer") new];
    [root setFrame:CGRectMake(0, 0, w, h)];
    CGColorRef black = CGColorCreateGenericGray(0, 1);
    [root setValue:(__bridge id)black forKey:@"backgroundColor"];   // the watch's own backdrop
    CGColorRelease(black);
    [root addSublayer:layer];
    [layer setAnchorPoint:CGPointZero]; [layer setPosition:CGPointZero];
    [layer setAffineTransform:CGAffineTransformMakeScale(scale, scale)];
    SSSurface surface = NULL;
    // Shown once first (materials settle on what's composited under them), then captured once
    // the server goes idle.
    for (int pass = 0; pass < 2; pass++) {
        uint64_t seen = 0;
        SSSurface (*wait)(int, uint64_t, double, uint64_t *) = dlsym(RTLD_DEFAULT, "swiftshot_fb_wait");
        SSSurface cur = wait ? wait(0, UINT64_MAX - 1, 0, &seen) : NULL;
        if (cur) CFRelease(cur);
        [server_context setValue:root forKey:@"layer"];
        [NSClassFromString(@"CATransaction") flush];
        NSDate *shown = [NSDate date];
        SSSurface s = next_frame(&seen, w, h, 20);   // seconds on a CI VM's GPU (shaders compiling)
        // Idle: no new frame for three gaps of half the first frame's latency (slow CI GPUs).
        double gap = MAX(0.016, -[shown timeIntervalSinceNow] * 0.5);
        int quiet = 0;
        NSDate *idle = [NSDate dateWithTimeIntervalSinceNow:MAX(1, gap * 10)];
        while (s && quiet < 3 && [idle timeIntervalSinceNow] > 0) {
            SSSurface n = next_frame(&seen, w, h, gap);
            if (n) { CFRelease(s); s = n; quiet = 0; } else quiet++;
        }
        if (pass == 1) surface = s; else if (s) CFRelease(s);
        [server_context setValue:nil forKey:@"layer"];
        [NSClassFromString(@"CATransaction") flush];
    }
    [layer removeFromSuperlayer];
    [layer setAffineTransform:transform]; [layer setAnchorPoint:anchor]; [layer setPosition:position];
    if (superlayer) [superlayer addSublayer:layer];
    if (!surface) { fprintf(stderr, "[swiftshot] watch capture: no frame\n"); return NULL; }
    IOSurfaceLock(surface, 1, NULL);
    size_t stride = IOSurfaceGetBytesPerRow(surface);
    void *bytes = malloc(w * h * 4);
    for (NSUInteger y = 0; y < h; y++) memcpy((char *)bytes + y * w * 4, (char *)IOSurfaceGetBaseAddress(surface) + y * stride, w * 4);
    IOSurfaceUnlock(surface, 1, NULL);
    CFRelease(surface);
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(bytes, w, h, 8, w * 4, srgb, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGImageRef image = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    if (ctx) CGContextRelease(ctx);
    CGColorSpaceRelease(srgb);
    free(bytes);
    return image;
}

/// Renders the window's layer tree at `scale` and returns a CGImage (+1), or NULL.
CGImageRef swiftshot_watch_capture(id window, double width, double height, double scale) {
    static id device, queue;
    if (!device) {
        dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
        id (*create)(void) = (id (*)(void))dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
        device = create ? create() : nil;
        queue = [device newCommandQueue];
    }
    Class rendererClass = NSClassFromString(@"CARenderer"), layerClass = NSClassFromString(@"CALayer");
    if (!device || !queue || !rendererClass) return NULL;
    NSUInteger w = (NSUInteger)llround(width * scale), h = (NSUInteger)llround(height * scale);
    id desc = [NSClassFromString(@"MTLTextureDescriptor") texture2DDescriptorWithPixelFormat:80 /* BGRA8Unorm */ width:w height:h mipmapped:NO];
    [desc setUsage:5 /* renderTarget | shaderRead */];
    [desc setStorageMode:0 /* shared */];
    id texture = [device newTextureWithDescriptor:desc];
    if (!texture) return NULL;

    // The window's layer under an unflipped, pixel-sized root (watchOS layers, unlike iOS ones,
    // expect an unflipped parent).
    id layer = [window layer];
    id superlayer = [layer superlayer];
    CGPoint anchor = [layer anchorPoint], position = [layer position];
    CGAffineTransform transform = [layer affineTransform];
    id root = [layerClass new];
    [root setFrame:CGRectMake(0, 0, w, h)];
    [root setGeometryFlipped:NO];

    // SwiftUI's image layers (SF Symbols) carry bitmaps rasterized with the same inverted
    // orientation as the drawn backing stores; mirror them in place for the capture.
    NSMutableArray *images = [NSMutableArray array], *transforms = [NSMutableArray array];
    collect_image_layers(layer, images);
    for (id image in images) {
        CGAffineTransform t = [image affineTransform];
        [transforms addObject:[NSValue valueWithBytes:&t objCType:@encode(CGAffineTransform)]];
        // Mirror about the bounds' horizontal centre line (SwiftUI layers' anchor isn't centred).
        CGFloat centre = (0.5 - [image anchorPoint].y) * CGRectGetHeight([image bounds]);
        [image setAffineTransform:CGAffineTransformConcat(CGAffineTransformMake(1, 0, 0, -1, 0, 2 * centre), t)];
    }

    [root addSublayer:layer];
    [layer setAnchorPoint:CGPointZero];
    [layer setPosition:CGPointZero];
    [layer setAffineTransform:CGAffineTransformMakeScale(scale, scale)];

    // Backing stores were drawn for the window's own tree; redraw them for this one so their
    // orientation matches the capture root (otherwise text comes out upside down).
    NSString *queueKey = *(__unsafe_unretained NSString **)dlsym(RTLD_DEFAULT, "kCARendererMetalCommandQueue");
    id renderer = [rendererClass rendererWithMTLTexture:texture options:@{queueKey: queue}];
    [renderer setLayer:root];
    [renderer setBounds:CGRectMake(0, 0, w, h)];
    [NSClassFromString(@"CATransaction") flush];
    [renderer beginFrameAtTime:CFAbsoluteTimeGetCurrent() timeStamp:NULL];
    [renderer addUpdateRect:CGRectMake(0, 0, w, h)];
    [renderer render];
    [renderer endFrame];
    id done = [queue commandBuffer]; [done commit]; [done waitUntilCompleted];

    [layer removeFromSuperlayer];
    [layer setAffineTransform:transform]; [layer setAnchorPoint:anchor]; [layer setPosition:position];
    if (superlayer) [superlayer addSublayer:layer];
    for (NSUInteger i = 0; i < images.count; i++) {
        CGAffineTransform t; [transforms[i] getValue:&t];
        [images[i] setAffineTransform:t];
    }

    void *bytes = malloc(w * h * 4);
    [texture getBytes:bytes bytesPerRow:w * 4 fromRegion:(SSRegion){{0, 0, 0}, {w, h, 1}} mipmapLevel:0];
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(bytes, w, h, 8, w * 4, srgb, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGImageRef raw = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    CGImageRef image = raw;
    if (ctx) CGContextRelease(ctx);
    CGColorSpaceRelease(srgb);
    free(bytes);
    return image;
}
#endif
