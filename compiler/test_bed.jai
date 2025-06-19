
main :: () {
    sp(0xFFFF);
    di();
    disable_lcd();
    write_sprite();
    enable_lcd();
    ei();
    halt();
}

write_sprite :: () {
    a : *u8 = xx 0x8001;
    while a <= xx 0x800F {
        a.* = 0b1000_0000;
        a += 2;
    }
}

enable_lcd :: () {
    lcdc: *u8 = xx 0xFF40;
    lcdc.* = 0b1000_0000;
}

disable_lcd :: () {
    lcdc: *u8 = xx 0xFF40;
    lcdc.* = 0b0000_0000;
}

// Special instructions intrinsics
di :: () #elsewhere;
ei :: () #elsewhere;
halt :: () #elsewhere;
reti :: () #elsewhere;
sp :: (addr: u16) #elsewhere;
