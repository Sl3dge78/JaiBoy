
main :: () {
    proc();
}

proc :: () {
    i := 0;
    while i < arr.count {
        ptr : *u8 = xx (0x8000 + i);
        ptr.* = arr[i];
        i += 1;
    }
    return;
}

arr :: u8.[0x42, 0x12, 0x32, 0x69];
