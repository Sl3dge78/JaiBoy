#import "stb_image";
#import "Basic";

load_gb_image :: (file: string) -> [] u8 #compile_time { 
    x : s32;
    y : s32;
    channels: s32;
    img := stbi_load(file.data, *x, *y, *channels, 4);
    assert(img != null, "Unable to load %", file);
    defer stbi_image_free(img);
    assert((x % 8) == 0 && (y % 8) == 0, "File dimensions aren't a multiple of 8");

    nb_x := x / 8;
    nb_y := y / 8;
    nb_sprites := nb_y * nb_x;

    result := NewArray(nb_sprites * 16, u8);

    col00 :: 0xFF_0F_BC_9B;
    col01 :: 0xFF_0F_AC_8B;
    col10 :: 0xFF_30_62_30;
    col11 :: 0xFF_0F_38_0F;
    pixels : *u32 = xx img;
    for sy : 0..nb_y - 1 {
        for sx : 0..nb_x - 1 {
            sprite := sx + sy * nb_x;
            for py : 0..7 {
                b1 : u8 = 0;
                b2 : u8 = 0;
                for px : 0..7 {
                    val := pixels[sprite + px + py * 8];
                    bit_1 := (val == col01 || val == col11);
                    bit_2 := (val == col10 || val == col11);
                    if bit_1 then b1 |= (1).(u8) << (7-px).(u8);
                    if bit_2 then b2 |= (1).(u8) << (7-px).(u8);
                }
                result[sprite + py * 2] = b1;
                result[sprite + py * 2 + 1] = b2;
            }
        }
    }

    builder: String_Builder;
    print_to_builder(*builder, ".[");
    for result {
        print_to_builder(*builder, "0x%,", formatInt(it, base = 16));
    }
    print_to_builder(*builder, "];");
    log("%", builder_to_string(*builder));
    return result; 
}
