/* Linux ARM EABI calls available on the Android 4.4 kernel. No libc/CRT. */
.syntax unified
.arm
.text
.global _start
_start:
    mov r4, sp
    bic sp, sp, #7
    ldr r0, [r4]
    add r1, r4, #4
    bl main
    mov r7, #1
    svc #0
1:  b 1b
.macro call name, number
.global \name
.type \name,%function
\name:
    push {r7,lr}
    mov r7, #\number
    svc #0
    pop {r7,pc}
.endm
call read,3
call write,4
call open,5
call close,6
call unlink,10
call lseek,19
call fsync,118
