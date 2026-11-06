maprom 1.0 -- Base64 mapROM control (TG68 and fx68k builds)

  maprom            copy Kickstart into SDRAM and switch over
  maprom OFF        switch back to the motherboard ROM
  maprom STATUS     report only

The Base64 boot ROM already does the copy at every boot, so STATUS
normally reports "active". Use OFF / maprom to compare with and without.
mapROM always clears on reset; the boot ROM sets it again.
