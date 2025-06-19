main :: () {
    val := proc();
}

proc :: () -> u8 {
    a := 0xCABE;
    b := 0xBEBE;

    if a != b {
        return 69;
    } else {
        return 1;
    }
}

