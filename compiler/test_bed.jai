
main :: () {
    sp(0xCFFF);
    di();
    disable_lcd();
    write_sprite();
    enable_lcd();
    ei();
    halt();
}

write_sprite :: () {
    low := 0x01;
    base : * u8 = xx 0x8000;
    while low < 0x10 {
        a : * u8 = base + low;
        a.* = 0b1001_1001;
        low += 2;
    }
}

enable_lcd :: () {
    lcdc: *u8 = xx 0xFF40;
    lcdc.* = 0b1000_0001;
}

disable_lcd :: () {
    lcdc: *u8 = xx 0xFF40;
    lcdc.* = 0b0000_0000;
}

// Special instructions intrinsics
di :: () #elsewhere;
ei :: () #elsewhere;
lo :: (v: u16) -> u8 #elsewhere;
hi :: (v: u16) -> u8 #elsewhere;
halt :: () #elsewhere;
reti :: () #elsewhere;
sp :: (addr: u16) #elsewhere;
