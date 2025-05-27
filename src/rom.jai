File_Utilities :: #import "File_Utilities";
String :: #import "String";

ROM_ENTRY ::     0x100;
ROM_LOGO ::      0x104;
ROM_LOGO_END ::  0x133;
ROM_LOGO_SIZE :: ROM_LOGO_END - ROM_LOGO;
ROM_TITLE ::     0x134;
ROM_MANUF ::     0x13F;
ROM_CGB ::       0x143;
ROM_LICENSEE ::  0x144;
ROM_SGB ::       0x146;
ROM_CARTRIDGE :: 0x147;
ROM_ROM_SIZE ::  0x148;
ROM_RAM_SIZE ::  0x149;
ROM_DEST_CODE :: 0x14A;
ROM_OLD_LICEN :: 0x14B;
ROM_ROM_VER ::   0x14C;
ROM_HDR_CHKSM :: 0x14D;
ROM_GBL_CHKSM :: 0x14E;

Bank_Mode :: enum {
    ROM_BANKING_MODE:: 0;
    RAM_BANKING_MODE:: 1;
}

Rom_Type :: enum {
    NONE :: 0x00;
    MBC1;
    MBC2;
    MBC3;
    MBC5;   
}

get_rom_type :: (id : u8) -> Rom_Type {
    if id == {
        case 0x00; return .NONE;
        case 0x01; #through;
        case 0x02; #through;
        case 0x03; return .MBC1;

        case 0x05; #through;
        case 0x06; return .MBC2;

        case 0x0F; #through;
        case 0x10; #through;
        case 0x11; #through;
        case 0x12; #through;
        case 0x13; return .MBC3;

        case 0x19; #through;
        case 0x1A; #through;
        case 0x1B; #through;
        case 0x1C; #through;
        case 0x1D; #through;
        case 0x1E; return .MBC5;
        case; { 
            log_error("Cartidge type % is not supported. Some things might not work.", hex(id));
            return .NONE;
        }
    }
}

