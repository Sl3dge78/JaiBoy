
main :: () {
    a := proc();

}

proc :: () -> u8 {
    i := 0;
    val : u8 = 0;
    while i < arr.count {
        val = arr[i];
        i += 1;
    }
    return val;
}

arr :: u8.[0x42, 0x42, 0x42, 0x69];
