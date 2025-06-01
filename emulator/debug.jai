
debug_window: *SDL_Window;
state: Immediate_State;

hex :: (val: u16) -> FormatInt #expand {
    return formatInt(val, 16, 4);
}

hex :: (val: u8) -> FormatInt #expand {
    return formatInt(val, 16, 2);
}

bin :: (val: u8) -> FormatInt #expand {
    return formatInt(val, 2, 8);
}

bin :: (val: u16) -> FormatInt #expand {
    return formatInt(val, 2, 16);
}

init_debug :: () {
    debug_window = SDL_CreateWindow("Debug",500, 500, SDL_WINDOW_BORDERLESS);
    state = init_immediate(debug_window);
    log("init");
}

deinit_debug :: () {
    log("deinit");
    deinit_immediate(*state);
    SDL_DestroyWindow(debug_window);
}

draw_debug :: (gb : *Gameboy) {
    cursor();
    camera(0, 0);
    SDL_SetRenderDrawColor(state.renderer, 10, 10, 10, 255);
    SDL_RenderClear(state.renderer);

    // if ImGui.Begin("Debug") {
    SDL_SetRenderDrawColor(state.renderer, 255, 255, 255, 255);
    text(tprint("pc   : 0x%", formatInt(gb.pc, 16, 4)));
    text(tprint("af   : 0x%", formatInt(gb.a, 16, 2)));
    text(tprint("bc   : 0x%", formatInt(gb.bc, 16, 4)));
    text(tprint("de   : 0x%", formatInt(gb.de, 16, 4)));
    text(tprint("hl   : 0x%", formatInt(gb.hl, 16, 4)));
    text(tprint("sp   : 0x%", formatInt(gb.sp, 16, 4)));
    text(tprint("ZNHC : %",   formatInt(gb.f >> 4, 2, 4)));
    text(tprint("(hl) : 0x%", formatInt(read(gb, gb.hl), 16, 2)));
    state.cy += 12;
    text(tprint("IME         : %", gb.ime));
    text(tprint("IF   (FF0F) : 0b% - 0x%", bin(gb.mem[IO_IF]), hex(gb.mem[IO_IF])));
    text(tprint("IE   (FFFF) : 0b% - 0x%", bin(gb.mem[IO_IE]), hex(gb.mem[IO_IE])));
    text(tprint("CLOCKMUL    : %", gb.clock_mul));
    text(tprint("HALTED    : %", gb.halted));
    cursor(100);
    text(tprint("IO_JOY  (FF00): 0x%", hex(gb.mem[IO_JOY])));
    text(tprint("IO_SB   (FF01): 0x%", hex(gb.mem[IO_SB])));
    text(tprint("IO_SC   (FF02): 0x%", hex(gb.mem[IO_SC])));
    text(tprint("IO_DIV  (FF04): 0x%", hex(gb.mem[IO_DIV])));
    text(tprint("IO_TIMA (FF05): 0x%", hex(gb.mem[IO_TIMA])));
    text(tprint("IO_TMA  (FF06): 0x%", hex(gb.mem[IO_TMA])));
    text(tprint("IO_TAC  (FF07): 0x%", hex(gb.mem[IO_TAC])));
    cursor(250);
    text(tprint("LCDC (FF40) : 0b% - 0x%", bin(gb.mem[IO_LCDC]), hex(gb.mem[IO_LCDC])));
    text(tprint("STAT (FF41) : 0b% - 0x%", bin(gb.mem[IO_STAT]), hex(gb.mem[IO_STAT])));
    text(tprint("SCY  (FF42) : 0x%", hex(gb.mem[IO_SCY])));
    text(tprint("SCX  (FF43) : 0x%", hex(gb.mem[IO_SCX])));
    text(tprint("LY   (FF44) : 0x%", hex(gb.mem[IO_LY])));
    text(tprint("LYC  (FF45) : 0x%", hex(gb.mem[IO_LYC])));
    text(tprint("DMA  (FF46) : 0x%", hex(gb.mem[IO_DMA])));
    text(tprint("BGP  (FF47) : 0x%", hex(gb.mem[IO_BGP])));
    text(tprint("OBP0 (FF48) : 0x%", hex(gb.mem[IO_OBP0])));
    text(tprint("OBP1 (FF49) : 0x%", hex(gb.mem[IO_OBP1])));
    text(tprint("WY   (FF4A) : 0x%", hex(gb.mem[IO_WY])));
    text(tprint("WX   (FF4B) : 0x%", hex(gb.mem[IO_WX])));

    cursor(0, 130);
    line(0, 130, 500, 130);
    text("Disassembly");
    state.cy += 12;

    addr := gb.pc;
    for 0..20 {
        addr = print_instruction(gb, addr);

    }

    // if ImGui.Begin("TILES") {
    //     draw_tiles(gb);
    // }
    // ImGui.End();
    //
    //
    //     draw_map(gb);
    //
    //
    // if ImGui.Begin("Callstack") {
    //     for gb.call_stack {
    //         ImGui.Text("FROM: 0x% - TO: 0x%", hex(it.from), hex(it.to));
    //     }
    // }
    // ImGui.End();
    //
    // if ImGui.Begin("Rom") {
    //     ImGui.Text("ROM BANK : 0x%", hex(gb.rom.rom_bank));
    //     ImGui.Text("RAM BANK : 0x%", hex(gb.rom.ram_bank));  
    // } 
    // ImGui.End();

    debug_audio(gb);
    cursor(0, 488);
    text("[F5] hide this | [F9/SPACE] step | [F7/N] Trace | [R] Reset");
    SDL_RenderPresent(state.renderer);
    
}

