Basic :: #import "Basic";
File :: #import "File";
ImGui :: #import "ImGui";
Compiler :: #import "Compiler";
#import "GL";
#load "gb.jai";
#load "opcodes.jai";
#load "debug.jai";

#import "SDL";

SKIP_PC_INSTR :: u8.[
    0x10,
    0x76,
    0xc0,
    0xc2,
    0xc3,
    0xc4,
    0xc7,
    0xc9,
    0xcd,
    0xcf,
    0xd0,    
    0xd2,
    0xd4,
    0xd7,
    0xd9,
    0xdf,
    0xe7,
    0xe9,
    0xef,
    0xf7,
    0xff,
];

reset_for_testing :: (cpu : *CPU) {
    cpu.pc    = ROM_ENTRY;
    cpu.sp    = 0xFFFE;
    cpu.a     = 0;
    cpu.b     = 0;
    cpu.c     = 0;
    cpu.d     = 0;
    cpu.e     = 0;
    cpu.f     = 0;
    cpu.h     = 0;
    cpu.l     = 0;
}

clear_memory :: (mem: []u8) {
    for *mem {
        << it = 0;
    }
}

run_instruction :: (gb: *Gameboy, op: []u8) {
    // Write instruction
    for op {
        gb.rom.rom_data[ROM_ENTRY + it_index] = it;
    }
    gb.pc = ROM_ENTRY;
    execute(gb);
}

test_eq :: (val : u16, expected : u16, name : string) -> bool {
    if val != expected {
        Basic.print("  CPU: % is 0x%. Expected 0x%.\n", name, hex(val), hex(expected));
        return false;
    } else {
        return true;
    }
}

test_cpu :: (gb: CPU, expected: CPU, pc: bool, sp: bool) -> bool {
    result := 0;
    result += xx test_eq(gb.a, expected.a, "a");
    result += xx test_eq(gb.f, expected.f, "f");
    result += xx test_eq(gb.b, expected.b, "b");
    result += xx test_eq(gb.c, expected.c, "c");
    result += xx test_eq(gb.d, expected.d, "d");
    result += xx test_eq(gb.e, expected.e, "e");
    result += xx test_eq(gb.f, expected.f, "f");
    result += xx test_eq(gb.h, expected.h, "h");
    result += xx test_eq(gb.l, expected.l, "l");
    if sp {
        result += xx test_eq(gb.sp, expected.sp, "sp");
    } else {
        result += xx test_eq(gb.sp, 0xFFFE, "sp");
    }
    if pc {
        result += xx test_eq(gb.pc, expected.pc, "pc");
    } else {
        result += 1;
    }

    return result == 11;
}

test_mem :: (mem: []u8, addr: []u16, expect: []u8) -> bool {
    result := 0;
    for addr {
        result += xx (mem[it] == expect[it_index]);
        if mem[it] != expect[it_index] {
            Basic.print("  MEM: Addr 0x% is 0x% expected 0x%.\n", hex(it), hex(mem[it]), hex(expect[it_index]));
        }
    }
    return result == addr.count;
}

test_instruction :: (gb: *Gameboy, instr: []u8, starting: CPU, expected: CPU, force_sp_check: bool = false) {
    Basic.print("0x% - %:\n", hex(instr[0]), OPCODE_DESC_TABLE[instr[0]].desc);
    gb.cpu = starting;
    if starting.sp == 0x00 && !force_sp_check {
        gb.sp = 0xFFFE;
    }
    run_instruction(gb, instr);
    
    test_cpu(gb.cpu, expected, expected.pc != 0, expected.sp != 0 || force_sp_check);
    clear_memory(gb.mem);
}

test_instruction :: (gb: *Gameboy, instr: []u8, starting: CPU, expected: CPU, addr: []u16, expect: []u8) {
    Basic.print("0x% - %:\n", hex(instr[0]), OPCODE_DESC_TABLE[instr[0]].desc);
    gb.cpu = starting;
    if starting.sp == 0x00 {
        gb.sp = 0xFFFE;
    }
    run_instruction(gb, instr);
    
    test_cpu(gb.cpu, expected, expected.pc != 0, expected.sp != 0);
    test_mem(gb.mem, addr, expect);
    clear_memory(gb.mem);
}  

