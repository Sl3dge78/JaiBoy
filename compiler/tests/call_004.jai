main :: () {
    a := call1();
    a += 2;
}

call1 :: () -> u8 {
    a : u8 = 120;
    return a;
}
