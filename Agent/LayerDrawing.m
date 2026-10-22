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