Rom :: struct {
    path : string;

    rom_data: []u8;
    rom_bank: u16;
    ram_enabled : bool;
    ram_data: []u8;
    ram_bank: u8;

    type: Rom_Type;
    bank_lo: u8;
    bank_hi: u8;
    bank_mode: Bank_Mode;

    get_ram_size :: (val: u8) -> u32 {
        if val == {
            case 0; return 0;
            case 1; return 2048;
            case 2; return 8192;
            case 3; return 32768;
            case 4; return 131072;
            case 5; return 65536;
        }
        return 0;
    }

    get_save_path :: (rom_path: string) -> string {
        path := String.path_strip_extension(rom_path);
        builder : String_Builder;
        append(*builder, path);
        append(*builder, ".sav");
        return builder_to_string(*builder,, temp);
    }

    load_save :: (rom: *Rom) -> bool {
        save_path := get_save_path(rom.path);

        if !File_Utilities.file_exists(save_path) then return false;

        save, success := File.read_entire_file(save_path);
        defer free(save);
        if !success {
            log_error("Unable to read save file at %.", save_path);
            return false;
        }
        if save.count != rom.ram_data.count {
            log_error("Saved data isn't the same size as the allocated ram.");
            return false;
        }

        memcpy(rom.ram_data.data, save.data, save.count);
        return true;
    }

    load :: (rom_file: string, result: *Rom) -> bool {
        content, success := File.read_entire_file(rom_file);
        if !success {
            log_error("Unable to open %", rom_file);
            return false;
        }
        result.path = rom_file;
        result.rom_data.data = content.data;
        result.rom_data.count = content.count;

        result.type = get_rom_type(result.rom_data[ROM_CARTRIDGE]);
        log("%", result.type);

        result.ram_data.count = get_ram_size(result.rom_data[ROM_RAM_SIZE]);
        result.ram_data.data = alloc(result.ram_data.count);
        
        Rom.load_save(result);
        
        return true;
    }

    reset :: (rom : *Rom) {
        rom.bank_lo = 1;
        rom.bank_hi = 0;
        change_bank(rom);
        Rom.load_save(rom);
    }

    destroy :: (rom : *Rom) {
        free(rom.rom_data.data);
        free(rom.ram_data.data);
    }

    read :: (rom : *Rom, address: u16) -> u8 {
        if address >= 0x0000 && address <= 0x3FFF {
            return rom.rom_data[address];
        } else if address >= 0x4000 && address <= 0x7FFF { // ROM BANK n
            relative : u32 = address - 0x4000;
            addr : u32 = relative + cast(u32)0x4000 * cast(u32)rom.rom_bank;
            return rom.rom_data[addr];
        }  else if address >= 0xA000 && address <= 0xBFFF { // RAM
            if !rom.ram_enabled then return 0;
            if rom.type == {
                case .MBC3; {
                    if rom.ram_bank == {
                        case 0x08; return 0; // @Todo
                        case 0x09; return 0; // @Todo
                        case 0x0A; return 0; // @Todo
                        case 0x0B; return 0; // @Todo
                        case 0x0C; return 0; // @Todo
                    }
                }
            }

            relative := address - 0xA000;
            return rom.ram_data[relative + 0x2000 * rom.ram_bank];    
        }
        assert(false, "Unreachable");
        return 0;
    }

    write :: (rom: *Rom, address: u16, value: u8) {
        if address >= 0x0000 && address <= 0x1FFF {
            if((value & 0xF) == 0xA) {
                rom.ram_enabled = true;
                return;
            } else {
                rom.ram_enabled = false;
                save_file := File.file_open(Rom.get_save_path(rom.path), for_writing = true, keep_existing_content = false);
                File.file_write(*save_file, rom.ram_data.data, rom.ram_data.count);
                File.file_close(*save_file);
                return;
            } 
        } else if address >= 0x2000 && address <= 0x3FFF {
            if rom.type == {
                case .MBC1; #through;
                case .MBC2; {
                    rom.bank_lo = value & 0b0001_1111;
                    if rom.bank_lo == {
                        case 0x00; #through;
                        case 0x20; #through;
                        case 0x40; #through;
                        case 0x60; 
                            rom.bank_lo += 1;
                    }
                    change_bank(rom);
                    return;
                }
                case .MBC3; {
                    rom.bank_lo = value;
                    if rom.bank_lo == 0 then rom.bank_lo = 1;
                    change_bank(rom);
                    return;
                }
                case .MBC5; {
                    if address <= 0x2FFF rom.bank_lo = value;
                    else if address >= 0x3000 rom.bank_hi = value;

                    change_bank(rom);
                    return;
                }
            }   
        } else if address >= 0x4000 && address <= 0x5FFF {
            if rom.type == .MBC5 {
                rom.ram_bank = value & 0xF;
                return;
            } else {
                rom.bank_hi = value & 0b11;
                change_bank(rom);   
                return;         
            }
        } else if address >= 0x6000 && address <= 0x7FFF {
            if rom.type == {
                case .MBC1; rom.bank_mode == xx value; return;
                case .MBC3; return; // Latch clock data, we do nothing.
            }
        } else if address >= 0xA000 && address <= 0xBFFF {
            relative := address - 0xA000;
            if rom.ram_data.count > relative {
                rom.ram_data[relative + 0x2000 * rom.ram_bank] = value;
            }
            return;
        }
    }

    
};

change_bank :: (rom: *Rom) {
    rom.rom_bank = rom.bank_lo;
    if rom.type == {
        case .MBC1; {
            if rom.bank_mode == .ROM_BANKING_MODE {
                rom.rom_bank |= rom.bank_hi << 5;
            } else {
                rom.ram_bank = rom.bank_hi;
            }
        }
        case .MBC3; {
            rom.ram_bank = rom.bank_hi;            
        }
        case .MBC5; {
            rom.rom_bank |= rom.bank_hi << 7;
        }
    }
}
