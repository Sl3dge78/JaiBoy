CPU :: struct {
    union {
        struct {
            f: u8;
            a: u8;
        };
        af: u16;
    };

    union {
        struct {
            c: u8;
            b: u8;
        };
        bc: u16;
    };

    union {
        struct {
            e: u8;
            d: u8;
        };
        de: u16;
    };

    union {
        struct {
            l: u8;
            h: u8;
        };
        hl: u16;
    };

    sp: u16;
    pc: u16;

    cpu_clock: s64;
}

Z_FLAG : u8 : 1 << 7;
N_FLAG : u8 : 1 << 6;
H_FLAG : u8 : 1 << 5; 
C_FLAG : u8 : 1 << 4;

Interrupt :: enum u8 {
    VBLANK  :: 0;
    LCDSTAT :: 1;
    TIMER   :: 2;
    SERIAL  :: 3;
    JOYPAD  :: 4;
}

interrupt :: (gb: *Gameboy, id: Interrupt) {
    gb.halted = false;
    IF := gb.mem[IO_IF];
    IF |= xx 1 << id;
    IF |= 0xE0;
    gb.mem[IO_IF] = IF;
}

handle_interrupts :: (gb: *Gameboy) {
    if(gb.ime) {
        IF := gb.mem[IO_IF];
        IE := gb.mem[IO_IE];     
        for 0..5 {
            if(IE & (1 << it) && IF & (1 << it)) {
                IF = xx(~(1 << it) & IF);
                gb.mem[IO_IF] = IF;
                gb.ime = 0;
                push_stack(gb, gb.pc);
                gb.pc = xx(0x40 + (it * 0x8));
            }
        }
    }
}

set_flags :: (gb: *Gameboy, Z: s32, N: s32, H: s32, C: s32) {
    
    if(Z != -1)
        gb.f = xx((gb.f & ~Z_FLAG) | (Z << 7 & Z_FLAG));
    if(N != -1)
        gb.f = xx((gb.f & ~N_FLAG) | (N << 6 & N_FLAG));
    if(H != -1)
        gb.f = xx((gb.f & ~H_FLAG) | (H << 5 & H_FLAG));
    if(C != -1)
        gb.f = xx((gb.f & ~C_FLAG) | (C << 4 & C_FLAG));
}

set_flags :: (gb: *Gameboy, Z: $T1, N: $T2, H: $T3, C: $T4) {
    set_flags(gb, xx Z, xx N, xx H, xx C);
}

pop_stack :: (gb: *Gameboy) -> u16 {
    result: u16 = read(gb, gb.sp);
    gb.sp += 1;
    result |= ((cast(u16)read(gb, gb.sp)) << 8);
    gb.sp += 1;
    return result;
}

push_stack :: (gb: *Gameboy, val: u16) {
    gb.sp -= 1;
    write(gb, gb.sp, xx ((val >> 8) & 0xFF));
    gb.sp -= 1;
    write(gb, gb.sp, xx (val & 0xFF));    
}

