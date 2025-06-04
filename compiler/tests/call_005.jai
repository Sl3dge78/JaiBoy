main :: () {
    a := call1();
    b := call2();
    a += b;
}

call1 :: () -> u8 {
    a : u8 = 120;
    return a;
}

call2 :: () -> u8 {
    return 13;
}
