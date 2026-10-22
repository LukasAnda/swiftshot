// swiftshot-simhost: runs a simulator process without a booted simulator (experimental).
//
//   swiftshot-simhost <runtime root> <simulator executable> [args…]
//
// A booted simulator gives its processes a launchd_sim and, through CoreSimulator, a Metal host,
// an IOSurface server and on-demand XPC services. This host provides exactly the ones rendering
// needs and starts the executable directly on the Mac with DYLD_ROOT_PATH=<runtime root>:
//   * Metal: macOS' MTLSimImplementation (what CoreSimulator's SimMetalHost loads) on a listener
//   * IOSurface: macOS' IOSurfaceRemoteServer on a second listener
//   * the runtime's MTLCompilerService (shader compiler), started here instead of by launchd
// Their ports reach the child as registered Mach ports; Agent/NoBoot.c (injected into the child
// via $SWIFTSHOT_NOBOOT_SHIM, or $SWIFTSHOT_NOBOOT_INSERT for the app) routes the child's XPC connections to them. Exits with the child.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <xpc/xpc.h>
#import <dlfcn.h>
#import <spawn.h>
#import <signal.h>
#import <mach/mach.h>

@interface IOSurfaceRemoteServer : NSObject
- (instancetype)initWithListener:(xpc_connection_t)listener options:(NSDictionary *)options;
@end

extern char **environ;
extern mach_port_t xpc_endpoint_copy_listener_port_4sim(xpc_endpoint_t);
extern void xpc_connection_enable_sim2host_4sim(xpc_connection_t);
typedef void (*MetalInit)(xpc_connection_t listener, uint64_t registryID);

static pid_t compilerPid;

/// An anonymous listener that speaks the simulator's XPC wire format; returns a send right to it.
static mach_port_t simListener(xpc_connection_t *out) {
    xpc_connection_t listener = xpc_connection_create(NULL, dispatch_get_main_queue());
    xpc_connection_enable_sim2host_4sim(listener);
    *out = listener;
    return xpc_endpoint_copy_listener_port_4sim(xpc_endpoint_create(listener));
}

static pid_t spawn(char *const argv[], const char *root, const char *insert) {
    setenv("DYLD_ROOT_PATH", root, 1);
    if (insert) setenv("DYLD_INSERT_LIBRARIES", insert, 1);
    pid_t pid;
    if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0) { perror(argv[0]); exit(71); }
    return pid;
}

/// Starts the runtime's shader compiler service and waits for its listener port.
static mach_port_t startCompiler(const char *root, const char *shim) {
    mach_port_t rendezvous;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &rendezvous);
    mach_port_insert_right(mach_task_self(), rendezvous, rendezvous, MACH_MSG_TYPE_MAKE_SEND);
    mach_port_t ports[3] = { MACH_PORT_NULL, MACH_PORT_NULL, rendezvous };
    mach_ports_register(mach_task_self(), ports, 3);
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/System/Library/Frameworks/Metal.framework/XPCServices/MTLCompilerService.xpc/MTLCompilerService", root);
    char *argv[] = { path, NULL };
    setenv("SWIFTSHOT_SIMHOST_SERVICE", "1", 1);
    compilerPid = spawn(argv, root, shim);
    unsetenv("SWIFTSHOT_SIMHOST_SERVICE");
    struct { mach_msg_header_t h; mach_msg_body_t b; mach_msg_port_descriptor_t p; mach_msg_trailer_t t; } m;
    kern_return_t kr = mach_msg(&m.h, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof m, rendezvous, 15000, 0);
    if (kr != KERN_SUCCESS) { fprintf(stderr, "swiftshot-simhost: shader compiler did not start (%x)\n", kr); return MACH_PORT_NULL; }
    return m.p.name;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: swiftshot-simhost <runtime root> <executable> [args…]\n"); return 64; }
        const char *root = argv[1];
        const char *shim = getenv("SWIFTSHOT_NOBOOT_SHIM");

        void *metal = dlopen("/System/Library/PrivateFrameworks/MTLSimImplementation.framework/MTLSimImplementation", RTLD_NOW);
        MetalInit metalInit = metal ? (MetalInit)dlsym(metal, "init_with_xpc_connection") : NULL;
        id<MTLDevice> gpu = MTLCreateSystemDefaultDevice();
        if (!metalInit || !gpu) { fprintf(stderr, "swiftshot-simhost: no Metal simulator support on this Mac\n"); return 69; }
        xpc_connection_t metalListener;
        mach_port_t metalPort = simListener(&metalListener);
        metalInit(metalListener, gpu.registryID);   // it accepts and serves each client itself

        xpc_connection_t surfaceListener;
        mach_port_t surfacePort = simListener(&surfaceListener);
        static IOSurfaceRemoteServer *surfaces;
        surfaces = [[NSClassFromString(@"IOSurfaceRemoteServer") alloc] initWithListener:surfaceListener options:@{}];
        if (!surfaces) { fprintf(stderr, "swiftshot-simhost: no IOSurfaceRemoteServer\n"); return 69; }

        mach_port_t compilerPort = startCompiler(root, shim);
        mach_port_t ports[3] = { metalPort, surfacePort, compilerPort };
        mach_ports_register(mach_task_self(), ports, 3);
        // The app gets the shim plus whatever else should be injected (the swiftshot agent).
        const char *insert = getenv("SWIFTSHOT_NOBOOT_INSERT");
        pid_t child = spawn(argv + 2, root, insert ? insert : shim);

        dispatch_source_t exitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, child, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
        dispatch_source_set_event_handler(exitSource, ^{
            int status = 0;
            waitpid(child, &status, 0);
            if (compilerPid) kill(compilerPid, SIGKILL);
            exit(WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status));
        });
        dispatch_resume(exitSource);
        dispatch_main();
    }
}
