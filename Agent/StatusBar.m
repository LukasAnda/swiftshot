// iOS agent (no-boot, experimental — SWIFTSHOT_STATUSBAR=<spec.json>): the system status bar,
// drawn with UIKit's own status bar view (the one SpringBoard shows) from a data description.
// Not on by default: the Dynamic Island layouts still need the screen's sensor-region geometry.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

void swiftshot_apply_status_bar_data(UIView *bar);

/// Applies the bar's data; its items are built for the window it is in.
void swiftshot_apply_status_bar_data(UIView *bar) {
    id data = objc_getAssociatedObject(bar, @selector(swiftshot_apply_status_bar_data));
    if (data) ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"updateWithData:"), data);
    [bar layoutIfNeeded];
}

/// _UIStatusBarData from a description: {entryKey: {"class": entry class, property: value…}}.
/// Entries listed are enabled.
id swiftshot_status_bar_data_from_spec(NSDictionary *entries) {
    id data = [NSClassFromString(@"_UIStatusBarData") new];
    for (NSString *key in entries) {
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
    Class cls = NSClassFromString(@"_UIStatusBar");
    id data = swiftshot_status_bar_data_from_spec(spec[@"entries"]);
    if (!cls || !data) return nil;
    UIView *bar = ((id (*)(id, SEL, NSInteger))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithStyle:"), [spec[@"style"] integerValue]);
    if ([bar respondsToSelector:NSSelectorFromString(@"setTargetScreen:")]) ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"setTargetScreen:"), screen);
    if (spec[@"provider"] && [bar respondsToSelector:NSSelectorFromString(@"_setVisualProviderClassName:")]) ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"_setVisualProviderClassName:"), spec[@"provider"]);
    bar.frame = frame;
    objc_setAssociatedObject(bar, @selector(swiftshot_apply_status_bar_data), data, OBJC_ASSOCIATION_RETAIN);
    return bar;
}
