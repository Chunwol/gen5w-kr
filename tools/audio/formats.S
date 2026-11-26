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
#ifdef LEGACY_V035
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
#else
select_formats:
    push {r4,r5,r6,r7,r8,r9,r10,lr}
    mov r8, r0
    mov r4, r1
    mov r9, r2
    mov r6, r3
    adr r7, anchor
    ldr r3, anchor
    subs r7, r7, r3
    cmp r0, #100
    beq main
    cmp r0, #102
    beq buffered_main
    cmp r0, #101
    bne none
    adr r5, alternate_table
    b next
main:
    adr r5, main_table
    b next
buffered_main:
    cmp r2, #1
    bne none
    adr r5, buffered_table
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
    cbz r0, done
    mov r2, r9
    cmp r2, #1
    bne done
    mov r2, r8
    cmp r2, #100
    bne check_alt
    cbz r6, add_opus_all
    cmp r0, #0x0800
    beq media_wifi
    movw r3, #0x8854
    cmp r0, r3
    bne add_opus_all
    orr r0, r0, #0x00c00000
add_opus_all:
    orr r0, r0, #0x70000000
    b done
media_wifi:
    orr r0, r0, #0x00c00000
    orr r0, r0, #0x8000
    b done
check_alt:
    cmp r2, #101
    bne done
    orr r0, r0, #0x40000000
    b done
none:
    movs r0, #0
done:
    movs r1, #0
    pop {r4,r5,r6,r7,r8,r9,r10,pc}
    .balign 4
anchor:
    .word anchor
main_table:
    /* Stock V039 PCM bitmaps; Wi-Fi adds AAC-LC / Opus 16k, 24k, 48k above. */
    .word 0x73f4, 0x00000054, 0x00008854 /* compatibility */
    .word 0x740c, 0x00000000, 0x00000800 /* media */
    .word 0x741c, 0x00000054, 0x00000054 /* telephony */
    .word 0x7430, 0x00000040, 0x00000040 /* speech recognition */
    .word 0x744c, 0x00000000, 0x00000400 /* alert */
    .word 0x745c, 0x00000050, 0x00000050 /* default */
    .word 0,0,0
alternate_table:
    .word 0x73f4, 0, 0x00008800
    .word 0x745c, 0, 0x00000400
    .word 0,0,0
buffered_table:
    .word 0x740c, 0, 0x00c08800 /* wireless MainHigh media: PCM 44.1/48k + AAC-LC */
    .word 0,0,0
    .space 348-(.-output_formats),0
#endif

#ifndef LEGACY_V035
/* Keep the stock stream/role dictionaries and add buffered MainHigh media only
 * for Wireless (1). This is authored code; CF objects stay in the OEM image. */
.section .formats,"ax",%progbits
.global advertised_formats
.thumb_func
advertised_formats:
    push {r4,r5,r6,r7,r8,lr}
    sub sp, #8
    mov r4, r0
    mov r5, r1
    adr r7, formats_anchor
    ldr r3, formats_anchor
    subs r7, r7, r3
    ldr r2, array_callbacks
    add r2, r7
    ldr r2, [r2]
    movs r0, #0
    movs r1, #0
    blx cf_array_create
    mov r6, r0
    cbz r0, formats_nomem
    adr r8, format_pairs
formats_next:
    ldr r0, [r8]
    cbz r0, formats_done
    cmp r0, #102
    bne formats_pair
    cmp r4, #1
    bne formats_skip
formats_pair:
    ldr r1, [r8, #4]
    add r1, r7
    mov r2, r4
    mov r3, sp
    bl create_dictionary
    cbz r0, formats_skip
    str r0, [sp, #4]
    ldr r1, [sp]
    cbnz r1, formats_release
    mov r1, r0
    mov r0, r6
    blx cf_array_append
formats_release:
    ldr r0, [sp, #4]
    blx cf_release
formats_skip:
    add r8, r8, #8
    b formats_next
formats_done:
    movs r0, #0
    b formats_result
formats_nomem:
    movw r0, #0xe5b8
    movt r0, #0xffff
formats_result:
    cbz r5, formats_return
    str r0, [r5]
formats_return:
    mov r0, r6
    add sp, #8
    pop {r4,r5,r6,r7,r8,pc}
    .balign 4
formats_anchor:
    .word formats_anchor
array_callbacks:
    .word 0x9ebc
format_pairs:
    .word 100,0x73f4, 101,0x73f4, 100,0x740c, 100,0x741c
    .word 100,0x7430, 100,0x744c, 100,0x745c, 101,0x745c
    .word 102,0x740c, 0,0
    .space 488-(.-advertised_formats),0
#endif
