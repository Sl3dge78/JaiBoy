
tiles_tex: u32;
map_1_tex: u32;
map_2_tex: u32;

windows_open : bool;

hex :: (val: u16) -> Basic.FormatInt #expand {
    return Basic.formatInt(val, 16, 4);
}

hex :: (val: u8) -> Basic.FormatInt #expand {
    return Basic.formatInt(val, 16, 2);
}

bin :: (val: u8) -> Basic.FormatInt #expand {
    return Basic.formatInt(val, 2, 8);
}

bin :: (val: u16) -> Basic.FormatInt #expand {
    return Basic.formatInt(val, 2, 16);
}

breakpoint :: (gb : *Gameboy) {
    gb.step_through = true;
    gb.cycles_left = 0;
}

init_debug :: () {
    glGenTextures(1, *map_1_tex);
    glBindTexture(GL_TEXTURE_2D, map_1_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glGenTextures(1, *map_2_tex);
    glBindTexture(GL_TEXTURE_2D, map_2_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glGenTextures(1, *tiles_tex);
    glBindTexture(GL_TEXTURE_2D, tiles_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
}

disassembly_from_pc := true;
disassembly_addr : u16 = 0;
disassembly_addr_buf: [32]u8;
breakpoint_buf: [32]u8;
breakpoints: [..]u16;

draw_debug :: (gb : *Gameboy) {

    if ImGui.Begin("Debug") {
        ImGui.Text("pc   : 0x%", Basic.formatInt(gb.pc, 16, 4));
        ImGui.Text("af   : 0x%", Basic.formatInt(gb.a, 16, 2));
        ImGui.Text("bc   : 0x%", Basic.formatInt(gb.bc, 16, 4));
        ImGui.Text("de   : 0x%", Basic.formatInt(gb.de, 16, 4));
        ImGui.Text("hl   : 0x%", Basic.formatInt(gb.hl, 16, 4));
        ImGui.Text("sp   : 0x%", Basic.formatInt(gb.sp, 16, 4));
        ImGui.Text("ZNHC : %",   Basic.formatInt(gb.f >> 4, 2, 4));
        ImGui.Text("(hl) : 0x%", Basic.formatInt(read(gb, gb.hl), 16, 2));
        ImGui.Text("-");
        ImGui.Text("IO_JOY  (FF00): 0x%", hex(gb.mem[IO_JOY]));
        ImGui.Text("IO_SB   (FF01): 0x%", hex(gb.mem[IO_SB]));
        ImGui.Text("IO_SC   (FF02): 0x%", hex(gb.mem[IO_SC]));
        ImGui.Text("IO_DIV  (FF04): 0x%", hex(gb.mem[IO_DIV]));
        ImGui.Text("IO_TIMA (FF05): 0x%", hex(gb.mem[IO_TIMA]));
        ImGui.Text("IO_TMA  (FF06): 0x%", hex(gb.mem[IO_TMA]));
        ImGui.Text("IO_TAC  (FF07): 0x%", hex(gb.mem[IO_TAC]));
        ImGui.Text("-");
        ImGui.Text("LCDC (FF40) : 0b% - 0x%", bin(gb.mem[IO_LCDC]), hex(gb.mem[IO_LCDC]));
        ImGui.Text("STAT (FF41) : 0b% - 0x%", bin(gb.mem[IO_STAT]), hex(gb.mem[IO_STAT]));
        ImGui.Text("SCY  (FF42) : 0x%", hex(gb.mem[IO_SCY]));
        ImGui.Text("SCX  (FF43) : 0x%", hex(gb.mem[IO_SCX]));
        ImGui.Text("LY   (FF44) : 0x%", hex(gb.mem[IO_LY]));
        ImGui.Text("LYC  (FF45) : 0x%", hex(gb.mem[IO_LYC]));
        ImGui.Text("DMA  (FF46) : 0x%", hex(gb.mem[IO_DMA]));
        ImGui.Text("BGP  (FF47) : 0x%", hex(gb.mem[IO_BGP]));
        ImGui.Text("OBP0 (FF48) : 0x%", hex(gb.mem[IO_OBP0]));
        ImGui.Text("OBP1 (FF49) : 0x%", hex(gb.mem[IO_OBP1]));
        ImGui.Text("WY   (FF4A) : 0x%", hex(gb.mem[IO_WY]));
        ImGui.Text("WX   (FF4B) : 0x%", hex(gb.mem[IO_WX]));
        ImGui.Text("-");
        ImGui.Text("IME         : %", gb.ime);
        ImGui.Text("IF   (FF0F) : 0b% - 0x%", bin(gb.mem[IO_IF]), hex(gb.mem[IO_IF]));
        ImGui.Text("IE   (FFFF) : 0b% - 0x%", bin(gb.mem[IO_IE]), hex(gb.mem[IO_IE]));
        ImGui.Text("CLOCKMUL    : %", gb.clock_mul);
        ImGui.Text("HALTED    : %", gb.halted);
    }
    ImGui.End();

    if ImGui.Begin("Disassembly") {
        if ImGui.TreeNode("Breakpoints") {
            ImGui.InputText("New BP", breakpoint_buf.data, breakpoint_buf.count);
            ImGui.SameLine();
            if ImGui.Button("Add") {
                got_addr, success := Basic.string_to_int(to_string(breakpoint_buf.data), 16);
                if success {
                    Basic.array_add(*breakpoints, xx got_addr);
                }
            }
            for *breakpoints {
                ImGui.Text("% - %", it_index, hex(<<it));
                ImGui.SameLine();
                if ImGui.Button("-") {
                    remove it;
                }
            }
            ImGui.TreePop();
        }
        ImGui.Checkbox("From PC", *disassembly_from_pc);
        if !disassembly_from_pc {
            ImGui.InputText("Start address", disassembly_addr_buf.data, disassembly_addr_buf.count);
            got_addr, success := Basic.string_to_int(to_string(disassembly_addr_buf.data), 16);
            disassembly_addr = xx got_addr;
        } else {
            disassembly_addr = gb.pc;
        }
        
        addr := disassembly_addr;
        for 0..20 {
            addr = print_instruction(gb, addr);
        }
    }
    ImGui.End();

    if ImGui.Begin("TILES") {
        draw_tiles(gb);
    }
    ImGui.End();

    
        draw_map(gb);
   

    if ImGui.Begin("Callstack") {
        for gb.call_stack {
            ImGui.Text("FROM: 0x% - TO: 0x%", hex(it.from), hex(it.to));
        }
    }
    ImGui.End();

    if ImGui.Begin("Rom") {
        ImGui.Text("ROM BANK : 0x%", hex(gb.rom.rom_bank));
        ImGui.Text("RAM BANK : 0x%", hex(gb.rom.ram_bank));  
    } 
    ImGui.End();

    debug_audio(gb);
    
}

print_instruction :: (gb : *Gameboy, addr : u16) -> u16 {
    op := OPCODE_DESC_TABLE[read(gb, addr)];
    builder : Basic.String_Builder;
    
    // Addr
    ImGui.Text("%", Basic.formatInt(addr, 16, 4));
    

    // Bytes
    Basic.print_to_builder(*builder, "% ", Basic.formatInt(read(gb, addr), 16, 2));
    for 1..op.bytes - 1 {
        Basic.print_to_builder(*builder, "% ", Basic.formatInt(read(gb, addr + it), 16, 2));
    }
    builder_string := Basic.builder_to_string(*builder);
    Basic.reset(*builder);
    defer Basic.free(builder_string);
    ImGui.SameLine(50);
    ImGui.Text(builder_string);
        
    // Desc
    ImGui.SameLine(150);
    ImGui.Text("%", op.desc);

    // Operands
    i := op.bytes - 1;
    while (i >= 1) {
        Basic.print_to_builder(*builder, "%", Basic.formatInt(read(gb, addr + i), 16, 2));
        i -= 1;
    }
    operand_string := Basic.builder_to_string(*builder);
    defer Basic.free(operand_string);
    ImGui.SameLine(275);
    ImGui.Text("%", operand_string);
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
    
    glBindTexture(GL_TEXTURE_2D, tiles_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, tex_width, tex_height, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);

    ImGui.Image(xx tiles_tex, ImGui.ImVec2.{tex_width * 2, tex_height * 2});
}

draw_map :: (gb: *Gameboy) {
    if ImGui.Begin("MAP") {
        ImGui.Text("MAP 1");
        MAP_SIZE:: 32 * 8;
        data: [MAP_SIZE * MAP_SIZE]Color;

        LCDC := gb.mem[IO_LCDC];
        tile_data_select: bool = (LCDC >> 4 & 1) == 1;
        base_addr: u16 = 0x9800;
        
        for y : 0..31 {
            for x : 0..31 {
                addr := base_addr + x + y * 32;
                tile_id := gb.mem[addr];
                for line : 0..7 {
                    tl := get_tile_line(gb, tile_id, tile_data_select, xx line);
                    for row: 0..7 {
                        pixel: u8 = (tl.data_2 >> (7 - row) & 1);
                        pixel <<= 1;
                        pixel |= (tl.data_1 >> (7 - row) & 1);
                        color := palette[pixel];

                        arx := (x * 8) + row;
                        ary := (y * 8) + line;

                        data[arx + (ary * MAP_SIZE)] = color;
                    }
                }
            }
        }

        glBindTexture(GL_TEXTURE_2D, map_1_tex);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, MAP_SIZE, MAP_SIZE, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);  
        ImGui.Image(xx map_1_tex, ImGui.ImVec2.{MAP_SIZE, MAP_SIZE});
    
        ImGui.Text("MAP 2");
        base_addr = 0x9C00;
        
        for y : 0..31 {
            for x : 0..31 {
                addr := base_addr + x + y * 32;
                tile_id := gb.mem[addr];
                for line : 0..7 {
                    tl := get_tile_line(gb, tile_id, tile_data_select, xx line);
                    for row: 0..7 {
                        pixel: u8 = (tl.data_2 >> (7 - row) & 1);
                        pixel <<= 1;
                        pixel |= (tl.data_1 >> (7 - row) & 1);
                        color := palette[pixel];

                        arx := (x * 8) + row;
                        ary := (y * 8) + line;

                        data[arx + (ary * MAP_SIZE)] = color;
                    }
                }
            }
        }

        glBindTexture(GL_TEXTURE_2D, map_2_tex);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, MAP_SIZE, MAP_SIZE, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);  
        ImGui.Image(xx map_2_tex, ImGui.ImVec2.{MAP_SIZE, MAP_SIZE});
    }
    ImGui.End();
}

debug_audio :: (gb: *Gameboy) {
    if (ImGui.Begin("Audio")) {
        ImGui.Text("%", Basic.formatStruct(gb.apu, 1, true));
        ImGui.Text("LFSR : %", bin(gb.apu.channel4.LFSR));
        ImGui.Text("NR14 : %", bin(gb.mem[IO_NR14]));
        ImGui.Text("NR22 : %", bin(gb.mem[IO_NR22]));
        ImGui.Text("NR24 : %", bin(gb.mem[IO_NR24]));
        ImGui.Text("NR32 : %", bin(gb.mem[IO_NR32]));
        ImGui.Text("NR34 : %", bin(gb.mem[IO_NR34]));        
    }
    ImGui.End();
}