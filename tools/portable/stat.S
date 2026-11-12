/* fstat64 fills bionic's ARM struct stat64, which is also struct stat. */
.syntax unified
.arm
.text
.global fstat
.type fstat,%function
fstat:
 push {r7,lr}
 mov r7,#197
 svc #0
 pop {r7,pc}

/* mount(source, target, type, flags, data): fifth EABI arg is on stack. */
.global mount
.type mount,%function
mount:
 ldr ip,[sp]
 push {r4,r7,lr}
 mov r4,ip
 mov r7,#21
 svc #0
 pop {r4,r7,pc}

/* Additional process primitives for the independent maintenance guardian. */
.macro primitive name, number
.global \name
.type \name,%function
\name:
 push {r7,lr}
 mov r7,#\number
 svc #0
 pop {r7,pc}
.endm
primitive fork,2
primitive execve,11
primitive kill,37
primitive pipe,42
primitive setsid,66
primitive poll,168
primitive clock_gettime,263
primitive _exit,1
.global waitpid
.type waitpid,%function
waitpid:
 push {r7,lr}
 mov r3,#0
 mov r7,#114
 svc #0
 pop {r7,pc}

/* rt_sigaction(SIGPIPE, SIG_IGN, NULL, sizeof(kernel_sigset_t)). */
.global portable_ignore_sigpipe
.type portable_ignore_sigpipe,%function
portable_ignore_sigpipe:
 push {r7,lr}
 sub sp,sp,#24
 mov r0,#1
 str r0,[sp]
 mov r0,#0
 str r0,[sp,#4]
 str r0,[sp,#8]
 str r0,[sp,#12]
 str r0,[sp,#16]
 mov r0,#13
 mov r1,sp
 mov r2,#0
 mov r3,#8
 mov r7,#174
 svc #0
 add sp,sp,#24
 pop {r7,pc}
