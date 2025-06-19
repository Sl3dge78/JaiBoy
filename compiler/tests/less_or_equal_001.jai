
main :: () {
    a := func();
}

func :: () -> u8 {
    a := 0x1012;
    if a <= 0x1013 {
        return 69;
    } else {
        return 0;
    }

}
