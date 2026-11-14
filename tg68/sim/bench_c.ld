ENTRY(run)
SECTIONS { . = 0x08010000; .text : { *(.text.entry) *(.text*) *(.rodata*) } .data : { *(.data*) } /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) } }
