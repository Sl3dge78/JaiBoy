
main :: () {
    result := proc();
}

proc :: () -> u8 {
    a : u8 = 0;
    b := 12;

    if b == 12 {
        a += 1;
    }
    return a;
}
