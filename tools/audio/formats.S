/* Our ABI-compatible format selectors. Addresses describe only V039 ABI facts.
 * The code and tables below were authored for this project. No OEM instructions.
 * uint64_t selector(uint32_t stream, CFStringRef role, uint32_t transport).
 * Keep PCM masks; advertise AAC-LC stereo and Opus 16/24 kHz mono as supported
 * by the stock Core format converter and Utils codec implementations. */
.syntax unified
.thumb
.section .input,"ax",%progbits
.global input_formats
.thumb_func
input_formats:
    movs r3, #0
    b.w select_formats
    .space 200-(.-input_formats),0

.section .output,"ax",%progbits
.global output_formats
.thumb_func
output_formats:
    movs r3, #1
select_formats:
    push {r4,r5,r6,r7,r8,lr}
    mov r4, r1
    mov r6, r3
    adr r7, anchor
    ldr r3, anchor
    subs r7, r7, r3
    cmp r0, #100
    beq main
    cmp r0, #101
    bne none
    adr r5, alternate_table
    b next
main:
    adr r5, main_table
next:
    ldr r1, [r5]
    cbz r1, none
    add r1, r7
    mov r0, r4
    /* CFEqual is the existing ARM PLT entry; BLX switches instruction state. */
    blx cf_equal
    cbnz r0, found
    adds r5, #12
    b next
found:
    adds r5, #4
    ldr r0, [r5,r6,lsl #2]
    b done
none:
    movs r0, #0
done:
    movs r1, #0
    pop {r4,r5,r6,r7,r8,pc}
    .balign 4
anchor:
    .word anchor
main_table:
    /* CF string objects and uint32 input/output bitmaps. */
    .word 0x73f4, 0x30000054, 0x30c08854 /* compatibility */
    .word 0x740c, 0x00000000, 0x00c00800 /* media */
    .word 0x741c, 0x30000054, 0x30000054 /* telephony */
    .word 0x7430, 0x20000040, 0x20000040 /* speech recognition */
    .word 0x744c, 0x00000000, 0x00000400 /* alert */
    .word 0x745c, 0x30000050, 0x30000050 /* default */
    .word 0,0,0
alternate_table:
    .word 0x73f4, 0, 0x00008800
    .word 0x745c, 0, 0x00000400
    .word 0,0,0
    .space 348-(.-output_formats),0
