// Runs as soon as dyld maps the agent into the target app (via DYLD_INSERT_LIBRARIES).
extern void SwiftshotAgentStart(void);

__attribute__((constructor))
static void swiftshot_agent_init(void) {
    SwiftshotAgentStart();
}
