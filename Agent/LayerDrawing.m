// Shared by the iOS and watchOS agents (no-boot mode).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

@interface NSObject (SwiftshotLayerDrawing)
- (CGRect)bounds;
@end

/// Once the process has a UIApplication, UIKit's text and drawing layers expect the opposite
/// context orientation from what Core Animation hands -drawInContext: without a render server, so
/// their text came out upside down inside correctly placed layers. Flip the context around every
/// -drawInContext: of CALayer and of each subclass that overrides it.
void swiftshot_flip_layer_drawing(void) {
    Class base = NSClassFromString(@"CALayer");
    SEL sel = @selector(drawInContext:);
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned i = 0; i < count; i++) {
        Class cls = classes[i];
        BOOL isLayer = NO;
        for (Class c = cls; c; c = class_getSuperclass(c)) if (c == base) { isLayer = YES; break; }
        if (!isLayer) continue;
        unsigned n = 0;
        Method *methods = class_copyMethodList(cls, &n);
        for (unsigned j = 0; j < n; j++) {
            if (method_getName(methods[j]) != sel) continue;
            typedef void (*Draw)(id, SEL, CGContextRef);
            Draw original = (Draw)method_getImplementation(methods[j]);
            method_setImplementation(methods[j], imp_implementationWithBlock(^(id layer, CGContextRef ctx) {
                // Subclass overrides call super: flip once, at the outermost call.
                static __thread int depth = 0;
                if (depth > 0) { original(layer, sel, ctx); return; }
                depth++;
                CGRect b = [layer bounds];
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, 0, CGRectGetMinY(b) + CGRectGetMaxY(b));
                CGContextScaleCTM(ctx, 1, -1);
                original(layer, sel, ctx);
                CGContextRestoreGState(ctx);
                depth--;
            }));
        }
        free(methods);
    }
    free(classes);
}

/// UIKit's scene corner safe areas (iOS 27.1: the iPhone Duo's status bar rail takes the
/// top-right corner) as a booted scene resolves them, for device windows (no-boot). Four CGSizes,
/// returned by value, which a Swift block cannot do; the values follow the rendered device.
typedef struct { CGSize corners[4]; } SwiftshotCornerInsets;
static SwiftshotCornerInsets swiftshot_corners;
static BOOL swiftshot_corners_set;

void swiftshot_set_corner_insets(const double *values) {
    swiftshot_corners_set = values != NULL;
    if (values) for (int i = 0; i < 4; i++) swiftshot_corners.corners[i] = CGSizeMake(values[2 * i], values[2 * i + 1]);
}

void swiftshot_install_corner_insets(void) {
    Class window = NSClassFromString(@"UIWindow"), scene = NSClassFromString(@"UIWindowScene"), device = NSClassFromString(@"SwiftshotAgent.DeviceWindow");
    if (!device) return;
    typedef SwiftshotCornerInsets (*Get0)(id, SEL);
    typedef SwiftshotCornerInsets (*Get1)(id, SEL, NSInteger);
    typedef SwiftshotCornerInsets (*Get2)(id, SEL, NSInteger, NSInteger);
    typedef SwiftshotCornerInsets (*Get3)(id, SEL, NSInteger, BOOL, NSInteger);
    // Windows: the device window's (scene) corner insets.
    for (NSString *name in @[@"_sceneSafeAreaCornerInsets", @"_normalizedCornerSafeAreaInsets", @"_safeAreaCornerInsets"]) {
        SEL sel = NSSelectorFromString(name);
        Method m = class_getInstanceMethod(window, sel);
        if (!m) continue;
        Get0 original = (Get0)method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^SwiftshotCornerInsets(id w) {
            return swiftshot_corners_set && [w isKindOfClass:device] ? swiftshot_corners : original(w, sel);
        }));
    }
    SEL axisSel = NSSelectorFromString(@"_sceneSafeAreaCornerInsetsForStatusBarAxis:statusBarVisibility:");
    Method axis = class_getInstanceMethod(window, axisSel);
    if (axis) {
        Get2 original = (Get2)method_getImplementation(axis);
        method_setImplementation(axis, imp_implementationWithBlock(^SwiftshotCornerInsets(id w, NSInteger a, NSInteger v) {
            return swiftshot_corners_set && [w isKindOfClass:device] ? swiftshot_corners : original(w, axisSel, a, v);
        }));
    }
    // The (only) window scene: portrait values, as the rendered device's booted scene resolves them.
    SEL s0 = NSSelectorFromString(@"_safeAreaCornerInsets"), s1 = NSSelectorFromString(@"_safeAreaCornerInsetsForInterfaceOrientation:"),
        s2 = NSSelectorFromString(@"_safeAreaCornerInsetsForInterfaceOrientation:statusBarHidden:"), s3 = NSSelectorFromString(@"_safeAreaCornerInsetsForInterfaceOrientation:statusBarHidden:statusBarAxis:");
    Method m0 = class_getInstanceMethod(scene, s0), m1 = class_getInstanceMethod(scene, s1), m2 = class_getInstanceMethod(scene, s2), m3 = class_getInstanceMethod(scene, s3);
    if (m0) { Get0 o = (Get0)method_getImplementation(m0); method_setImplementation(m0, imp_implementationWithBlock(^SwiftshotCornerInsets(id x) { return swiftshot_corners_set ? swiftshot_corners : o(x, s0); })); }
    if (m1) { Get1 o = (Get1)method_getImplementation(m1); method_setImplementation(m1, imp_implementationWithBlock(^SwiftshotCornerInsets(id x, NSInteger r) { return swiftshot_corners_set && r <= 2 ? swiftshot_corners : o(x, s1, r); })); }
    if (m2) { typedef SwiftshotCornerInsets (*G)(id, SEL, NSInteger, BOOL); G o = (G)method_getImplementation(m2); method_setImplementation(m2, imp_implementationWithBlock(^SwiftshotCornerInsets(id x, NSInteger r, BOOL h) { return swiftshot_corners_set && r <= 2 ? swiftshot_corners : o(x, s2, r, h); })); }
    if (m3) { Get3 o = (Get3)method_getImplementation(m3); method_setImplementation(m3, imp_implementationWithBlock(^SwiftshotCornerInsets(id x, NSInteger r, BOOL h, NSInteger a) { return swiftshot_corners_set && r <= 2 ? swiftshot_corners : o(x, s3, r, h, a); })); }
}
