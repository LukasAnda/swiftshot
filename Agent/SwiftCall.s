// void *swiftshot_call_swiftself(void *fn, void *self, void *arg)
// Calls a Swift function `fn(arg)` with `self` in x20 (the Swift calling convention's
// self/context register), e.g. an allocating initializer that expects its metatype there.
#if defined(__arm64__)
    .text
    .globl _swiftshot_call_swiftself
    .p2align 2
_swiftshot_call_swiftself:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x20, [sp, #16]
    mov     x16, x0
    mov     x20, x1
    mov     x0, x2
    blr     x16
    ldr     x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
#endif
