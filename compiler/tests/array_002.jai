
main :: () {
    a := proc();

}

proc :: () -> u8 {
    i := 0;
    val : u8 = 0;
    while i < arr.count {
        val = arr[i];
    }
    return val;
}

arr :: u8.[0x42, 0x42, 0x42, 0x69];
