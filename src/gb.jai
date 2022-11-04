#load "cpu.jai";
#load "ppu.jai";
#load "rom.jai";
#load "apu.jai";

CLOCK_SPEED ::   4194304;

SCREEN_WIDTH ::  160;
SCREEN_HEIGHT :: 144;

IO_JOY ::        0xFF00;
IO_SB  ::        0xFF01;
IO_SC  ::        0xFF02;
IO_DIV ::        0xFF04;
IO_TIMA ::       0xFF05;
IO_TMA ::        0xFF06;
IO_TAC ::        0xFF07;

IO_LCDC ::       0xFF40;
IO_STAT ::       0xFF41;
IO_SCY ::        0xFF42;
IO_SCX ::        0xFF43;
IO_LY ::         0xFF44;
IO_LYC ::        0xFF45;
IO_DMA ::        0xFF46;
IO_BGP ::        0xFF47;
IO_OBP0 ::       0xFF48;
IO_OBP1 ::       0xFF49;
IO_WY ::         0xFF4A;
IO_WX ::         0xFF4B;
IO_IF ::         0xFF0F;
IO_IE ::         0xFFFF;

MEM_ROM_START ::      0x0000;
MEM_ROM_END ::        0x7FFF;
MEM_ROM_SIZE ::       MEM_ROM_END - MEM_ROM_START + 1;
MEM_VRAM_START ::     0x8000;
MEM_VRAM_END ::       0x9FFF;
MEM_VRAM_SIZE ::      MEM_VRAM_END - MEM_VRAM_START + 1;
MEM_CARTRAM_START ::  0xA000;
MEM_CARTRAM_END ::    0xBFFF;
MEM_CARTRAM_SIZE ::   MEM_CARTRAM_END - MEM_CARTRAM_START + 1;
MEM_WRAM0_START ::    0xC000;
MEM_WRAM0_END ::      0xCFFF;
MEM_WRAM0_SIZE ::     MEM_WRAM0_END - MEM_WRAM0_START + 1;
MEM_WRAM1_START ::    0xD000;
MEM_WRAM1_END ::      0xDFFF;
MEM_WRAM1_SIZE ::     MEM_WRAM1_END - MEM_WRAM1_START + 1;
MEM_MIRROR0_START ::  0xE000;
MEM_MIRROR0_END ::    0xEFFF;
MEM_MIRROR0_SIZE ::   MEM_MIRROR0_END - MEM_MIRROR0_START + 1;
MEM_MIRROR1_START ::  0xEFFF;
MEM_MIRROR1_END ::    0xFDFF;
MEM_MIRROR1_SIZE ::   MEM_MIRROR1_END - MEM_MIRROR1_START + 1;
MEM_OAM_START ::      0xFE00;
MEM_OAM_END ::        0xFE9F;
MEM_OAM_SIZE ::       MEM_OAM_END - MEM_OAM_START + 1;
MEM_UNUSABLE_START :: 0xFEA0;
MEM_UNUSABLE_END ::   0xFEFF;
MEM_UNUSABLE_SIZE ::  MEM_UNUSABLE_END - MEM_UNUSABLE_START + 1;
MEM_IO_START ::       0xFF00;
MEM_IO_END ::         0xFF7F;
MEM_IO_SIZE ::        MEM_IO_END - MEM_IO_START + 1;
MEM_HRAM_START ::     0xFF80;
MEM_HRAM_END ::       0xFFFF;
MEM_HRAM_SIZE ::      MEM_HRAM_END - MEM_HRAM_START + 1;
MEM_END ::            0xFFFF;
MEM_SIZE ::           0x10000;

Stack_Entry :: struct {
    from: u16;
    to: u16;
};

make_stack_entry :: (from : u16, to: u16) -> Stack_Entry{
    s : Stack_Entry = ---;
    s.from = from;
    s.to = to;
    return s;
}

OAMSprite:: struct  {
    y: u8;
    x: u8;
    tile: u8;
    flags: u8;
};

