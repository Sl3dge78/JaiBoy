
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
    a.* = 0b1000_0000;
    a = xx 0x8003;
    a.* = 0b0100_0000;
    a = xx 0x8005;
    a.* = 0b0010_0000;
    a = xx 0x8007;
    a.* = 0b0001_0000;
    a = xx 0x8009;
    a.* = 0b0000_1000;
    a = xx 0x800B;
    a.* = 0b0000_0100;
    a = xx 0x800D;
    a.* = 0b0000_0010;
    a = xx 0x800F;
    a.* = 0b0000_0001;
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
