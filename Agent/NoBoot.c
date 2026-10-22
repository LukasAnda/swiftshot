// No-boot shim, injected into simulator processes that run straight on the Mac (no booted
// simulator, so no launchd_sim to look services up in). swiftshot-simhost starts those processes
// with up to three registered Mach ports (mach_ports_register):
//   0: Metal host (com.apple.metal.simulator)        — served by macOS' MTLSimImplementation
//   1: IOSurface server (com.apple.IOSurface.Remote) — served by macOS' IOSurfaceRemoteServer
//   2: MTLCompilerService listener (in the app)      / rendezvous port (in the compiler itself)
// and this shim routes the corresponding XPC connections to them. Without registered ports (a
// normal booted simulator) every call passes straight through.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>
#include <xpc/xpc.h>

extern xpc_endpoint_t xpc_endpoint_create_mach_port_4sim(mach_port_t);
extern mach_port_t xpc_endpoint_copy_listener_port_4sim(xpc_endpoint_t);
extern xpc_connection_t xpc_connection_create_from_endpoint(xpc_endpoint_t);
// Declared "unavailable on iOS" by the SDK, but present in the simulator's libxpc.
extern xpc_connection_t real_create_mach_service(const char *, dispatch_queue_t, uint64_t) __asm__("_xpc_connection_create_mach_service");
extern void real_xpc_main(xpc_connection_handler_t) __asm__("_xpc_main");

static mach_port_t registered(int index) {
    static mach_port_t ports[3];
    static int loaded;
    if (!loaded) {
        loaded = 1;
        mach_port_array_t p;
        mach_msg_type_number_t n = 0;
        if (mach_ports_lookup(mach_task_self(), &p, &n) == KERN_SUCCESS)
            for (unsigned i = 0; i < n && i < 3; i++) ports[i] = p[i];
    }
    return ports[index];
}

static xpc_connection_t connect_to(mach_port_t port, dispatch_queue_t queue) {
    xpc_connection_t c = xpc_connection_create_from_endpoint(xpc_endpoint_create_mach_port_4sim(port));
    if (queue) xpc_connection_set_target_queue(c, queue);
    return c;
}

static xpc_connection_t noboot_create_mach_service(const char *name, dispatch_queue_t queue, uint64_t flags) {
    if (name) {
        // The Metal driver asks for "com.apple.metal.simulator.<process>" first, then the plain name.
        if (strncmp(name, "com.apple.metal.simulator", 25) == 0 && registered(0)) return connect_to(registered(0), queue);
        if (strcmp(name, "com.apple.IOSurface.Remote") == 0 && registered(1)) return connect_to(registered(1), queue);
    }
    return real_create_mach_service(name, queue, flags);
}

static xpc_connection_t noboot_create(const char *name, dispatch_queue_t queue) {
    if (name && strcmp(name, "com.apple.MTLCompilerService") == 0 && registered(2) && getenv("SWIFTSHOT_NOBOOT"))
        return connect_to(registered(2), queue);
    return xpc_connection_create(name, queue);
}

// In the MTLCompilerService binary started by swiftshot-simhost: listen anonymously and mail the
// listener's port to the host's rendezvous port, which hands it to the app.
static void noboot_xpc_main(xpc_connection_handler_t handler) {
    if (!getenv("SWIFTSHOT_SIMHOST_SERVICE") || !registered(2)) { real_xpc_main(handler); return; }
    xpc_connection_t listener = xpc_connection_create(NULL, NULL);
    xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) == XPC_TYPE_CONNECTION) handler(peer);
    });
    xpc_connection_activate(listener);
    struct { mach_msg_header_t h; mach_msg_body_t b; mach_msg_port_descriptor_t p; } m = {0};
    m.h.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
    m.h.msgh_size = sizeof m;
    m.h.msgh_remote_port = registered(2);
    m.b.msgh_descriptor_count = 1;
    m.p.name = xpc_endpoint_copy_listener_port_4sim(xpc_endpoint_create(listener));
    m.p.disposition = MACH_MSG_TYPE_MOVE_SEND;
    m.p.type = MACH_MSG_PORT_DESCRIPTOR;
    if (mach_msg(&m.h, MACH_SEND_MSG, sizeof m, 0, 0, 0, 0) != KERN_SUCCESS) exit(70);
    dispatch_main();
}

__attribute__((used, section("__DATA,__interpose"))) static struct { const void *replacement, *original; } interposers[] = {
    { (const void *)noboot_create_mach_service, (const void *)real_create_mach_service },
    { (const void *)noboot_create, (const void *)xpc_connection_create },
    { (const void *)noboot_xpc_main, (const void *)real_xpc_main },
};
