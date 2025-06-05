main :: () {
    result_a := call1();
    result_b := call2();
    result_a += result_b;
}

call1 :: () -> u8 {
    a : u8 = 120;
    return a;
}

call2 :: () -> u8 {
    return 13;
}
