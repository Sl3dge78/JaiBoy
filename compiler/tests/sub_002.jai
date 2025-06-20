
main :: () {
    a := func();
}

func :: () -> u8 {
    a := 0xFF0F;
    a = a - 0xF00F;
    if a == 0x0F00 {
        return 1;
    } else {
        return 0;
    }
}
