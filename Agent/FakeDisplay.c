// Stand-in for the simulator's framebuffer service (SimFramebufferClient), so Core Animation's own
// window server (CAWindowServer, the code backboardd composites the screen with) runs inside a
// no-boot process. A booted simulator gets its displays from CoreSimulator's SimRenderServer; here
// the agent describes them (SWIFTSHOT_DISPLAYS, one per device) and every frame the server swaps
// is kept, so a capture is the composited framebuffer exactly as a device would show it.
//
// Only what QuartzCore calls is provided (SFBConnection*/SFBDisplay*/SFBSwapchain*), with the
// layouts a booted simulator reports: modes are 35-byte records {id, width, height, scale, 1,
// pixel format, colorspace, refresh ×100, preferred, 1, 1}.

#include <CoreFoundation/CoreFoundation.h>
typedef struct __IOSurface *IOSurfaceRef;  // opaque here (the watchOS SDK has no IOSurface headers)
#include <Block.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdlib.h>
#include <string.h>

#pragma pack(push, 1)
typedef struct { uint32_t id, width, height, scale, one, format, colorspace, refresh; uint8_t preferred, a, b; } ss_mode;
#pragma pack(pop)
_Static_assert(sizeof(ss_mode) == 35, "SFB mode record");

typedef struct { double width, height; } ss_size;
typedef void (^ss_present_block)(void *swapchain, void *error, uint64_t presented, uint64_t displayed, void *context);

typedef struct {
    int index;
    ss_mode mode;
    uint32_t pitch;
    CFStringRef name, deviceName, uid;
} ss_display;

typedef struct {
    int display;
    IOSurfaceRef pending;
    void *context;
    ss_present_block block;
    dispatch_queue_t queue;
} ss_swapchain;

#define SS_MAX_DISPLAYS 16
static CFMutableArrayRef displays;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t presented = PTHREAD_COND_INITIALIZER;
static uint64_t frames[SS_MAX_DISPLAYS];
static IOSurfaceRef latest[SS_MAX_DISPLAYS];

#define TRACE(...) do { if (getenv("SWIFTSHOT_FB_TRACE")) fprintf(stderr, "[swiftshot] fb: " __VA_ARGS__); } while (0)

static void *data_of(const void *object) { return object ? CFDataGetMutableBytePtr((CFMutableDataRef)object) : NULL; }
static CFMutableDataRef new_object(size_t size) {
    CFMutableDataRef d = CFDataCreateMutable(NULL, 0);
    CFDataSetLength(d, size);
    return d;
}

// SWIFTSHOT_DISPLAYS: "1206x2622@460;1320x2868@460" (pixels, dot pitch); the first one is "LCD".
static void load_displays(void) {
    if (displays) return;
    displays = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    const char *spec = getenv("SWIFTSHOT_DISPLAYS");
    if (!spec || !*spec) spec = "1206x2622@460";
    char *copy = strdup(spec), *save = NULL;
    int index = 0;
    for (char *item = strtok_r(copy, ";", &save); item && index < SS_MAX_DISPLAYS; item = strtok_r(NULL, ";", &save), index++) {
        unsigned w = 0, h = 0, pitch = 460;
        if (sscanf(item, "%ux%u@%u", &w, &h, &pitch) < 2) continue;
        CFMutableDataRef object = new_object(sizeof(ss_display));
        ss_display *d = data_of(object);
        d->index = index;
        d->mode = (ss_mode){ .id = index + 1, .width = w, .height = h, .scale = 3, .one = 1, .format = 'BGRA',
                             .colorspace = getenv("SWIFTSHOT_FB_COLORSPACE") ? (uint32_t)atoi(getenv("SWIFTSHOT_FB_COLORSPACE")) : 2, .refresh = 6000, .preferred = 1, .a = 1, .b = 1 };
        d->pitch = pitch;
        d->name = index == 0 ? CFSTR("LCD") : CFStringCreateWithFormat(NULL, NULL, CFSTR("LCD-%d"), index);
        d->deviceName = index == 0 ? CFSTR("primary") : CFStringCreateWithFormat(NULL, NULL, CFSTR("primary-%d"), index);
        d->uid = CFStringCreateWithFormat(NULL, NULL, CFSTR("00000000-0000-0000-0000-%012d"), index + 1);
        CFArrayAppendValue(displays, object);
        CFRelease(object);
    }
    free(copy);
}

