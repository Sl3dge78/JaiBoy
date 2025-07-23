#import "stb_image";
#import "Basic";

load_gb_image :: (file: string) -> [] u8 #compile_time { 
    w : s32;
    h : s32;
    channels: s32;
    img := stbi_load(file.data, *w, *h, *channels, 4);
    assert(img != null, "Unable to load %", file);
    defer stbi_image_free(img);
    assert((w % 8) == 0 && (h % 8) == 0, "File dimensions aren't a multiple of 8");

    nb_x := w / 8;
    nb_y := h / 8;
    nb_sprites := nb_y * nb_x;
    log("Sprites: x: %, y: %", nb_x, nb_y);

    result := NewArray(nb_sprites * 16, u8);

    col00 :: 0xFF_0F_BC_9B;
    col01 :: 0xFF_0F_AC_8B;
    col10 :: 0xFF_30_62_30;
    col11 :: 0xFF_0F_38_0F;
    pixels : *u32 = xx img;
    for sy : 0..nb_y - 1 {
        for sx : 0..nb_x - 1 {
            sprite := sx + sy * nb_x;
            sprite_x := sx * 8;
            sprite_y := sy * 8;
            log("% (%, %)", sprite, sprite_x, sprite_y);
            for py : 0..7 {
                b1 : u8 = 0;
                b2 : u8 = 0;
                for px : 0..7 {
                    ix := px + sprite_x;
                    iy := py + sprite_y;
                    val := pixels[ix + iy * w];
                    bit_1 := (val == col01 || val == col11);
                    bit_2 := (val == col10 || val == col11);
                    if bit_1 then b1 |= (1).(u8) << (7-px).(u8);
                    if bit_2 then b2 |= (1).(u8) << (7-px).(u8);
                }
                result[sprite * 16 + py * 2] = b1;
                result[sprite * 16 + py * 2 + 1] = b2;
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
