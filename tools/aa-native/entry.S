.syntax unified
.thumb
.section .entry,"ax",%progbits
.global route_entry
.thumb_func
route_entry:
    /* At the reviewed unknown-message edge r2=message, r6=body, r5=length.
     * Rejoin its original epilogue with only its result register changed. */
    push.w {r0,r1,r2,r3,r5,r6,r7,r8,r9,r10,r11,lr}
    mov r0,r2
    mov r1,r6
    mov r2,r5
    bl aa_route
    mov r4,r0
    pop.w {r0,r1,r2,r3,r5,r6,r7,r8,r9,r10,r11,lr}
    adr r12, continuation
    ldr r12,[r12]
    /* PIC address of the stock epilogue. */
    adr r5, continuation
    add r12,r5
    /* r5 is dead on this edge: stock epilogue restores it from its frame. */
    bx r12
    .balign 4
continuation:
    .word 0xb681d-continuation
.global status_entry
.thumb_func
status_entry:
    b.w aa_status