// MARK: connection

static void *ss_connection_create(CFAllocatorRef allocator, CFStringRef label) { return new_object(8); }
static bool ss_connection_connect(void *connection, CFErrorRef *error) { load_displays(); return true; }
static CFArrayRef ss_connection_copy_displays(void *connection, CFErrorRef *error) {
    load_displays();
    return CFArrayCreateCopy(NULL, displays);
}
static void *ss_connection_copy_display_by_uid(void *connection, CFStringRef uid, CFErrorRef *error) {
    load_displays();
    for (CFIndex i = 0; i < CFArrayGetCount(displays); i++) {
        const void *object = CFArrayGetValueAtIndex(displays, i);
        ss_display *d = data_of(object);
        // QuartzCore asks by the name it keyed the display with (the device name).
        if (CFEqual(d->uid, uid) || CFEqual(d->deviceName, uid) || CFEqual(d->name, uid)) return (void *)CFRetain(object);
    }
    if (getenv("SWIFTSHOT_FB_TRACE")) CFShow(uid);
    return NULL;
}
static dispatch_queue_t updated_queue;
static void (^updated_handler)(void *display);
static void ss_connection_set_handler(void *connection, dispatch_queue_t queue, void (^block)(void *)) {
    updated_queue = queue;
    updated_handler = block ? (void (^)(void *))_Block_copy(block) : NULL;
}

// MARK: display

static uint32_t ss_display_get_type(void *d) { return 0; }
static CFStringRef ss_display_get_name(void *d) { return ((ss_display *)data_of(d))->name; }
static CFStringRef ss_display_get_device_name(void *d) { return ((ss_display *)data_of(d))->deviceName; }
static CFStringRef ss_display_get_uid(void *d) { return ((ss_display *)data_of(d))->uid; }
static uint32_t ss_display_get_dot_pitch(void *d) { return ((ss_display *)data_of(d))->pitch; }
static uint16_t ss_display_get_mode_count(void *d) { return 1; }
static bool ss_display_get_mode(void *d, long index, ss_mode *out) {
    if (index != 0 || !out) return false;
    *out = ((ss_display *)data_of(d))->mode;
    return true;
}
static void ss_display_get_current_mode(void *d, ss_mode *out) { if (out) *out = ((ss_display *)data_of(d))->mode; }
static ss_size ss_display_get_device_size(void *d) { ss_mode m = ((ss_display *)data_of(d))->mode; return (ss_size){ m.width, m.height }; }
static ss_size ss_display_get_canvas_size(void *d) { return ss_display_get_device_size(d); }

static void *ss_display_create_swapchain(void *d, long count, CFDictionaryRef options, CFErrorRef *error, double width, double height) {
    TRACE("create swapchain %g x %g count %ld (mode %u x %u)\n", width, height, count, ((ss_display *)data_of(d))->mode.width, ((ss_display *)data_of(d))->mode.height);
    CFMutableDataRef object = new_object(sizeof(ss_swapchain));
    ((ss_swapchain *)data_of(object))->display = ((ss_display *)data_of(d))->index;
    return object;
}

// MARK: swapchain

