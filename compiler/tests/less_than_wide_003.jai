
main :: () {
    a := func();
}

func :: () -> u8 {
    a := 0x1012;
    if a < 0x1010 {
        return 0;
    } else {
        return 69;
    }

}
