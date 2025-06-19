main :: () {
    val := proc();
}

proc :: () -> u8 {
    a := 0xBA;
    b := 0xBEBE;

    if a == b {
        return 1;
    } else {
        return 69;
    }
}