static bool ss_swap_begin(void *s, uint64_t time, CFErrorRef *error) { TRACE("swap begin\n"); return true; }
static bool ss_swap_add_surface(void *s, IOSurfaceRef surface, double sx, double sy, double sw, double sh,
                                double dx, double dy, double dw, double dh, long layer, long flags, CFErrorRef *error) {
    ss_swapchain *chain = data_of(s);
    if (surface) CFRetain(surface);
    if (chain->pending) CFRelease(chain->pending);
    chain->pending = surface;
    return true;
}
static bool ss_swap_set_callback(void *s, void *context, dispatch_queue_t queue, ss_present_block block) {
    ss_swapchain *chain = data_of(s);
    chain->context = context;
    chain->queue = queue;
    chain->block = block ? (ss_present_block)_Block_copy(block) : NULL;
    return true;
}
static bool ss_swap_submit(void *s, CFErrorRef *error) {
    ss_swapchain *chain = data_of(s);
    TRACE("swap submit\n");
    IOSurfaceRef surface = chain->pending;
    chain->pending = NULL;
    int index = chain->display;
    if (surface && index < SS_MAX_DISPLAYS) {
        pthread_mutex_lock(&lock);
        if (latest[index]) CFRelease(latest[index]);
        latest[index] = surface;   // keeps the reference
        frames[index]++;
        pthread_cond_broadcast(&presented);
        pthread_mutex_unlock(&lock);
    } else if (surface) CFRelease(surface);
    ss_present_block block = chain->block;
    void *context = chain->context;
    chain->block = NULL;
    if (block) {
        CFRetain(s);
        uint64_t now = mach_absolute_time();
        dispatch_async(chain->queue ?: dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            block(s, NULL, now, now, context);
            _Block_release(block);
            CFRelease(s);
        });
    }
    return true;
}
static bool ss_swap_cancel(void *s, CFErrorRef *error) {
    ss_swapchain *chain = data_of(s);
    if (chain->pending) CFRelease(chain->pending);
    chain->pending = NULL;
    return true;
}

// MARK: agent interface

/// Changes a display's pixel size, as CoreSimulator does for a resizable display: the window
/// server is told through its "display updated" handler and maps new surfaces.
bool swiftshot_fb_resize(int display, unsigned width, unsigned height) {
    load_displays();
    if (display >= CFArrayGetCount(displays) || !updated_handler) return false;
    void *object = (void *)CFArrayGetValueAtIndex(displays, display);
    ss_display *d = data_of(object);
    if (d->mode.width == width && d->mode.height == height) return true;
    TRACE("resize %d to %u x %u\n", display, width, height);
    d->mode.width = width;
    d->mode.height = height;
    void (^handler)(void *) = updated_handler;
    CFRetain(object);
    TRACE("resize via queue %s\n", updated_queue ? dispatch_queue_get_label(updated_queue) : "(none)");
    dispatch_async(updated_queue ?: dispatch_get_main_queue(), ^{ TRACE("updated handler\n"); handler(object); TRACE("updated handler done\n"); CFRelease(object); });
    return true;
}

/// Frames presented on a display so far.
uint64_t swiftshot_fb_frames(int display) {
    pthread_mutex_lock(&lock);
    uint64_t n = display < SS_MAX_DISPLAYS ? frames[display] : 0;
    pthread_mutex_unlock(&lock);
    return n;
}

/// Waits (up to timeout seconds) for a frame newer than `after`, returns the presented surface
/// (+1 reference; the server may draw into it again later, so copy it out promptly) or NULL.
IOSurfaceRef swiftshot_fb_wait(int display, uint64_t after, double timeout, uint64_t *frame) {
    if (display >= SS_MAX_DISPLAYS) return NULL;
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    long ns = deadline.tv_nsec + (long)((timeout - (long)timeout) * 1e9);
    deadline.tv_sec += (long)timeout + ns / 1000000000L;
    deadline.tv_nsec = ns % 1000000000L;
    pthread_mutex_lock(&lock);
    while (frames[display] <= after) {
        if (pthread_cond_timedwait(&presented, &lock, &deadline) != 0) break;
    }
    IOSurfaceRef s = frames[display] > after ? latest[display] : NULL;
    if (s) CFRetain(s);
    if (frame) *frame = frames[display];
    pthread_mutex_unlock(&lock);
    return s;
}

// MARK: interposing

