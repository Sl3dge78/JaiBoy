main :: () {
    val := proc();

}

proc :: () -> u8 {
    a := 0xCAFE;
    b := 0xBABE;

    if a == b {
        return 1;
    } else {
        return 69;
    }
}

