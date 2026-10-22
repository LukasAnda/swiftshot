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