TileLine:: struct  {
    data_1: u8;
    data_2: u8;
};

Gameboy :: struct {
    rom_path : string;
    rom : Rom;

    mem : []u8;
    ime : u8;

    using #as cpu : CPU;
    timer: u16;
    
    keys_dpad : u8 = 0xFF;
    keys_buttons : u8 = 0xFF;
   
    apu : APU;

    lcd_screen: [SCREEN_HEIGHT][SCREEN_WIDTH]u8;

    halted: bool;

    // Internals
    rom_loaded: bool;
    
    ppu_clock: s64;
    cycles_left: s64;
    DMA_cycles_left: s16;
    clock_speed: u64 = 4_194_304;
    
    // Debug
    overclock := false;
    running: bool = true;
    step_through: bool = false;
    
    clock_mul: float = 1;

    call_stack: [..]Stack_Entry;
}

init :: (using gb: *Gameboy) {       
    mem.data = Basic.alloc(MEM_SIZE);
    mem.count = MEM_SIZE;

    init_audio(gb, *gb.apu);
}

destroy :: (gb: *Gameboy) {
    Basic.free(gb.mem.data);
    Rom.destroy(*gb.rom);
}

reset :: (using gb: *Gameboy) {
    pc    = ROM_ENTRY;
    sp    = 0xFFFE;
    a     = 0;
    b     = 0;
    c     = 0;
    d     = 0;
    e     = 0;
    f     = 0;
    h     = 0;
    l     = 0;

    ime   = 0;
    gb.mem[IO_LCDC] = 0x91;
    gb.mem[IO_STAT] = 0x85;
    gb.mem[IO_IF]   = 0xE1; 
    gb.mem[IO_IE]   = 0x00; 
    gb.mem[IO_TAC]  = 0x00; 
    gb.mem[0x2000]  = 0x01; // Select rom bank 1

    Rom.reset(*gb.rom);

    gb.call_stack.count = 0;
}

load_rom :: (gb: *Gameboy, file : string) -> bool {
    gb.rom_path = file;
    if !Rom.load(file, *gb.rom) {
        return false;
    }
    return true;
}

