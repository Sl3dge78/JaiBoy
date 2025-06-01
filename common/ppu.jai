Lcdc_Flags :: enum_flags u8 {
    WIN_PRIORIRY:: 0b0000_0001;
    OBJ_ENABLE:: 0b0000_0010;
    SPRITE_SIZE:: 0b0000_0100;
    BG_TILE_MAP_DISPLAY_SELECT:: 0b0000_1000;
    BG_TILE_DATA_SELECT:: 0b0001_0000;
    WIN_ENABLE:: 0b0010_0000;
    WIN_TILEMAP:: 0b0100_0000;
    LCD_ENABLE:: 0b1000_0000;
}

STAT_MODE_FLAG   : u8 : 0b0000_0011;
STAT_COINCI_FLAG : u8 : 0b0000_0100;
STAT_HBLANK_INT  : u8 : 0b0000_1000;
STAT_VBLANK_INT  : u8 : 0b0001_0000;
STAT_OAM_INT     : u8 : 0b0010_0000;
STAT_COINCI_INT  : u8 : 0b0100_0000;

Color :: struct {
    r: u8;
    g: u8;
    b: u8;
    a: u8;
} #no_padding;

palette : [4]Color = .[
    .{0xe2, 0xf3, 0xe4, 0xFF},
    .{0x94, 0xe3, 0x44, 0xFF},
    .{0x46, 0x87, 0x8f, 0xFF},
    .{0x33, 0x2c, 0x50, 0xFF},
];

Palette :: union  {
    array: [4]u8;
    single: u32; 
};

get_palette_from_byte :: (byte: u8) -> Palette {
    result : Palette;
    result.array[0] = byte & 0b11;
    result.array[1] = (byte & 0b1100) >> 2;
    result.array[2] = (byte & 0b110000) >> 4;
    result.array[3] = (byte & 0b11000000) >> 6;
    return result;
}

get_mode :: (LY: u8) -> u8 {
    if(LY >= 144 && LY <= 153) { // We're in vblank
        return 1;
    } else { // Go the start of the sequence for the next line
        return 2;
    }
}

LCD :: (gb: *Gameboy) {
    LCDC: Lcdc_Flags = xx gb.mem[IO_LCDC];
    
    if(!(LCDC >> 7 & 1)) { // LCD Display Enable
        gb.ppu_clock = 1;
        return;
    }
    
    STAT: u8 = gb.mem[IO_STAT];
    LY:   u8 = gb.mem[IO_LY];
    LYC:  u8 = gb.mem[IO_LYC];

    mode := STAT & 0b11;

    if mode == {
        case 0; { // H blank, draw the line!
            background(gb, LCDC, LY);
            window(gb, LCDC, LY);
            OAM(gb, LCDC, LY);
            gb.ppu_clock += 208;

            LY += 1;
            if(LY == 154) {
                LY = 0;
            }
            gb.mem[IO_LY] = LY;
            mode = get_mode(LY);
        } 
        case 1; { // VBlank
            gb.ppu_clock += 456;

            LY += 1;
            if(LY == 154) {
                LY = 0;
            }
            gb.mem[IO_LY] = LY;
            mode = get_mode(LY);
        } 
        case 2; { // Scanning oam
            mode = 3;
            gb.ppu_clock += 80;
        } 
        case 3; { // Reading oam
            mode = 0;
            gb.ppu_clock += 168;
        } 
    }

    // Update STAT register
    STAT = (STAT & ~STAT_COINCI_FLAG) | ((cast(u8)(LY == LYC)) << 2); // Coincidence flag
    STAT = (STAT & ~STAT_MODE_FLAG) | mode; // Mode flag
    STAT |= 0b1000_0000;
    gb.mem[IO_STAT] = STAT;
    
    // Interrupts       
    if LY == 0x90 { // V-Blank interrupt
        interrupt(gb, .VBLANK);
    }

    if(LY == LYC && (STAT & STAT_COINCI_INT)) { // STAT Interrupt
        interrupt(gb, .LCDSTAT);
    }
    
    if mode == 2 && STAT & STAT_OAM_INT { // OAM interrupt
        interrupt(gb, .LCDSTAT);
    }

    if mode == 1 && (STAT & STAT_VBLANK_INT) { // V-Blank stat int
        interrupt(gb, .LCDSTAT);
    }
    
    if mode == 0 && STAT & STAT_HBLANK_INT { // H-Blank interrupt
        interrupt(gb, .LCDSTAT);
    }
}