print_instruction :: (gb : *Gameboy, addr : u16) -> u16 {
    op := OPCODE_DESC_TABLE[read(gb, addr)];
    builder : String_Builder;
    
    // Addr
    print_to_builder(*builder, "0x% ", formatInt(addr, 16, 4));

    // Bytes
    print_to_builder(*builder, "% ", formatInt(read(gb, addr), 16, 2));
    for 1..op.bytes - 1 {
        print_to_builder(*builder, "% ", formatInt(read(gb, addr + it), 16, 2));
    }
    while builder_string_length(*builder) < 20 {
        append(*builder, " ");
    }

    // Desc
    print_to_builder(*builder, "%", op.desc);
    while builder_string_length(*builder) < 32 {
        append(*builder, " ");
    }

    // Operands
    i := op.bytes - 1;
    while (i >= 1) {
        print_to_builder(*builder, "%", formatInt(read(gb, addr + i), 16, 2));
        i -= 1;
    }

    builder_string := builder_to_string(*builder,, temp);
    text(builder_string);
    return addr + op.bytes;
}

draw_tiles :: (gb: *Gameboy) {

    tiles_per_line :: 16;

    tex_height :: 8 * 8 * 3; // 8 lines * Tile height * 3 blocks
    tex_width  :: 8 * 16;    // Tile width * 16 tiles/line

    data : [tex_height * tex_width]Color;
    
    ptr : u16 = 0x8000;

    while ptr < 0x9800 {
        rel := (ptr - 0x8000) / 2;
        tile_id := rel / 8;
        line := rel % 8;

        tile_x := tile_id % tiles_per_line;
        tile_y := tile_id / tiles_per_line;

        data_1 := gb.mem[ptr];
        data_2 := gb.mem[ptr + 1];

        tex_x := tile_x * 8;
        tex_y := (tile_y * 8) + line;

        for 0..7 {
            shift := 7 - it;
            col := (data_1 >> shift) & 1 | (((data_2 >> shift) & 1) << 1);
            data[tex_x + it + tex_y * tex_width] = palette[col];
        }

        ptr += 2;
    }
    
    // @TODO
    // glBindTexture(GL_TEXTURE_2D, tiles_tex);
    // glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, tex_width, tex_height, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);
    //
    // ImGui.Image(xx tiles_tex, ImGui.ImVec2.{tex_width * 2, tex_height * 2});
}

draw_map :: (gb: *Gameboy) {
    // if ImGui.Begin("MAP") {
    //     ImGui.Text("MAP 1");
    //     MAP_SIZE:: 32 * 8;
    //     data: [MAP_SIZE * MAP_SIZE]Color;
    //
    //     LCDC := gb.mem[IO_LCDC];
    //     tile_data_select: bool = (LCDC >> 4 & 1) == 1;
    //     base_addr: u16 = 0x9800;
    //
    //     for y : 0..31 {
    //         for x : 0..31 {
    //             addr := base_addr + x + y * 32;
    //             tile_id := gb.mem[addr];
    //             for line : 0..7 {
    //                 tl := get_tile_line(gb, tile_id, tile_data_select, xx line);
    //                 for row: 0..7 {
    //                     pixel: u8 = (tl.data_2 >> (7 - row) & 1);
    //                     pixel <<= 1;
    //                     pixel |= (tl.data_1 >> (7 - row) & 1);
    //                     color := palette[pixel];
    //
    //                     arx := (x * 8) + row;
    //                     ary := (y * 8) + line;
    //
    //                     data[arx + (ary * MAP_SIZE)] = color;
    //                 }
    //             }
    //         }
    //     }
    //
    //     glBindTexture(GL_TEXTURE_2D, map_1_tex);
    //     glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    //     glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, MAP_SIZE, MAP_SIZE, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);  
    //     ImGui.Image(xx map_1_tex, ImGui.ImVec2.{MAP_SIZE, MAP_SIZE});
    //
    //     ImGui.Text("MAP 2");
    //     base_addr = 0x9C00;
    //
    //     for y : 0..31 {
    //         for x : 0..31 {
    //             addr := base_addr + x + y * 32;
    //             tile_id := gb.mem[addr];
    //             for line : 0..7 {
    //                 tl := get_tile_line(gb, tile_id, tile_data_select, xx line);
    //                 for row: 0..7 {
    //                     pixel: u8 = (tl.data_2 >> (7 - row) & 1);
    //                     pixel <<= 1;
    //                     pixel |= (tl.data_1 >> (7 - row) & 1);
    //                     color := palette[pixel];
    //
    //                     arx := (x * 8) + row;
    //                     ary := (y * 8) + line;
    //
    //                     data[arx + (ary * MAP_SIZE)] = color;
    //                 }
    //             }
    //         }
    //     }
    //
    //     glBindTexture(GL_TEXTURE_2D, map_2_tex);
    //     glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    //     glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, MAP_SIZE, MAP_SIZE, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);  
    //     ImGui.Image(xx map_2_tex, ImGui.ImVec2.{MAP_SIZE, MAP_SIZE});
    // }
    // ImGui.End();
}

debug_audio :: (gb: *Gameboy) {
    // if (ImGui.Begin("Audio")) {
    //     ImGui.Text("%", formatStruct(gb.apu, 1, true));
    //     ImGui.Text("LFSR : %", bin(gb.apu.channel4.LFSR));
    //     ImGui.Text("NR14 : %", bin(gb.mem[IO_NR14]));
    //     ImGui.Text("NR22 : %", bin(gb.mem[IO_NR22]));
    //     ImGui.Text("NR24 : %", bin(gb.mem[IO_NR24]));
    //     ImGui.Text("NR32 : %", bin(gb.mem[IO_NR32]));
    //     ImGui.Text("NR34 : %", bin(gb.mem[IO_NR34]));        
    // }
    // ImGui.End();
}

#load "../common/opcodes.jai";
