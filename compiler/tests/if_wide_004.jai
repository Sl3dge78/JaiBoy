main :: () {
    val := proc();
}

proc :: () -> u8 {
    a := 0xBEBA;
    b := 0xBEBE;

    if a != b {
        return 69;
    } else {
        return 1;
    }
}
