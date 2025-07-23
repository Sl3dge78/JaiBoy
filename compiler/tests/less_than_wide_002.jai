
main :: () {
    a := func1();
    a += func2();
    a += func3();
}

func1 :: () -> u8 {
    a := 0x1012;
    if a < 0x1010 {
        return 0;
    } else {
        return 1;
    }
}

func2 :: () -> u8 {
    a := 0x0112;
    if a < 0x1010 {
        return 2;
    } else {
        return 0;
    }

}

func3 :: () -> u8 {
    a := 0x1012;
    if a < 0x0110 {
        return 0;
    } else {
        return 4;
    }
}