render_sprite_line :: (gb: *Gameboy, p: Palette, line: TileLine, x: *u32, y: u8, is_x_flipped: bool, priority: bool) {
    for i: 0..8 {
        if << x >= SCREEN_WIDTH then return;
        color_val : u8;
        if(!is_x_flipped) {
            color_val = (line.data_2 >> (7-i) & 1);
            color_val <<= 1;
            color_val |=  (line.data_1 >> (7-i) & 1);
        } else {
            color_val = (line.data_2 >> (i) & 1);
            color_val <<= 1;
            color_val |=  (line.data_1 >> (i) & 1);
        }
        paletted_color := p.array[color_val];
        if(color_val != 0) {
            if(!priority || gb.lcd_screen[y][<< x] < 1)            
                gb.lcd_screen[y][<< x] = paletted_color;
        }

        (<<x) += 1;
    }
}

draw_background_line :: (gb: *Gameboy, LY: u8, SCX: u8, map_line: u8, tile_line: u8, base_address: u16, tile_data_select: bool) {
    bg_pal : Palette = get_palette_from_byte(read(gb, IO_BGP));

    for x: 0..SCREEN_WIDTH - 1 {
        map_x: u8 = xx(((SCX + x) / 8) % 32);
        address: u16 = (base_address + map_x) + (cast(u16)map_line * 32);
        tile_id: u8 = read(gb, address);
        tl: TileLine = get_tile_line(gb, tile_id, tile_data_select, tile_line);
        
        tile_x: u8 = xx((x + SCX) % 8);
        color_val: u8 = (tl.data_2 >> (7-tile_x) & 1);
        color_val <<= 1;
        color_val |= (tl.data_1 >> (7-tile_x) & 1);
        gb.lcd_screen[LY][x] = bg_pal.array[color_val];
    }
}

get_tile_line :: (gb: *Gameboy, tile_offset: u8, mode: bool, line: u8) -> TileLine {
    result: TileLine;
    if(mode) {
        result.data_1 = read(gb, cast(u16)0x8000 + cast(u16)(tile_offset) * 16 + cast(u16)(line * 2));
        result.data_2 = read(gb, cast(u16)0x8000 + cast(u16)(tile_offset) * 16 + cast(u16)(line * 2) + 1);
    } else {
        tile_addr : s8 = cast,no_check(s8) tile_offset;
        //tile_addr *= 16;
        addr : u16 = xx(0x9000 + (cast(s32)tile_addr * 16) + (line * 2));
        result.data_1 = read(gb, addr);
        result.data_2 = read(gb, addr + 1);
    }
    return result;
}

background :: (gb: *Gameboy, LCDC : Lcdc_Flags, LY: u8) {
    SCY: u8 = read(gb, IO_SCY);
    SCX: u8 = read(gb, IO_SCX);
    BGP: u8 = read(gb, IO_BGP);

    tile_data_select := (LCDC & .BG_TILE_DATA_SELECT) != 0;
    bg_tile_map_select := (LCDC & .BG_TILE_MAP_DISPLAY_SELECT) != 0;
    tile_map_base_address : u16 = xx ifx bg_tile_map_select then 0x9C00 else 0x9800;

    map_line  : u8 = xx (((cast(u16)LY + cast(u16)SCY) / cast(u16)8) % cast(u16)32);
    tile_line : u8 = xx ((cast(u16)LY + cast(u16)SCY) % cast(u16)8);

    draw_background_line(gb, LY, SCX, map_line, tile_line, tile_map_base_address, tile_data_select);
}