write :: (gb: *Gameboy, address: u16, value: u8) {

    if address == {
        case IO_DMA; {
            gb.DMA_cycles_left = 0x9F; // DMA transfer
        }
        case IO_IF; value |= 0xE0; 
        case IO_TAC; value |= 0xF8; 
        case IO_DIV; gb.timer = 0; 
        case IO_STAT; { 
            value = (gb.mem[IO_STAT] & 0b0000_0111) | (0b1111_1000 & value);
        }
        case IO_LCDC; {
            if (IO_LCDC & 0x80) == 0 {
                gb.mem[IO_STAT] &= 0b1111_1100;
                gb.mem[IO_LY] = 0;
            }
        }
        case IO_SC; {
            if value == 0x81 {
                Basic.print_character(gb.mem[IO_SB]);
            }
        }
        case IO_NR52; {
            toggle : bool = !((value >> 7) & 1);
            SDL_PauseAudioDevice(gb.apu.audio_device, xx toggle);
            value &= 0x80;
        }
        case IO_NR11; {
            gb.apu.enveloppes[0].length = xx (value & 0b11111);
        } 
        case IO_NR12; {
            gb.apu.enveloppes[0].volume = cast,no_check(s8) ((value >> 4) & 0xF);
        } 
        case IO_NR14; {
            is_playing := (value & 0x80) != 0;
            if(is_playing) {
                enveloppe_init(gb, *gb.apu.enveloppes[0], 0);
                NR10 := gb.mem[IO_NR10];
                NR11 := gb.mem[IO_NR11];
                gb.apu.channel1.pitch = gb.mem[IO_NR13];
                gb.apu.channel1.pitch |= (cast(u16)value & 0x07) << 8;
                gb.apu.channel1.sweep_timer = (1.0/128.0);
                time := (NR10 >> 4) & 0b111;
                gb.apu.channel1.sweep_period = ifx time == 0 then 8 else time;
                gb.apu.channel1.duty = (NR11 & 0xC0) >> 6;
            }
        }
        case IO_NR21; {
            gb.apu.enveloppes[1].length = xx (value & 0b11111);
        }
        case IO_NR22; {
            gb.apu.enveloppes[1].volume = cast,no_check(s8) ((value >> 4) & 0xF);
        }
        case IO_NR24; {
            is_playing := (value & 0x80) != 0;
            if(is_playing) {
                enveloppe_init(gb, *gb.apu.enveloppes[1], 1);
                NR21 := gb.mem[IO_NR21];
                gb.apu.channel2.pitch = gb.mem[IO_NR23];
                gb.apu.channel2.pitch |= (cast(u16)value & 0x07) << 8;
                gb.apu.channel2.duty = (NR21 & 0xC0) >> 6;
            }
        }
        case IO_NR30; {
            gb.apu.is_playing[2] = (value & 0x80) != 0;
        }
        case IO_NR31; {
            gb.apu.enveloppes[2].length = xx (value & 0b11111);
        }
        case IO_NR32; {
            gb.apu.enveloppes[2].volume = cast,no_check(s8) ((value >> 5) & 3);
        }
        case IO_NR34; {
            is_playing := (value & 0x80) != 0;
            if(is_playing) {
                enveloppe_init(gb, *gb.apu.enveloppes[2], 2);
                NR31 := gb.mem[IO_NR31];
                gb.apu.channel3.pitch = gb.mem[IO_NR33];
                gb.apu.channel3.pitch |= (cast(u16)value & 0x07) << 8;
            }
        }
        case IO_NR42; {
            gb.apu.enveloppes[3].volume = cast,no_check(s8)((value >> 4) & 0xF);
        }
        case IO_NR44; {
            is_playing := (value & 0x80) != 0;
            if(is_playing) {
                enveloppe_init(gb, *gb.apu.enveloppes[3], 3);
            }
        }
    }

    if address >= MEM_MIRROR0_START && address <= MEM_MIRROR1_END {
        gb.mem[address] = value;
        address -= 0x2000;
    }

    if address >= MEM_ROM_START && address <= MEM_ROM_END {
        Rom.write(*gb.rom, address, value);
        return;
    }

    if address >= 0xA000 && address <= 0xBFFF {
        Rom.write(*gb.rom, address, value);
        return;
    }
    
    gb.mem[address] = value;
}

write_u16 :: (gb: *Gameboy, addr: u16, val: u16) {
    write(gb, addr, xx (val & 0xFF));
    write(gb, addr + 1, xx ((val >> 8) & 0xFF));
}

read :: (gb: *Gameboy, address: u16) -> u8 {
    if address >= 0x0000 && address <= 0x7FFF {
        return Rom.read(*gb.rom, address);
    } 
    if address >= 0xA000 && address <= 0xBFFF {
        return Rom.read(*gb.rom, address);
    }

    return gb.mem[address];
}

read_u16 :: (gb: *Gameboy, addr : u16) -> u16 {
    lo : u16 = read(gb, addr);
    hi : u16 = read(gb, addr + 1);
    return (hi << 8) | lo;
}

