#import "stb_image";
#import,dir "../modules/jai-sdl3";

convert_image_to_gb :: (file: string) -> [] u8 {
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
                    log("s: %, x: %, y: % = 0x%", sprite, px, py, formatInt(val, base = 16));
                    bit_1 := (val == col01 || val == col11);
                    bit_2 := (val == col10 || val == col11);
                    if bit_1 then b1 |= (1).(u8) << (7-px).(u8);
                    if bit_2 then b2 |= (1).(u8) << (7-px).(u8);
                }
                result[sprite + py] = b1;
                result[sprite + py + 1] = b2;
            }
        }
    }

    return result; 

    surface := SDL_CreateSurfaceFrom(x, y, .RGBA8888, img, 4 * size_of(u8) * x);
    defer SDL_DestroySurface(surface);

    palette := SDL_CreatePalette(4);
    colors := SDL_Color.[
    ];
    cspace := SDL_GetSurfaceColorspace(surface);
    SDL_SetPaletteColors(palette, colors.data, 0, colors.count);
    new := SDL_ConvertSurfaceAndColorspace(surface, .INDEX8, palette, cspace, 0);
    assert(new != null, "%", SDL_GetError());
    defer SDL_DestroySurface(new);

    SDL_LockSurface(new);
    {
        pixels : *u8 = xx new.pixels;
        for 0..(x * y) {
            log("%", pixels[it]);
        }
        for sy : 0..nb_y - 1 {
            for sx : 0..nb_x - 1 {
                sprite := sx * 8 + sy * 8 * nb_x;
                for py : 0..7 {
                    b1 : u8 = 0;
                    b2 : u8 = 0;
                    for px : 0..7 {
                        val := pixels[sprite + px + py * 8];
                        log("s: %, x: %, y: % = %", sprite, px, py, val);
                    }
                }
            }
        }
    }

    SDL_UnlockSurface(new);
    return result;
}