window :: (gb: *Gameboy, LCDC: Lcdc_Flags, LY: u8) {
    window_display:bool = xx(LCDC >> 5 & 1);
    if(window_display) {
        WY:u8 = read(gb, IO_WY);
        WX:u8 = read(gb, IO_WX) - 8;
            
        if(LY < WY)
            return;

        map_line: u8 = ((LY - WY) / 8);
        if (map_line > 32 || map_line < 0) 
            return;
        tile_line: u8 = (LY - WY) % 8;
    
        tile_data_select := (LCDC & .BG_TILE_DATA_SELECT) != 0;
        bg_tile_map_select := (LCDC & .BG_TILE_MAP_DISPLAY_SELECT) != 0;
        tile_map_base_address : u16 = xx ifx bg_tile_map_select then 0x9800 else 0x9C00;
        
        draw_background_line(gb, LY, WX, map_line, tile_line, tile_map_base_address, tile_data_select);
    }
}

get_OAM_sprite:: (gb: *Gameboy, tile_id: u16) -> OAMSprite {
    result : OAMSprite;
    if(tile_id > 40) {
        log("Attempting to access tile No %. This is out of the bounds of the OAM", tile_id);
    }
    result.y     = read(gb, 0xFE00 + (tile_id * 4));
    result.x     = read(gb, 0xFE00 + (tile_id * 4) + 1);
    result.tile  = read(gb, 0xFE00 + (tile_id * 4) + 2);
    result.flags = read(gb, 0xFE00 + (tile_id * 4) + 3);
    return result;
}

OAM :: (gb: *Gameboy, LCDC: Lcdc_Flags, LY: u8) {
    x:u16 = 0;
    sprite_count : u8 = 0;
    sprite_size := (LCDC & .SPRITE_SIZE) != 0;
    OBP0 : u8 = read(gb, IO_OBP0);
    OBP1 : u8 = read(gb, IO_OBP1);
    for i: 0..40 {
        if(sprite_count >= 10) 
            break;
        sprite: OAMSprite = get_OAM_sprite(gb, xx i);
        if(sprite.y < 0x10)
                continue;
        is_palette_1:bool = xx(sprite.flags >> 4 & 1);
        is_x_flipped:bool = xx(sprite.flags >> 5 & 1);
        is_y_flipped:bool = xx(sprite.flags >> 6 & 1);
        priority:bool     = xx(sprite.flags >> 7 & 1);
        pal: Palette;
        if(is_palette_1) {
            pal = get_palette_from_byte(OBP1);
        } else {
            pal = get_palette_from_byte(OBP0);
        }
        
        sprite.y -= 0x10;
        if(sprite.y <= LY && sprite.y + 8 > LY) {
            // Draw tile
            line:u8 = LY - sprite.y;
            tile:u8 = sprite.tile;
            if (is_y_flipped) {
                if (sprite_size)
                    tile += 1;
                line = 7 - line;
            }
            tl:TileLine = get_tile_line(gb, tile, true, line);
            sx:u32 = sprite.x - 7;
            render_sprite_line(gb, pal, tl, *sx, LY, is_x_flipped, priority);
            sprite_count+=1;
        } else if(sprite_size && sprite.y + 8 <= LY && sprite.y + 16 > LY) {
            line:u8 = LY - sprite.y - 8;
            tile:u8 = sprite.tile + 1;
            if (is_y_flipped) {
                line = 7 - line;
                tile -= 1;
            }
            tl:TileLine = get_tile_line(gb, tile, true, line);
            sx:u32 = sprite.x - 7;
            render_sprite_line(gb, pal, tl, *sx, LY, is_x_flipped, priority);
            sprite_count += 1;

        } else {
            continue;
        }
    }
}