input :: (gb: *Gameboy, e: *SDL_KeyboardEvent, is_up: u8) {
    if e.keysym.scancode == {
        case SDL_SCANCODE_DOWN;   gb.keys_dpad = (gb.keys_dpad & (0b11110111)) | (is_up << 3);
        case SDL_SCANCODE_UP;     gb.keys_dpad = (gb.keys_dpad & (0b11111011)) | (is_up << 2);
        case SDL_SCANCODE_LEFT;   gb.keys_dpad = (gb.keys_dpad & (0b11111101)) | (is_up << 1);
        case SDL_SCANCODE_RIGHT;  gb.keys_dpad = (gb.keys_dpad & (0b11111110)) | (is_up << 0);
        case SDL_SCANCODE_X;      gb.keys_buttons = (gb.keys_buttons & (0b11110111)) | (is_up << 3);
        case SDL_SCANCODE_Z;      gb.keys_buttons = (gb.keys_buttons & (0b11111011)) | (is_up << 2);
        case SDL_SCANCODE_A;      gb.keys_buttons = (gb.keys_buttons & (0b11111101)) | (is_up << 1);
        case SDL_SCANCODE_S;      gb.keys_buttons = (gb.keys_buttons & (0b11111110)) | (is_up << 0); 
    }
    
    if !is_up {
        if e.keysym.scancode == {
            case SDL_SCANCODE_DOWN;   #through;
            case SDL_SCANCODE_UP;     #through;
            case SDL_SCANCODE_LEFT;   #through;
            case SDL_SCANCODE_RIGHT;  #through;
            case SDL_SCANCODE_X;      #through;
            case SDL_SCANCODE_Z;      #through;
            case SDL_SCANCODE_A;      #through;
            case SDL_SCANCODE_S;      interrupt(gb, .JOYPAD);
        }
    }
}

loop :: (gb: *Gameboy, delta_time: float) {
    
    if(!gb.step_through) {
        gb.clock_speed = xx ((CLOCK_SPEED * gb.clock_mul) / (delta_time * 60));
        if gb.clock_speed > CLOCK_SPEED then gb.clock_speed = CLOCK_SPEED;
        gb.cycles_left += xx(delta_time * gb.clock_speed);
    }

    while main := gb.cycles_left >= 0 {
        // Cpu
        if gb.cpu_clock <= 0 {
            if !gb.halted 
                execute(gb);

            if gb.call_stack.count > 20 {
                Basic.array_ordered_remove_by_index(*gb.call_stack, 0);
            }
            for breakpoints {
                if gb.pc == it {
                    breakpoint(gb);
                    break main;
                }
            }
        } 

        // Video
        while gb.ppu_clock <= 0 {
            LCD(gb);
        }
    
        // Audio
        audio(gb);

        // DMA
        if(gb.DMA_cycles_left >= 0) {
            addr_read : u16 = read(gb, 0xFF46);
            addr_read <<= 8;
            addr_read |= xx gb.DMA_cycles_left;
            addr_write : u16 = 0xFE00 + cast(u16) gb.DMA_cycles_left;
            write(gb, addr_write, read(gb, addr_read));
            gb.DMA_cycles_left -= 1;
        }

        TAC := gb.mem[IO_TAC];
        if(TAC >> 2 & 1) { // Timer enabled
            gb.timer += 1;
            TIMA: u16 = xx gb.mem[IO_TIMA];
            
            speed: u8 = TAC & 0b00000011;
            if speed == {
                case 0; if(gb.timer >= 1024){ TIMA += 1; gb.timer = 0;}
                case 1; if(gb.timer >= 16)  { TIMA += 1; gb.timer = 0;}
                case 2; if(gb.timer >= 64)  { TIMA += 1; gb.timer = 0;}
                case 3; if(gb.timer >= 256) { TIMA += 1; gb.timer = 0;}
            }
            
            if TIMA >= 0x100 { // overflow
                TIMA = gb.mem[IO_TMA]; // Reset it to TMA
                interrupt(gb, .TIMER);
            }
            
            gb.mem[IO_TIMA] = xx TIMA;
        }

        // Timer update
        gb.mem[IO_DIV] = gb.mem[IO_DIV] + 1;

        // Interrupts
        handle_interrupts(gb);
        
        
        // Inputs
        JOY := gb.mem[IO_JOY];
        if JOY & (1 << 4) { // Button
            JOY = 0b11010000;
            JOY |= gb.keys_buttons & 0x0F;
        }
        if JOY & (1 << 5) { // D-Pad
            JOY = 0b11100000;
            JOY |= gb.keys_dpad & 0x0F;
        }
        gb.mem[IO_JOY] = JOY; 

        gb.cpu_clock -=1;
        gb.ppu_clock -=1;
        gb.cycles_left -=1;
    }
}
