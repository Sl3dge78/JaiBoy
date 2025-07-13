main :: () {
    r := proc();

}

proc :: () -> u8 {
    a : u8 = 0;

    while a < 10 {
        a += 1;
    }
    return a;
}