extern void *SFBConnectionCreate(CFAllocatorRef, CFStringRef) __attribute__((weak_import));
extern bool SFBConnectionConnect(void *, CFErrorRef *) __attribute__((weak_import));
extern CFArrayRef SFBConnectionCopyDisplays(void *, CFErrorRef *) __attribute__((weak_import));
extern void *SFBConnectionCopyDisplayByUID(void *, CFStringRef, CFErrorRef *) __attribute__((weak_import));
extern void SFBConnectionSetDisplayUpdatedHandler(void *, dispatch_queue_t, void (^)(void *)) __attribute__((weak_import));
extern uint32_t SFBDisplayGetType(void *) __attribute__((weak_import));
extern CFStringRef SFBDisplayGetName(void *) __attribute__((weak_import));
extern CFStringRef SFBDisplayGetDeviceName(void *) __attribute__((weak_import));
extern CFStringRef SFBDisplayGetDisplayUID(void *) __attribute__((weak_import));
extern uint32_t SFBDisplayGetDotPitch(void *) __attribute__((weak_import));
extern uint16_t SFBDisplayGetModeCount(void *) __attribute__((weak_import));
extern bool SFBDisplayGetMode(void *, long, void *) __attribute__((weak_import));
extern void SFBDisplayGetCurrentMode(void *, void *) __attribute__((weak_import));
extern ss_size SFBDisplayGetDeviceSize(void *) __attribute__((weak_import));
extern ss_size SFBDisplayGetCurrentCanvasSize(void *) __attribute__((weak_import));
extern void *SFBDisplayCreateSwapchain(void *, long, CFDictionaryRef, CFErrorRef *, double, double) __attribute__((weak_import));
extern bool SFBSwapchainSwapBegin(void *, uint64_t, CFErrorRef *) __attribute__((weak_import));
extern bool SFBSwapchainSwapAddSurface(void *, IOSurfaceRef, double, double, double, double, double, double, double, double, long, long, CFErrorRef *) __attribute__((weak_import));
extern bool SFBSwapchainSwapSetCallback(void *, void *, dispatch_queue_t, void *) __attribute__((weak_import));
extern bool SFBSwapchainSwapSubmit(void *, CFErrorRef *) __attribute__((weak_import));
extern bool SFBSwapchainSwapCancel(void *, CFErrorRef *) __attribute__((weak_import));

#define I(r, o) { (const void *)r, (const void *)o }
__attribute__((used, section("__DATA,__interpose"))) static struct { const void *replacement, *original; } fake_display_interposers[] = {
    I(ss_connection_create, SFBConnectionCreate), I(ss_connection_connect, SFBConnectionConnect),
    I(ss_connection_copy_displays, SFBConnectionCopyDisplays), I(ss_connection_copy_display_by_uid, SFBConnectionCopyDisplayByUID),
    I(ss_connection_set_handler, SFBConnectionSetDisplayUpdatedHandler),
    I(ss_display_get_type, SFBDisplayGetType), I(ss_display_get_name, SFBDisplayGetName), I(ss_display_get_device_name, SFBDisplayGetDeviceName),
    I(ss_display_get_uid, SFBDisplayGetDisplayUID), I(ss_display_get_dot_pitch, SFBDisplayGetDotPitch),
    I(ss_display_get_mode_count, SFBDisplayGetModeCount), I(ss_display_get_mode, SFBDisplayGetMode),
    I(ss_display_get_current_mode, SFBDisplayGetCurrentMode), I(ss_display_get_device_size, SFBDisplayGetDeviceSize),
    I(ss_display_get_canvas_size, SFBDisplayGetCurrentCanvasSize), I(ss_display_create_swapchain, SFBDisplayCreateSwapchain),
    I(ss_swap_begin, SFBSwapchainSwapBegin), I(ss_swap_add_surface, SFBSwapchainSwapAddSurface),
    I(ss_swap_set_callback, SFBSwapchainSwapSetCallback), I(ss_swap_submit, SFBSwapchainSwapSubmit), I(ss_swap_cancel, SFBSwapchainSwapCancel),
};
