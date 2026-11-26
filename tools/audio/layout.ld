cf_equal = 0x26ec;
cf_array_create = 0x26c8;
cf_array_append = 0x26d4;
cf_release = 0x26e0;
create_dictionary = 0x3cd1;
SECTIONS {
 .input 0x3aac : { *(.input) }
 .output 0x3b74 : { *(.output) }
 .formats 0x3e1c : { *(.formats) }
 /DISCARD/ : { *(.ARM.exidx*) *(.comment*) *(.note*) }
}
