main :: () {
    result := proc();
}

proc :: () -> u8 {
    a : u8 = 1;
    b : u8 = 2;

    c : u8;

    if a == b {
        c = a;
    } else {
        c = b;
    }
    return c;
}

