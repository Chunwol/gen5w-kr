cf_equal = 0x26ec;
SECTIONS {
 .input 0x3aac : { *(.input) }
 .output 0x3b74 : { *(.output) }
 /DISCARD/ : { *(.ARM.exidx*) *(.comment*) *(.note*) }
}
