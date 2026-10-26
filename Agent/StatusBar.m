// iOS agent: the system status bar, drawn with the status bar view SpringBoard shows, from a data
// description (9:41, full signal, charged battery). On by default; --no-status-bar leaves it out.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

void swiftshot_apply_status_bar_data(UIView *bar);
UIView *swiftshot_make_status_bar_spec(NSDictionary *spec, CGRect frame, UIScreen *screen);

/// UIScreen._exclusionArea (the Dynamic Island's rect, which the status bar lays out around), as
/// the rendered device's booted screen reports it. CGRectNull: none.
static CGRect swiftshot_exclusion = {{INFINITY, INFINITY}, {0, 0}};
/// What SpringBoard's status bar avoids (its avoidance frame): the scene's camera region where the
/// device has one (iPhone Duo), else the exclusion area. CGRectNull: none.
static CGRect swiftshot_avoidance = {{INFINITY, INFINITY}, {0, 0}};

/// Applies the bar's data; its items are built for the window it is in.
void swiftshot_apply_status_bar_data(UIView *bar) {
    id data = objc_getAssociatedObject(bar, @selector(swiftshot_apply_status_bar_data));
    if (data) ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"updateWithData:"), data);
    [bar layoutIfNeeded];
    // The avoidance frame after the data, as SpringBoard's long-lived bar gets it: its visual
    // provider (made with the items) only then turns it into the cutout guide. Set before, the
    // cutout came from the screen's exclusion area, mirrored in a right-to-left bar (iPhone 17
    // on an Arabic simulator: the cutout, and with it the battery, Wi-Fi and signal, 1/3 pt off).
    NSValue *avoidance = objc_getAssociatedObject(bar, @selector(swiftshot_make_status_bar_spec));
    if (avoidance) {
        ((void (*)(id, SEL, CGRect))objc_msgSend)(bar, NSSelectorFromString(@"setAvoidanceFrame:"), avoidance.CGRectValue);
        [bar layoutIfNeeded];
    }
}

/// _UIStatusBarData from a description: {entryKey: {"class": entry class, property: value…}}.
/// Entries listed are enabled.
id swiftshot_status_bar_data_from_spec(NSDictionary *entries, NSString *dataClass) {
    id data = [NSClassFromString(dataClass ?: @"_UIStatusBarData") new];
    for (NSString *key in entries) {
        // Entries this runtime's data class doesn't have (added in a later iOS) are left out.
        if (![data respondsToSelector:NSSelectorFromString(key)]) continue;
        NSDictionary *e = entries[key];
        Class cls = NSClassFromString(e[@"class"] ?: @"_UIStatusBarDataEntry");
        id entry = [cls new];
        [entry setValue:@YES forKey:@"enabled"];
        for (NSString *k in e) if (![k isEqualToString:@"class"]) [entry setValue:e[k] forKey:k];
        [data setValue:entry forKey:key];
    }
    return data;
}

UIView *swiftshot_make_status_bar_spec(NSDictionary *spec, CGRect frame, UIScreen *screen) {
    // SpringBoard's own status bar (SystemStatusUI's STUIStatusBar) when the spec names it.
    if (spec[@"framework"]) dlopen([spec[@"framework"] fileSystemRepresentation], RTLD_NOW);
    Class cls = NSClassFromString(spec[@"barClass"] ?: @"_UIStatusBar");
    id data = swiftshot_status_bar_data_from_spec(spec[@"entries"], spec[@"dataClass"]);
    if (!cls || !data) return nil;
    UIView *bar = ((id (*)(id, SEL, NSInteger))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithStyle:"), [spec[@"style"] integerValue]);
    if ([bar respondsToSelector:NSSelectorFromString(@"setTargetScreen:")]) ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"setTargetScreen:"), screen);
    if (spec[@"provider"] && [bar respondsToSelector:NSSelectorFromString(@"_setVisualProviderClassName:")]) ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"_setVisualProviderClassName:"), spec[@"provider"]);
    bar.frame = frame;
    for (NSString *k in spec[@"barProperties"]) [bar setValue:spec[@"barProperties"][k] forKey:k];
    // The island (not a notch, which starts at the top edge), which SpringBoard's bar lays its
    // items out around: set once the data has built the items (swiftshot_apply_status_bar_data).
    if ([spec[@"avoidExclusionArea"] boolValue] && !CGRectIsNull(swiftshot_avoidance) && swiftshot_avoidance.origin.y > 0 && [bar respondsToSelector:NSSelectorFromString(@"setAvoidanceFrame:")])
        objc_setAssociatedObject(bar, @selector(swiftshot_make_status_bar_spec), [NSValue valueWithCGRect:swiftshot_avoidance], OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(bar, @selector(swiftshot_apply_status_bar_data), data, OBJC_ASSOCIATION_RETAIN);
    return bar;
}


void swiftshot_set_exclusion_rect(CGRect rect, CGRect avoidance) { swiftshot_exclusion = rect; swiftshot_avoidance = avoidance; }

void swiftshot_install_exclusion_area(void) {
    SEL sel = NSSelectorFromString(@"_exclusionArea");
    Method m = class_getInstanceMethod(UIScreen.class, sel);
    Class shape = NSClassFromString(@"UISDisplaySingleRectShape");
    if (!m || !shape) return;
    id (*original)(id, SEL) = (id (*)(id, SEL))method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^id(id screen) {
        if (CGRectIsNull(swiftshot_exclusion)) return original(screen, sel);
        return ((id (*)(id, SEL, CGRect))objc_msgSend)([shape alloc], NSSelectorFromString(@"initWithRect:"), swiftshot_exclusion);
    }));
}