test_pc :: (gb: *Gameboy) {
    ok := 0;
    nok := 0;
    total := 0;
    for OPCODE_DESC_TABLE {
        if it.bytes == 0 then continue;
        instr : [1]u8;
        instr[0] = xx it_index;

        if Basic.array_find(SKIP_PC_INSTR, instr[0]) then continue;

        total += 1;
        reset_for_testing(*gb.cpu);
        run_instruction(gb, instr);
        if gb.pc != ROM_ENTRY + it.bytes {
            nok += 1;
            Basic.log_error("FAIL: 0x% - %", hex(instr[0]), OPCODE_DESC_TABLE[it_index].desc);
        } else {
            ok += 1;
        }
    }
    Basic.log("COMPLETED: TOTAL: %. OK: %. NOK: %", total, ok, nok);
}

test_all :: () {
    Basic.log("Testing");
    Basic.log("--------");
    gb := Basic.New(Gameboy);
    gb.mem.data = Basic.alloc(MEM_SIZE);
    gb.mem.count = MEM_SIZE;

    gb.rom.rom_data.data = Basic.alloc(0x8000);
    gb.rom.rom_data.count = 0x8000;

    gb.rom.ram_data.data = Basic.alloc(0x8000);
    gb.rom.ram_data.count = 0x8000;

    gb.rom.type = .MBC1;

    Basic.log(" PC ");
    test_pc(gb);
    Basic.log("--------");
    Basic.log(" INSTRUCTIONS ");

    reset_for_testing(*gb.cpu);
    test_instruction(gb, .[0x41], .{c = 0x44}, .{c = 0x44, b = 0x44, pc = ROM_ENTRY + 1}); // LD B, C

    // JR NZ, r8
    test_instruction(gb, .[0x20, cast,no_check(u8)(-2)], .{}, .{pc = ROM_ENTRY});      
    test_instruction(gb, .[0x20, 2], .{}, .{pc = ROM_ENTRY + 4});      
    test_instruction(gb, .[0x20, cast,no_check(u8)(-2)], .{f = 0b1000_0000}, .{f = 0b1000_0000});
    test_instruction(gb, .[0x20, 2], .{f = 0b1000_0000}, .{f = 0b1000_0000});

    // JR NC, r8
    test_instruction(gb, .[0x30, cast,no_check(u8)(-2)], .{}, .{pc = ROM_ENTRY});      
    test_instruction(gb, .[0x30, 2], .{}, .{pc = ROM_ENTRY + 4});      
    test_instruction(gb, .[0x30, cast,no_check(u8)(-2)], .{f = 0b0001_0000}, .{f = 0b0001_0000});
    test_instruction(gb, .[0x30, 2], .{f = 0b0001_0000}, .{f = 0b0001_0000});

    // LD (reg), d16
    test_instruction(gb, .[0x01, 0x69, 0x78], .{}, .{bc = 0x7869});
    test_instruction(gb, .[0x11, 0x69, 0x78], .{}, .{de = 0x7869});
    test_instruction(gb, .[0x21, 0x69, 0x78], .{}, .{hl = 0x7869});
    test_instruction(gb, .[0x31, 0x69, 0x78], .{}, .{sp = 0x7869});

    // LD (reg), A
    test_instruction(gb, .[0x02], .{a = 0x69, bc = 0xC102}, .{a = 0x69, bc = 0xC102}, .[0xC102], .[0x69]);
    test_instruction(gb, .[0x12], .{a = 0x69, de = 0xC102}, .{a = 0x69, de = 0xC102}, .[0xC102], .[0x69]);
    test_instruction(gb, .[0x22], .{a = 0x69, hl = 0xC102}, .{a = 0x69, hl = 0xC103}, .[0xC102], .[0x69]);
    test_instruction(gb, .[0x32], .{a = 0x69, hl = 0xC102}, .{a = 0x69, hl = 0xC101}, .[0xC102], .[0x69]);

    // INC REG
    test_instruction(gb, .[0x03], .{bc = 0x0102}, .{bc = 0x0103});
    test_instruction(gb, .[0x13], .{de = 0x0102}, .{de = 0x0103});
    test_instruction(gb, .[0x23], .{hl = 0x0102}, .{hl = 0x0103});
    test_instruction(gb, .[0x33], .{sp = 0x0102}, .{sp = 0x0103});
    test_instruction(gb, .[0x33], .{sp = 0xFFFF}, .{sp = 0x0000}, force_sp_check = true);

    // INC reg @todo test flags
    test_instruction(gb, .[0x04], .{b = 0x01},  .{b = 0x02});
    test_instruction(gb, .[0x14], .{d = 0x01},  .{d = 0x02});
    test_instruction(gb, .[0x24], .{h = 0x01},  .{h = 0x02});
    test_instruction(gb, .[0x34], .{hl = 0xFF80}, .{hl = 0xFF80}, .[0xFF80], .[0x01]);

    // DEC (reg) @todo test flags
    test_instruction(gb, .[0x05], .{b = 0x02},  .{b = 0x01, f = 0b0100_0000});
    test_instruction(gb, .[0x15], .{d = 0x02},  .{d = 0x01, f = 0b0100_0000});
    test_instruction(gb, .[0x25], .{h = 0x02},  .{h = 0x01, f = 0b0100_0000});
    gb.mem[0xC102] = 0x02;
    test_instruction(gb, .[0x35], .{hl = 0xC102}, .{hl = 0xC102, f = 0b0100_0000}, .[0xC102], .[0x01]);

    test_instruction(gb, .[0x05], .{b = 0x01},  .{b = 0x00, f = 0b1100_0000});
    test_instruction(gb, .[0x15], .{d = 0x01},  .{d = 0x00, f = 0b1100_0000});
    test_instruction(gb, .[0x25], .{h = 0x01},  .{h = 0x00, f = 0b1100_0000});
    gb.mem[0xC102] = 0x01;
    test_instruction(gb, .[0x35], .{hl = 0xC102}, .{hl = 0xC102, f = 0b1100_0000}, .[0xC102], .[0x00]);

    // LD reg, d8
    test_instruction(gb, .[0x06, 0x69], .{},  .{b = 0x69});
    test_instruction(gb, .[0x16, 0x69], .{},  .{d = 0x69});
    test_instruction(gb, .[0x26, 0x69], .{},  .{h = 0x69});
    test_instruction(gb, .[0x36, 0x69], .{hl = 0xC102}, .{hl = 0xC102}, .[0xC102], .[0x69]);

    test_instruction(gb, .[0x07], .{a = 0b1000_1000},  .{a = 0b0001_0001, f = C_FLAG});
    test_instruction(gb, .[0x07], .{a = 0b0000_1000},  .{a = 0b0001_0000});

    test_instruction(gb, .[0x17], .{a = 0b1000_1000},  .{a = 0b0001_0000, f = C_FLAG});
    test_instruction(gb, .[0x17], .{a = 0b0000_1000},  .{a = 0b0001_0000});
    test_instruction(gb, .[0x17], .{a = 0b0000_1000, f = C_FLAG},  .{a = 0b0001_0001});

    test_instruction(gb, .[0x37], .{},  .{f = C_FLAG});
    test_instruction(gb, .[0x37], .{f = Z_FLAG},  .{f = Z_FLAG | C_FLAG});
    test_instruction(gb, .[0x37], .{f = H_FLAG | N_FLAG},  .{f = C_FLAG});

    // LD (a16),SP
    test_instruction(gb, .[0x08, 0x80, 0xFF], .{sp = 0x7869},  .{sp = 0x7869}, .[0xFF80, 0xFF81], .[0x69, 0x78]);

    // JR, r8
    test_instruction(gb, .[0x18, cast,no_check(u8)(-2)], .{}, .{pc = ROM_ENTRY});      
    test_instruction(gb, .[0x18, 2], .{}, .{pc = ROM_ENTRY + 4});      
    test_instruction(gb, .[0x18, cast,no_check(u8)(-2)], .{f = 0b1000_0000}, .{f = 0b1000_0000, pc = ROM_ENTRY});
    test_instruction(gb, .[0x18, 2], .{f = 0b1000_0000}, .{f = 0b1000_0000, pc = ROM_ENTRY + 4});

    // JR Z, r8
    test_instruction(gb, .[0x28, cast,no_check(u8)(-2)], .{}, .{});      
    test_instruction(gb, .[0x28, 2], .{}, .{});      
    test_instruction(gb, .[0x28, cast,no_check(u8)(-2)], .{f = 0b1000_0000}, .{f = 0b1000_0000, pc = ROM_ENTRY});
    test_instruction(gb, .[0x28, 2], .{f = 0b1000_0000}, .{f = 0b1000_0000, pc = ROM_ENTRY + 4});

    // JR C, r8
    test_instruction(gb, .[0x38, cast,no_check(u8)(-2)], .{}, .{});      
    test_instruction(gb, .[0x38, 2], .{}, .{});      
    test_instruction(gb, .[0x38, cast,no_check(u8)(-2)], .{f = 0b0001_0000}, .{f = 0b0001_0000, pc = ROM_ENTRY});
    test_instruction(gb, .[0x38, 2], .{f = 0b0001_0000}, .{f = 0b0001_0000, pc = ROM_ENTRY + 4});

    // ADD REG, REG  @todo: Test flags
    test_instruction(gb, .[0x09], .{hl = 0x0101, bc = 0x0102}, .{bc = 0x0102, hl = 0x0203});
    test_instruction(gb, .[0x09], .{hl = 0x0F0F, bc = 0x0101}, .{f = H_FLAG, bc = 0x0101, hl = 0x1010});
    test_instruction(gb, .[0x09], .{hl = 0xFFFF, bc = 0x0001}, .{f = H_FLAG | C_FLAG, bc = 0x0001, hl = 0x0000});

    test_instruction(gb, .[0x19], .{hl = 0x0101, de = 0x0102}, .{de = 0x0102, hl = 0x0203});
    test_instruction(gb, .[0x19], .{hl = 0x0F0F, de = 0x0101}, .{f = H_FLAG, de = 0x0101, hl = 0x1010});
    test_instruction(gb, .[0x19], .{hl = 0xFFFF, de = 0x0001}, .{f = H_FLAG | C_FLAG, de = 0x0001, hl = 0x0000});

    test_instruction(gb, .[0x29], .{hl = 0x0102}, .{hl = 0x0204});
    test_instruction(gb, .[0x29], .{hl = 0x0F0F}, .{f = H_FLAG, hl = 0x1E1E});
    test_instruction(gb, .[0x29], .{hl = 0x8FFF}, .{f = H_FLAG | C_FLAG, hl = 0x1FFE});

    test_instruction(gb, .[0x39], .{hl = 0x0101, sp = 0x0102}, .{sp = 0x0102, hl = 0x0203});
    test_instruction(gb, .[0x39], .{hl = 0x0F0F, sp = 0x0101}, .{f = H_FLAG, sp = 0x0101, hl = 0x1010});
    test_instruction(gb, .[0x39], .{hl = 0xFFFF, sp = 0x0001}, .{f = H_FLAG | C_FLAG, sp = 0x0001, hl = 0x0000});

    // LD reg, (REG)
    gb.rom.ram_enabled = true;
    gb.rom.ram_data[0x0102] = 0x69;
    test_instruction(gb, .[0x0A], .{bc = 0xA000 + 0x0102},  .{a = 0x69, bc = 0xA000 + 0x0102});
    gb.rom.ram_data[0x0102] = 0x69;
    test_instruction(gb, .[0x1A], .{de = 0xA000 + 0x0102},  .{a = 0x69, de = 0xA000 + 0x0102});
    gb.rom.ram_data[0x0102] = 0x69;
    test_instruction(gb, .[0x2A], .{hl = 0xA000 + 0x0102},  .{a = 0x69, hl = 0xA000 + 0x0103});
    gb.rom.ram_data[0x0102] = 0x69;
    test_instruction(gb, .[0x3A], .{hl = 0xA000 + 0x0102},  .{a = 0x69, hl = 0xA000 + 0x0101});

    // DEC REG
    test_instruction(gb, .[0x0B], .{bc = 0x0102}, .{bc = 0x0101});
    test_instruction(gb, .[0x1B], .{de = 0x0102}, .{de = 0x0101});
    test_instruction(gb, .[0x2B], .{hl = 0x0102}, .{hl = 0x0101});
    test_instruction(gb, .[0x3B], .{sp = 0x0102}, .{sp = 0x0101});
    test_instruction(gb, .[0x3B], .{sp = 0x0000}, .{sp = 0xFFFF}, force_sp_check = true);

    // INC reg @todo test flags
    test_instruction(gb, .[0x0C], .{c = 0x01}, .{c = 0x02});
    test_instruction(gb, .[0x1C], .{e = 0x01}, .{e = 0x02});
    test_instruction(gb, .[0x2C], .{l = 0x01}, .{l = 0x02});
    test_instruction(gb, .[0x3C], .{a = 0x01}, .{a = 0x02});

    // DEC reg @todo test flags
    test_instruction(gb, .[0x0D], .{c = 0x01}, .{c = 0x00, f = 0b1100_0000});
    test_instruction(gb, .[0x1D], .{e = 0x01}, .{e = 0x00, f = 0b1100_0000});
    test_instruction(gb, .[0x2D], .{l = 0x01}, .{l = 0x00, f = 0b1100_0000});
    test_instruction(gb, .[0x3D], .{a = 0x01}, .{a = 0x00, f = 0b1100_0000});

    // LD reg, d8
    test_instruction(gb, .[0x0E, 0x69], .{}, .{c = 0x69});
    test_instruction(gb, .[0x1E, 0x69], .{}, .{e = 0x69});
    test_instruction(gb, .[0x2E, 0x69], .{}, .{l = 0x69});
    test_instruction(gb, .[0x3E, 0x69], .{}, .{a = 0x69});

    // Cx Dx Ex Fx
    // RET NZ
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC0], .{sp = 0xFFFC}, .{pc = 0x0203, sp = 0xFFFE});
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC0], .{f = Z_FLAG, sp = 0xFFFC}, .{f = Z_FLAG, sp = 0xFFFC});

    // RET NC
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xD0], .{sp = 0xFFFC}, .{pc = 0x0203, sp = 0xFFFE});
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xD0], .{f = C_FLAG, sp = 0xFFFC}, .{f = C_FLAG, sp = 0xFFFC});

    test_instruction(gb, .[0xE0, 0xAF], .{a = 0x69}, .{a = 0x69}, .[0xFFAF], .[0x69]);
    gb.mem[0xFFAF] = 0x69;
    test_instruction(gb, .[0xF0, 0xAF], .{}, .{a = 0x69});

    // POP REG
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC1], .{sp = 0xFFFC}, .{bc = 0x0203, sp = 0xFFFE});

    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xD1], .{sp = 0xFFFC}, .{de = 0x0203, sp = 0xFFFE});

    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xE1], .{sp = 0xFFFC}, .{hl = 0x0203, sp = 0xFFFE});

    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x33;
    test_instruction(gb, .[0xF1], .{sp = 0xFFFC}, .{af = 0x0230, sp = 0xFFFE});

    // C2
    test_instruction(gb, .[0xC2, 0xEF, 0xBE], .{}, .{pc = 0xBEEF});
    test_instruction(gb, .[0xC2, 0xEF, 0xBE], .{f = Z_FLAG}, .{f = Z_FLAG, pc = 0x0103});

    // D2
    test_instruction(gb, .[0xD2, 0xEF, 0xBE], .{}, .{pc = 0xBEEF});
    test_instruction(gb, .[0xD2, 0xEF, 0xBE], .{f = C_FLAG}, .{f = C_FLAG, pc = 0x0103});

    test_instruction(gb, .[0xE2], .{a = 0x69, c = 0xAF}, .{a = 0x69, c = 0xAF}, .[0xFFAF], .[0x69]);
    gb.mem[0xFFAF] = 0x69;
    test_instruction(gb, .[0xF2], .{c = 0xAF}, .{a = 0x69, c = 0xAF});

    // C3
    test_instruction(gb, .[0xC3, 0xEF, 0xBE], .{}, .{pc = 0xBEEF});

    // CALL NZ, a16
    test_instruction(gb, .[0xC4, 0x01, 0x02], .{sp = 0xFFFE}, .{pc = 0x0201, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x03]);
    test_instruction(gb, .[0xC4, 0x01, 0x02], .{f = Z_FLAG, sp = 0xFFFE}, .{f = Z_FLAG, sp = 0xFFFE});

    // CALL NC, a16
    test_instruction(gb, .[0xD4, 0x01, 0x02], .{sp = 0xFFFE}, .{pc = 0x0201, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x03]);
    test_instruction(gb, .[0xD4, 0x01, 0x02], .{f = C_FLAG, sp = 0xFFFE}, .{f = C_FLAG, sp = 0xFFFE});
    
    // PUSH REG
    test_instruction(gb, .[0xC5], .{bc = 0x0203, sp = 0xFFFE}, .{bc = 0x0203, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x02, 0x03]);
    test_instruction(gb, .[0xD5], .{de = 0x0203, sp = 0xFFFE}, .{de = 0x0203, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x02, 0x03]);
    test_instruction(gb, .[0xE5], .{hl = 0x0203, sp = 0xFFFE}, .{hl = 0x0203, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x02, 0x03]);
    test_instruction(gb, .[0xF5], .{af = 0x0230, sp = 0xFFFE}, .{af = 0x0230, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x02, 0x30]);

    // AND d8
    test_instruction(gb, .[0xE6, 0b1101_1011], .{a = 0b1001_1001}, .{a = 0b1001_1001, f = H_FLAG});
    test_instruction(gb, .[0xE6, 0b1101_1011], .{a = 0b0010_0100}, .{a = 0, f = Z_FLAG | H_FLAG});
    test_instruction(gb, .[0xE6, 0b1101_1011], .{a = 0b1001_1001}, .{a = 0b1001_1001, f = H_FLAG});
    test_instruction(gb, .[0xE6, 0x01], .{a = 0x01}, .{a = 0x01, f = H_FLAG});
    // SUB d8
    test_instruction(gb, .[0xD6, 0x01], .{}, .{a = 0xFF, f = C_FLAG | H_FLAG | N_FLAG});

    // RST 0xh
    test_instruction(gb, .[0xC7], .{}, .{pc = 0x0000, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);
    test_instruction(gb, .[0xD7], .{}, .{pc = 0x0010, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);
    test_instruction(gb, .[0xE7], .{}, .{pc = 0x0020, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);
    test_instruction(gb, .[0xF7], .{}, .{pc = 0x0030, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);

    // RET Z
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC8], .{f = Z_FLAG, sp = 0xFFFC}, .{f = Z_FLAG, pc = 0x0203, sp = 0xFFFE});
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC8], .{sp = 0xFFFC}, .{sp = 0xFFFC});

    // RET C
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xD8], .{f = C_FLAG, sp = 0xFFFC}, .{f = C_FLAG, pc = 0x0203, sp = 0xFFFE});
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xD8], .{sp = 0xFFFC}, .{sp = 0xFFFC});

    // E8
    test_instruction(gb, .[0xE8, 0x01], .{sp = 0xFFFC}, .{sp = 0xFFFD});
    test_instruction(gb, .[0xE8, 0x01], .{sp = 0xFFFF}, .{f = C_FLAG | H_FLAG, sp = 0x0000}, force_sp_check = true);
    test_instruction(gb, .[0xE8, cast,no_check(u8)(-2)], .{sp = 0xFFFC}, .{f = H_FLAG | C_FLAG, sp = 0xFFFA}, force_sp_check = true);
    test_instruction(gb, .[0xE8, cast,no_check(u8)(-1)], .{sp = 0x0000}, .{sp = 0xFFFF}, force_sp_check = true);

    // F8
    test_instruction(gb, .[0xF8, 0x01], .{sp = 0xFFFD}, .{hl = 0xFFFE, sp = 0xFFFD});
    test_instruction(gb, .[0xF8, 0x01], .{sp = 0xFFFF}, .{f = C_FLAG | H_FLAG, hl = 0x0000, sp = 0xFFFF});
    test_instruction(gb, .[0xF8, cast,no_check(u8)(-2)], .{}, .{f = C_FLAG | H_FLAG, hl = 0xFFFC});
    test_instruction(gb, .[0xF8, cast,no_check(u8)(-1)], .{sp = 0x0000}, .{hl = 0xFFFF}, force_sp_check = true);

    // RET
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC9], .{sp = 0xFFFC}, .{pc = 0x0203, sp = 0xFFFE});

    // D9
    gb.mem[0xFFFD] = 0x02;
    gb.mem[0xFFFC] = 0x03;
    test_instruction(gb, .[0xC9], .{sp = 0xFFFC}, .{pc = 0x0203, sp = 0xFFFE});
    if gb.ime != 1 {
        Basic.log("  IME != 1");
    }
    // E9
    test_instruction(gb, .[0xE9], .{hl = 0xBEEF}, .{hl = 0xBEEF, pc = 0xBEEF});
    // F9
    test_instruction(gb, .[0xF9], .{hl = 0xBEEF}, .{hl = 0xBEEF, sp = 0xBEEF});

    // CA
    test_instruction(gb, .[0xCA, 0xEF, 0xBE], .{f = Z_FLAG}, .{f = Z_FLAG, pc = 0xBEEF});
    test_instruction(gb, .[0xCA, 0xEF, 0xBE], .{}, .{pc = 0x0103});

    // DA
    test_instruction(gb, .[0xDA, 0xEF, 0xBE], .{f = C_FLAG}, .{f = C_FLAG, pc = 0xBEEF});
    test_instruction(gb, .[0xDA, 0xEF, 0xBE], .{}, .{pc = 0x0103});

    test_instruction(gb, .[0xEA, 0xAF, 0xFF], .{a = 0x69}, .{a = 0x69}, .[0xFFAF], .[0x69]);
    gb.mem[0xFFAF] = 0x69;
    test_instruction(gb, .[0xFA, 0xAF, 0xFF], .{}, .{a = 0x69});

    // CALL Z, a16
    test_instruction(gb, .[0xCC, 0x01, 0x02], .{f = Z_FLAG, sp = 0xFFFE}, .{f = Z_FLAG, pc = 0x0201, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x03]);
    test_instruction(gb, .[0xCC, 0x01, 0x02], .{sp = 0xFFFE}, .{sp = 0xFFFE});

    // CALL C, a16
    test_instruction(gb, .[0xDC, 0x01, 0x02], .{f = C_FLAG, sp = 0xFFFE}, .{f = C_FLAG, pc = 0x0201, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x03]);
    test_instruction(gb, .[0xDC, 0x01, 0x02], .{sp = 0xFFFE}, .{sp = 0xFFFE});

    // CD
    test_instruction(gb, .[0xCD, 0xEF, 0xBE], .{}, .{pc = 0xBEEF, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x03]);

    // CALL a16
    test_instruction(gb, .[0xCD, 0x69, 0x78], .{sp = 0xFFFE}, .{pc = 0x7869, sp = 0xFFFE - 2}, .[0xFFFD, 0xFFFC], .[0x01, 0x03]);
    
    test_instruction(gb, .[0xFE, 0x01], .{a = 0x01}, .{f = Z_FLAG | N_FLAG, a = 0x01});
    test_instruction(gb, .[0xFE, 0x01], .{a = 0x02}, .{f = N_FLAG, a = 0x02});
    test_instruction(gb, .[0xFE, 0x01], .{a = 0x02}, .{f = N_FLAG, a = 0x02});
    test_instruction(gb, .[0xFE, 0x90], .{}, .{f = N_FLAG | C_FLAG});

    test_instruction(gb, .[0xCF], .{}, .{pc = 0x0008, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);
    test_instruction(gb, .[0xDF], .{}, .{pc = 0x0018, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);
    test_instruction(gb, .[0xEF], .{}, .{pc = 0x0028, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);
    test_instruction(gb, .[0xFF], .{}, .{pc = 0x0038, sp = 0xFFFC}, .[0xFFFD, 0xFFFC], .[0x01, 0x01]);   
   
    Basic.log("--------");

    destroy(gb);
    Basic.free(gb);
}

BLARGGS_ROMS :: string.[
    "../bin/tests/01-special.gb",    // 1350
    "../bin/tests/02-interrupts.gb", // 260
    "../bin/tests/03-op sp,hl.gb",   // 
    "../bin/tests/04-op r,imm.gb",
    "../bin/tests/05-op rp.gb",
    "../bin/tests/06-ld r,r.gb",
    "../bin/tests/07-jr,jp,call,ret,rst.gb",
    "../bin/tests/08-misc instrs.gb",
    "../bin/tests/09-op r,r.gb",
    "../bin/tests/10-bit ops.gb",
    "../bin/tests/11-op a,(hl).gb",
];

test_blargg :: () {
    Basic.log("BLARGG");
    Basic.log("--------");
    MAX_TIME :: 20;
    for BLARGGS_ROMS {
        gb : Gameboy;
        init(*gb);
        defer destroy(*gb);
        load_rom(*gb, it);
        gb.overclock = true;
        total_time := 0.0;
        pc := 0;
        while true {
            loop(*gb, 0.5);
            if gb.mem[gb.pc] == 0x18 && gb.mem[gb.pc + 1] == 0xFE {
                Basic.log("Test complete. In % iterations.", total_time);
                break;
            }

            total_time += 0.5;
            if total_time > MAX_TIME {
                Basic.log("Stopping the test it might have failed...");
                break;
            }
        }
        
    }
    Basic.log("--------");
    Basic.log("DONE");
}

main :: () {
    test_all();
}

#run { 
    test_all();
    // test_blargg();
    Compiler.set_build_options_dc(.{do_output = false});
}