execute :: (gb: *Gameboy) {
    op_code := read(gb, gb.pc);
    if op_code == {
        case 0x00; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
        } 
        case 0x01; { 
            gb.pc += 1;
            gb.c = read(gb, gb.pc);
            gb.pc += 1;
            gb.b = read(gb, gb.pc);
            gb.pc += 1;
            gb.cpu_clock += 12;
        } 
        case 0x02; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            write(gb, gb.bc, gb.a);
        } 
        case 0x03; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.c+= 1;
            if(gb.c == 0x00)
                gb.b+= 1;
        } 
        case 0x04; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.b+= 1;
            set_flags(gb, xx (gb.b == 0), 0, xx ((gb.b & 0xF) == 0), -1);
        } 
        case 0x05; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.b -= 1;
            set_flags(gb, xx (gb.b == 0), 1, xx ((gb.b & 0xF) == 0xF), -1);
        } 
        case 0x06; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.b = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x07; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            bit: u8 = (gb.a & 0x80);
            gb.a <<= 1; 
            gb.a |= bit >> 7;
            set_flags(gb, 0,0,0, bit >> 7);
        } 
        case 0x08; {
            gb.cpu_clock += 20;
            gb.pc += 1;
            addr := read_u16(gb, gb.pc);
            gb.pc += 2;
            write_u16(gb, addr, gb.sp);
        } 
        case 0x09; {
            gb.cpu_clock += 8;
            gb.pc += 1;
            val: u32 = cast(u32)gb.hl + cast(u32)gb.bc;
            set_flags(gb, -1, 0, xx ((gb.hl & 0xFFF) + (gb.bc & 0xFFF) > 0xFFF), xx (val > 0xFFFF));
            gb.hl = xx (val & 0xFFFF);
        } 
        case 0x0A; { 
            gb.cpu_clock += 8;
            gb.pc += 1;
            gb.a = read(gb, gb.bc);
        } 
        case 0x0B; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.c -= 1;
            if(gb.c == 0xFF)
                gb.b -= 1;
        } 
        case 0x0C; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.c += 1;
            set_flags(gb, xx (gb.c == 0), 0, xx((gb.c & 0xF) == 0x00), -1);
        } 
        case 0x0D; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.c -= 1;
            set_flags(gb, xx (gb.c == 0), 1, xx ((gb.c & 0xF) == 0xF), -1);
        } 
        case 0x0E; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.c = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x0F; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            bit :u8= (gb.a & 01);
            gb.a >>= 1;
            gb.a |= bit << 7;
            set_flags(gb, 0, 0, 0, bit);
        } 
        case 0x10; {
            gb.cpu_clock += 10;            
            gb.step_through = true;
            log("Stop Instruction");
        } 
        case 0x11; { 
            gb.pc += 1;
            gb.e = read(gb, gb.pc);
            gb.pc += 1;
            gb.d = read(gb, gb.pc);
            gb.pc += 1;
            gb.cpu_clock += 12;
        } 
        case 0x12; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            write(gb, gb.de, gb.a);
        } 
        case 0x13; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.e += 1;
            if(gb.e == 0x00)
                gb.d += 1;
        } 
        case 0x14; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.d += 1;
            set_flags(gb, xx(gb.d == 0), 0, xx((gb.d & 0xF) == 0), -1);
        } 
        case 0x15; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.d -= 1;
            set_flags(gb, xx(gb.d == 0), 1, xx((gb.d & 0xF) == 0xF), -1);
        } 
        case 0x16; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.d = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x17; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            bit: u8 = xx ((gb.a & 0b10000000) != 0);
            gb.a <<= 1; 
            gb.a |= xx((gb.f & C_FLAG) != 0);
            set_flags(gb, 0, 0, 0, bit);
        } 
        case 0x18; {
            gb.pc += 1;
            offset: s8 = cast,no_check(s8)read(gb, gb.pc);
            gb.pc += 1;
            gb.pc = cast(u16)(cast(s32)gb.pc + offset);
            gb.cpu_clock += 12;
        } 
        case 0x19; {
            gb.cpu_clock += 8;
            gb.pc += 1;
            val : u32 = cast(u32)gb.hl + cast(u32)gb.de;
            set_flags(gb, -1, 0, xx ((gb.hl & 0xFFF) + (gb.de & 0xFFF) > 0xFFF), xx(val > 0xFFFF));
            gb.hl = xx(val & 0xFFFF);
        } 
        case 0x1A; { 
            gb.cpu_clock += 8;
            gb.pc += 1;
            gb.a = read(gb, gb.de);
        } 
        case 0x1B; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.e -= 1;
            if(gb.e == 0xFF)
                gb.d -= 1;
        } 
        case 0x1C; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.e += 1;
            set_flags(gb, xx(gb.e == 0), 0, xx((gb.e & 0xF) == 0x00), -1);
        } 
        case 0x1D; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.e -= 1;
            set_flags(gb, xx(gb.e == 0), 1, xx((gb.e & 0xF) == 0xF), -1);
        } 
        case 0x1E; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.e = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x1F; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            bit:u8 = (gb.a & 0x1);
            gb.a >>= 1;
            gb.a |= (cast(u8)((gb.f & C_FLAG) != 0)) << 7;
            set_flags(gb, 0, 0, 0, bit);
        } 
        case 0x20; {
            gb.pc += 1;
            off := read(gb, gb.pc);
            offset: s8 = cast,no_check(s8)off;
            gb.pc += 1;
            if(!(gb.f & Z_FLAG)) {
                gb.pc = cast(u16)(cast(s32)gb.pc + cast(s16)offset);
                gb.cpu_clock += 12;
            } else {
                gb.cpu_clock += 8;
            }
        } 
        case 0x21; {
            gb.pc += 1;
            gb.l = read(gb, gb.pc);
            gb.pc += 1;
            gb.h = read(gb, gb.pc);
            gb.pc += 1;
            gb.cpu_clock += 4;
        } 
        case 0x22; {
            gb.cpu_clock += 8;
            gb.pc += 1;
            write(gb, gb.hl, gb.a);
            gb.hl += 1;
        } 
        case 0x23; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.l += 1;
            if(gb.l == 0x00)
                gb.h += 1;
        } 
        case 0x24; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.h += 1;
            set_flags(gb, xx(gb.h == 0), 0, xx((gb.h & 0xF) == 0), -1);
        } 
        case 0x25; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.h -= 1;
            set_flags(gb, xx(gb.h == 0), 1, xx((gb.h & 0xF) == 0xF), -1);
        } 
        case 0x26; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.h = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x27; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            a: u16 = gb.a;
            c: u8 = xx((gb.f & C_FLAG) != 0);
            if((gb.f & N_FLAG) == 0) {
                if(gb.f & H_FLAG || (a & 0x0F) > 0x09) {
                    a += 0x06;
                }
                if(c || (a & 0xFF0) > 0x90) {
                    a += 0x60;
                    c |= xx ((a & 0xFF0) > 0x90);
                }
            } else {
                if(gb.f & H_FLAG) {
                    a -= 0x06;
                } 
                if(c) {
                    a = (a - 0x60) & 0xFF;
                }
            }
            value:u16 = a;
            gb.a = xx(value & 0xFF);
            set_flags(gb, xx(gb.a == 0), -1, 0, c);
        } 
        case 0x28; {
            gb.pc += 1;
            offset:s8 = cast,no_check(s8) read(gb, gb.pc);
            gb.pc += 1;
            if((gb.f & Z_FLAG)) {
                gb.pc = cast(u16)(cast(s32)gb.pc + cast(s16)offset);
                gb.cpu_clock += 12;
            } else {
                gb.cpu_clock += 8;
            }
        } 
        case 0x29; {
            gb.cpu_clock += 8;
            gb.pc += 1;
            val:u32 = cast(u32)gb.hl + cast(u32)gb.hl;
            set_flags(gb, -1, 0, xx ((gb.hl & 0xFFF) + (gb.hl & 0xFFF) > 0xFFF), xx (val > 0xFFFF));
            gb.hl = xx(val & 0xFFFF);
        } 
        case 0x2A; { 
            gb.cpu_clock += 8;
            gb.pc += 1;
            gb.a = read(gb, gb.hl);
            gb.hl += 1;
        } 
        case 0x2B; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.l -= 1;
            if(gb.l == 0xFF)
                gb.h -= 1;
        } 
        case 0x2C; {
            gb.l += 1;
            set_flags(gb, xx (gb.l == 0), 0, xx ((gb.l & 0xF) == 0), -1);
            gb.pc  += 1;
            gb.cpu_clock += 4;
        } 
        case 0x2D; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.l -= 1;
            set_flags(gb, xx (gb.l == 0), 1, xx((gb.l & 0xF) == 0xF), -1);
        } 
        case 0x2E; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.l = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x2F; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.a = ~gb.a;
            set_flags(gb, -1, 1, 1, -1);
        } 
        case 0x30; {
            gb.pc += 1;
            offset: s8 = cast,no_check(s8) read(gb, gb.pc);
            gb.pc += 1;
            if(!(gb.f & C_FLAG)) {
                gb.pc = xx(cast,no_check(s32)gb.pc + offset);
                gb.cpu_clock += 12;
            } else {
                gb.cpu_clock += 8;
            }
        } 
        case 0x31; { 
            gb.pc += 1;
            value := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.sp = value;
            gb.cpu_clock += 12;
        } 
        case 0x32; { 
            gb.cpu_clock += 8;
            gb.pc += 1;
            write(gb, gb.hl, gb.a);
            gb.hl -= 1;
        }
        case 0x33; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.sp += 1;
        } 
        case 0x34; {
            gb.cpu_clock += 12;
            gb.pc += 1;
            value:u8 = read(gb, gb.hl);
            result:u8 = value + 1;
            set_flags(gb, xx(result == 0), 0, xx((value & 0xF) == 0xF), -1);
            write(gb, gb.hl, result);
        } 
        case 0x35; {
            gb.cpu_clock += 12;
            gb.pc += 1;
            value: u8 = read(gb, gb.hl);
            result: u8 = value - 1;
            set_flags(gb, xx(result == 0), 1, xx((value & 0xF) == 0), -1);
            write(gb, gb.hl, result);
        } 
        case 0x36; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            write(gb, gb.hl, read(gb, gb.pc));
            gb.pc += 1;
        } 
        case 0x37; { // SCF
            gb.cpu_clock += 4;
            gb.pc += 1;
            set_flags(gb, -1, 0, 0, 1);
        } 
        case 0x38; {
            gb.pc += 1;
            offset: s8 = cast,no_check(s8)read(gb, gb.pc);
            gb.pc += 1;
            if((gb.f & C_FLAG)) {
                gb.pc = cast(u16)(cast(s32)gb.pc + cast(s16)offset);
                gb.cpu_clock += 12;
            } else {
                gb.cpu_clock += 8;
            }
        } 
        case 0x39; {
            gb.cpu_clock += 8;
            gb.pc += 1;
            val: u32 = cast(u32)gb.hl + cast(u32)gb.sp;
            set_flags(gb, -1, 0, xx ((gb.hl & 0xFFF) + (gb.sp & 0xFFF) > 0xFFF), xx (val > 0xFFFF));
            gb.hl = xx(val & 0xFFFF);
        } 
        case 0x3A; { 
            gb.cpu_clock += 8;
            gb.pc += 1;
            gb.a = read(gb, gb.hl);
            gb.hl -= 1;
        } 
        case 0x3B; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.sp -= 1;
        } 
        case 0x3C; {
            gb.a += 1;
            set_flags(gb, gb.a == 0, 0, (gb.a & 0xF) == 0, -1);
            gb.pc  += 1;
            gb.cpu_clock += 4;
        } 
        case 0x3D; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.a -= 1;
            set_flags(gb, gb.a == 0, 1, (gb.a & 0xF) == 0xF, -1);
        } 
        case 0x3E; { 
            gb.cpu_clock += 8;
            gb.pc += 1;
            gb.a = read(gb, gb.pc);
            gb.pc += 1;
        } 
        case 0x3F; {
            gb.cpu_clock += 4;
            gb.pc += 1;
            set_flags(gb, -1, 0, 0, (gb.f & C_FLAG) == 0);
        } 
        case 0x76; { 
            gb.cpu_clock += 4;
            gb.pc += 1;
            gb.halted = true;
        } 
        case 0xC0; {
            gb.pc += 1;
            gb.cpu_clock += 8;
            if(!(gb.f & Z_FLAG)) {
                gb.pc = pop_stack(gb);
                gb.cpu_clock += 12;
            }
        } 
        case 0xC1; {
            gb.pc += 1;
            gb.cpu_clock += 12;
            gb.bc = pop_stack(gb);
        } 
        case 0xC2; {
            from: u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(!(gb.f & Z_FLAG)) {
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xC3; {
            pc:= read_u16(gb, gb.pc + 1);
            from := gb.pc;
            gb.pc = pc;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xC4; {
            from: u16 = gb.pc;
            gb.pc += 1;
            addr := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(!(gb.f & Z_FLAG)) {
                push_stack(gb, gb.pc);
                gb.pc = addr;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xC5; { 
            gb.pc += 1;
            push_stack(gb, gb.bc);
            gb.cpu_clock += 16;
        } 
        case 0xC6; { 
            gb.pc += 1;
            gbADD(gb, read(gb, gb.pc), 0);
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xC7; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0000;
            array_add(*gb.call_stack, make_stack_entry(from, 0));
            gb.cpu_clock += 16;
        } 
        case 0xC8; {
            from:u16 = gb.pc;
            gb.pc += 1;
            gb.cpu_clock += 8;
            if((gb.f & Z_FLAG)) {
                gb.pc = pop_stack(gb);
                gb.cpu_clock += 12;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xC9; {
            from: u16 = gb.pc;
            gb.pc = pop_stack(gb);
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xCA; {
            from:u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(gb.f & Z_FLAG) {
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xCB; {
            gb.pc += 1;
            gbPrefixCB(gb);
        } 
        case 0xCC; {
            from: u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(gb.f & Z_FLAG) {
                push_stack(gb, gb.pc);
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xCD; {
            from: u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            push_stack(gb, gb.pc);
            gb.pc = pc;
            gb.cpu_clock += 24;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xCE; {
            gb.pc += 1;
            gbADD(gb, read(gb, gb.pc), 1);
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xCF; {
            from: u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0008;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xD0; {
            from:u16 = gb.pc;
            gb.pc += 1;
            gb.cpu_clock += 8;
            if(!(gb.f & C_FLAG)) {
                gb.pc = pop_stack(gb);
                gb.cpu_clock += 12;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xD1; {
            gb.pc += 1;
            gb.cpu_clock += 12;
            gb.de = pop_stack(gb);
        } 
        case 0xD2; {
            from:u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(!(gb.f & C_FLAG)) {
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xD4; {
            from:u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(!(gb.f & C_FLAG)) {
                push_stack(gb, gb.pc);
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xD5; { 
            gb.pc += 1;
            push_stack(gb, gb.de);
            gb.cpu_clock += 16;
        } 
        case 0xD6; { 
            gb.pc += 1;
            gbSUB(gb, read(gb, gb.pc), 0);
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xD7; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0010;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xD8; {
            from:u16 = gb.pc;
            gb.pc += 1;
            gb.cpu_clock += 8;
            if((gb.f & C_FLAG)) {
                gb.pc = pop_stack(gb);
                gb.cpu_clock += 12;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xD9; {
            from:u16 = gb.pc;
            gb.pc += 1;
            gb.cpu_clock += 16;
            pc := pop_stack(gb);
            gb.pc = pc;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            gb.ime = 1;
        } 
        case 0xDA; {
            from:u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(gb.f & C_FLAG) {
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xDC; {
            from:u16 = gb.pc;
            gb.pc += 1;
            pc := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.cpu_clock += 12;
            if(gb.f & C_FLAG) {
                push_stack(gb, gb.pc);
                gb.pc = pc;
                gb.cpu_clock += 4;
                array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
            }
        } 
        case 0xDE; {
            gb.pc += 1;
            gbSUB(gb, read(gb, gb.pc), 1);
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xDF; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0018;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xE0; { 
            gb.pc += 1;
            offset:u8 = read(gb, gb.pc);
            gb.pc += 1;
            addr: u16 = 0xFF00 + cast(u16)offset;
            write(gb, addr, gb.a);
            gb.cpu_clock += 12;
        } 
        case 0xE1; {
            gb.pc += 1;
            gb.cpu_clock += 12;
            gb.hl = pop_stack(gb);
        } 
        case 0xE2; {
            write(gb, xx(gb.c + 0xFF00), gb.a);
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xE5; { 
            gb.pc += 1;
            push_stack(gb, gb.hl);
            gb.cpu_clock += 16;
        } 
        case 0xE6; { 
            gb.pc += 1;
            gbAND(gb, read(gb, gb.pc));
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xE7; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0020;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xE8; {
            gb.pc += 1;
            gb.cpu_clock += 16;
            
            add: s32 = xx cast,no_check(s8) read(gb, gb.pc);
            gb.pc += 1;
            result: u32 = cast,no_check(u32)(cast(s32)gb.sp + add);
            
            h: s32 = (cast(s32)(gb.sp & 0xF) + cast(s32)(add & 0xF));
            c: s32 = (cast(s32)(gb.sp & 0xFF) + cast(s32)(add & 0xFF));

            set_flags(gb, 0, 0, h > 0xF, c > 0xFF);
            gb.sp = xx(result & 0xFFFF);            
        } 
        case 0xE9; {
            from:u16 = gb.pc;
            gb.pc = gb.hl;
            gb.cpu_clock += 4;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xEA; { 
            gb.pc += 1;
            addr := read_u16(gb, gb.pc);
            gb.pc += 2;
            write(gb, addr, gb.a);
            gb.cpu_clock += 16;
        } 
        case 0xEE; {
            gb.pc += 1;
            gbXOR(gb, read(gb, gb.pc));
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xEF; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0028;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xF0; { 
            gb.pc += 1;
            offset:u8 = read(gb, gb.pc);
            gb.pc += 1;
            gb.a = read(gb, xx(0xFF00 + offset));
            gb.cpu_clock += 12;
        } 
        case 0xF1; {
            gb.pc += 1;
            gb.cpu_clock += 12;
            gb.af = pop_stack(gb);
            gb.f &= 0xF0;
        } 
        case 0xF2; {
            value:u8 = read(gb, xx(gb.c + 0xFF00));
            gb.a = value;
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xF3; { 
            gb.pc += 1;
            gb.ime = 0;
            gb.cpu_clock += 4;
        } 
        case 0xF5; { 
            gb.pc += 1;
            push_stack(gb, gb.af);
            gb.cpu_clock += 16;
        } 
        case 0xF6; { 
            gb.pc += 1;
            gbOR(gb, read(gb, gb.pc));
            gb.pc += 1;
            gb.cpu_clock += 8;
        } 
        case 0xF7; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0030;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case 0xF8; {
            gb.pc += 1;
            gb.cpu_clock += 16;
            
            add: s32 = xx cast,no_check(s8) read(gb, gb.pc);
            gb.pc += 1;
            result: u32 = cast,no_check(u32)(cast(s32)gb.sp + add);
            
            h: s32 = (cast(s32)(gb.sp & 0xF) + cast(s32)(add & 0xF));
            c: s32 = (cast(s32)(gb.sp & 0xFF) + cast(s32)(add & 0xFF));

            set_flags(gb, 0, 0, h > 0xF, c > 0xFF);
            gb.hl = xx(result & 0xFFFF);            
        } 
        case 0xF9; {
            gb.pc += 1;
            gb.cpu_clock += 8;
            gb.sp = gb.hl;
        } 
        case 0xFA; { 
            gb.pc += 1;
            gb.cpu_clock += 16;
            addr := read_u16(gb, gb.pc);
            gb.pc += 2;
            gb.a = read(gb, addr);
        } 
        case 0xFB; { 
            gb.pc += 1;
            gb.ime = 1;
            gb.cpu_clock += 4;
        } 
        case 0xFC; { 
            gb.pc += 1;
            gb.cpu_clock += 4;
            gb.ime = 1;
        } 
        case 0xFE; { 
            gb.pc += 1;
            gb.cpu_clock += 4;
            gbCP(gb, read(gb, gb.pc));
            gb.pc += 1;
        } 
        case 0xFF; {
            from:u16 = gb.pc;
            gb.pc += 1;
            push_stack(gb, gb.pc);
            gb.pc = 0x0038;
            gb.cpu_clock += 16;
            array_add(*gb.call_stack, make_stack_entry(from, gb.pc));
        } 
        case;
        if(op_code >= 0x40 && op_code <= 0x7F) { // LD
            gbInstructionLD(gb, op_code);
            gb.pc += 1;
            gb.cpu_clock += 4;
        } else if(op_code >= 0x80 && op_code <= 0xBF) { // MATHS
            b2:u8 = (op_code & 0xF);
            operand:u8 = gbGetFromByteCode(gb, b2 % 8);
            b1:u8 = (op_code >> 4) & 0xF - 0x8;
            b1 *= 2;
            if (b2 > 7) {
                b1 += 1;
            }
            if b1 == {
                case 0; gbADD(gb, operand, 0);
                case 1; gbADD(gb, operand, 1);
                case 2; gbSUB(gb, operand, 0);
                case 3; gbSUB(gb, operand, 1);
                case 4; gbAND(gb, operand);   
                case 5; gbXOR(gb, operand);   
                case 6; gbOR (gb, operand);   
                case 7; gbCP (gb, operand);
            }
            gb.cpu_clock += 4;
            gb.pc += 1;
            
        } else {
            log("Unimplemented opcode : 0x%", hex(read(gb, gb.pc)));
            gb.cpu_clock += 1;
            gb.pc += 1;
            gb.step_through = true;
        }
    }
}

gbADD :: (gb: *Gameboy, operand: u8, carry: u8) {
    half_a:u16 = gb.a & 0xF;
    half_a += operand & 0xF;
    result:u16 = cast(u16)gb.a + cast(u16)operand;
    if((gb.f & C_FLAG) != 0 && carry) {
        result += carry;
        half_a += carry;
    }
    
    set_flags(gb, (result & 0xFF) == 0, 0, half_a > 0xF, result > 0xFF);
    gb.a = xx(result & 0xFF);
}

gbSUB :: (gb: *Gameboy, operand: u8, carry: u8) {
    half_a:u16 = gb.a & 0xF;
    half_a -= operand & 0xF;
    result : u16 = cast(u16)gb.a - cast(u16)operand;
    if((gb.f & C_FLAG) != 0 && carry) {
        result -= carry;
        half_a -= carry;
    }
    set_flags(gb, (result & 0xFF) == 0, 1, half_a > 0xF, result > 0xFF);
    gb.a = xx(result & 0xFF);
}

gbAND :: (gb: *Gameboy, operand:u8) {
    gb.a = operand & gb.a;
    set_flags(gb, gb.a == 0, 0, 1, 0);
}

gbXOR :: (gb: *Gameboy, operand:u8) {
    gb.a = operand ^ gb.a;
    set_flags(gb, gb.a == 0, 0, 0, 0);
}

gbOR :: (gb: *Gameboy, operand:u8) {
    gb.a = operand | gb.a;
    set_flags(gb, gb.a == 0, 0, 0, 0);
}

gbCP :: (gb: *Gameboy, operand:u8) {
    half_a:s16 = gb.a & 0xF;
    
    result:s16 = cast(s16)gb.a - cast(s16)operand;
    half_a -= cast(s16)operand & 0xF;
    
    set_flags(gb, result == 0, 1, half_a < 0, result < 0);
}

gbGetFromByteCode :: (gb : *Gameboy, id: u8) -> u8 {
    if id == {
        case 0; return gb.b;
        case 1; return gb.c;
        case 2; return gb.d;
        case 3; return gb.e;
        case 4; return gb.h;
        case 5; return gb.l;
        case 6; return read(gb, gb.hl);
        case 7; return gb.a;
        case; assert(false); return 0;
    }
}

gbSetFromByteCode :: (gb : *Gameboy, id: u8, value: u8) {
    if id == {
        case 0; gb.b = value; return;
        case 1; gb.c = value; return;
        case 2; gb.d = value; return;
        case 3; gb.e = value; return;
        case 4; gb.h = value; return;
        case 5; gb.l = value; return;
        case 6; write(gb, gb.hl, value); return;
        case 7; gb.a = value; return;
        case; assert(false); return;
    }
}

gbInstructionLD :: (gb : *Gameboy, op_code: u8) {
    
    b1 :u8= (op_code >> 4) - 4;
    b2 :u8= op_code & 0xF;
    b1 *= 2;
    if (b2 > 7) {
        b1 += 1;
    }
    b2 = b2 % 8;
    
    gbSetFromByteCode(gb, b1, gbGetFromByteCode(gb, b2));
}

gbPrefixCB :: (gb : *Gameboy) {
    code := read(gb, gb.pc);
    gb.pc += 1;
    src := gbGetFromByteCode(gb, (code & 0x0F) % 8);
    
    if((code & 0x0F) % 8 == 6) 
        gb.cpu_clock += 8;
    
    above_8:bool = (code & 0x0F) >= 8;
    first:u8 = code >> 4 & 0x0F;
    
    Z: s8 = 0;
    N: s8 = 0;
    H: s8 = 0;
    C: s8 = 0;
    
    if first == {
        case 0; { // RLC -- RRC
            if(!above_8) {
                bit: u8 = (src & 0x80);
                src <<= 1; 
                src |= bit >> 7;
                C = xx(bit >> 7);
            } else {
                bit: u8 = (src & 0x01);
                src >>= 1;
                src |= bit << 7;
                C = xx bit;
            }
            Z = xx(src == 0);
        } 
        case 1; { // RL -- 
            if(!above_8) {
                bit: u8 = (src & 0x80);
                src <<= 1; 
                C = xx(bit >> 7);
                src += xx((gb.f & C_FLAG) != 0);
                Z = xx(src == 0);
            } else { // RR
                bit: u8 = (src & 0x01);
                src >>= 1;
                C = xx bit;
                src |= (cast(u8)((gb.f & C_FLAG) != 0)) << 7;
            }
            Z = xx(src == 0);
        } 
        case 2; { // SLA 
            if(!above_8) {
                C = xx((src & 0b10000000) != 0);
                src <<= 1; 
                Z = xx(src == 0);
            } else { // SRA
                bit: u8 = (src & 0x80);
                C = xx(src & 0x01);
                src >>= 1;
                src |= bit;
                Z = xx(src == 0);
            }
            Z = xx(src == 0);
        } 
        case 3; {
            if(!above_8) { // swap
                high: u8 = src & 0xF0;
                low: u8 = src & 0x0F;
                src = (high >> 4) | (low << 4);
            } else { // SRL
                bit: u8 = (src & 1);
                src >>= 1; 
                C = xx bit;
            }
            Z = xx(src == 0);
        } 
        case; 
        if(first >= 0x4 && first <= 0x7) { // BIT
            bit: u8 = (first - 0x4) * 2 + xx above_8;
            Z = xx (((src >> bit) & 1) == 0);
            N = 0;
            H = 1;
            C = -1;
        } else if(first >= 0x8 && first <= 0xB) { // RES
            bit: u8 = (first - 0x8) * 2 + xx above_8;
            
            src &= ~(cast(u8)1 << bit);
            
            Z = -1;
            N = -1;
            H = -1;
            C = -1;
        } else { // SET
            bit: u8 = (first - 0xC) * 2 + xx above_8;
            
            src |= cast(u8)1 << bit;
            
            Z = -1;
            N = -1;
            H = -1;
            C = -1;
        }
        
    }
    set_flags(gb, Z, N, H, C);
    gb.cpu_clock += 8;
    gbSetFromByteCode(gb, (code & 0x0F) % 8, src);
}
