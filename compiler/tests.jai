#import "Compiler";
#import "Basic";
#import "File";
#import "Print_Color";

#load "../common/gb.jai";
#load "codegen.jai";

#run {
    test_programs();
    set_build_options_dc(.{do_output=false});
}

run_program :: (path: string, gb: *Gameboy, builder: *String_Builder) -> bool {
    print("Testing %\t\t", path);
    cart := build_cart(path,, log_level = .NORMAL);

    reset(gb);

    if !Rom.load_from_memory(cart.contents, "test.gb", *gb.rom) {
        print_to_builder(builder, "> Unable to load rom");
        return false;
    }

    i := 10_000;
    while !gb.halted && i > 0 {
        execute(gb);
        i -= 1;
    }
    if !gb.halted {
        print_to_builder(builder, "> Execution didn't complete");
        return false;
    }
    return true;
}

test_program :: (path: string, gb: *Gameboy, verifs: ..Verification) {
    builder : String_Builder;
    log("Building %", path);
    if !run_program(path, gb, *builder) {
        print_color("Failed!\n", color = .RED);
        print_color("%\n", builder_to_string(*builder), color = .RED);
        return;
    }

    success := true;
    for verifs {
        if it.kind == {
            case .CPU; {
                if !check_register(gb, it.register, it.val, *builder) {
                    success = false;
                }
            }
            case .ADDRESS; {
                if !check_address(gb, it.address, it.val, *builder) {
                    success = false;
                }
            }
        }
    }
    if !success {
        print_color("Failed!\n", color = .RED);
        print_color("%\n", builder_to_string(*builder), color = .RED);
    } else {
        print_color("OK!", color = .GREEN);
        print_color("\n", color = .RED);
    }
}

Verification :: struct {
    kind : enum {
        CPU;
        ADDRESS;
    };
    union {
        register: Register;
        address: u16;
    }
    val : u8;
}

cpu :: (reg: Register, val: u8) -> Verification {
    return .{ kind = .CPU, register = reg, val = val };
}

ram :: (addr: u16, val: u8) -> Verification {
    return .{ kind = .ADDRESS, address = addr, val = val };
}

check_register :: (gb: *Gameboy, reg: Register, val: u8, builder: *String_Builder) -> bool{
    reg_val : u8;
    if reg == {
        case .A; reg_val = gb.cpu.a;
        case .B; reg_val = gb.cpu.b;
        case .C; reg_val = gb.cpu.c;
        case .H; reg_val = gb.cpu.h;
        case .L; reg_val = gb.cpu.l;
        case; {
            assert(false, "Register test not implemented");
            return false;
        }
    }
    ok := reg_val == val;
    if !ok {
        print_to_builder(builder, "> Register % is %. Expected %.\n", reg, reg_val, val);
        print_to_builder(builder, "Here's the state of the cpu: \n");
        print_to_builder(builder, "a: %, b: %, c: %, d: %, e: %, h: %, l: %", gb.cpu.a, gb.cpu.b, gb.cpu.c, gb.cpu.d, gb.cpu.e, gb.cpu.h, gb.cpu.l);
    }
    return ok;
}

check_address :: (gb: *Gameboy, address: u16, val: u8, builder: *String_Builder) -> bool {
    address_val := gb.mem[address];
    ok := address_val == val;
    if !ok {
        print_to_builder(builder, "> Memory 0x% is %. Expected %.\n", formatInt(address, base = 16), address_val, val);
    } 
    return ok;

}

test_programs :: () {
    gb := New(Gameboy,, temp);

    init(gb,, temp);

    test_program("tests/add.jai", gb, cpu(.A, 2));
    test_program("tests/sub.jai", gb, cpu(.A, 1));
    test_program("tests/or.jai", gb,  cpu(.A, 0b1110_1101));
    test_program("tests/and.jai", gb, cpu(.A, 0b1100_0000));
    test_program("tests/if_001.jai", gb, cpu(.A, 1));
    test_program("tests/if_002.jai", gb, cpu(.B, 2));
    test_program("tests/add_equals.jai", gb, cpu(.A, 3));
    test_program("tests/sub_equals.jai", gb, cpu(.A, 1));
    test_program("tests/or_equals.jai", gb, cpu(.A, 0b1111_1101));
    test_program("tests/and_equals.jai", gb, cpu(.A, 0b1000_0000));
    test_program("tests/xor_equals.jai", gb, cpu(.A, 0b1000_1111));
    test_program("tests/if_003.jai", gb, cpu(.B, 69));
    test_program("tests/if_004.jai", gb, cpu(.A, 2));
    test_program("tests/call_001.jai", gb, cpu(.A, 69));
    test_program("tests/call_002.jai", gb);
    test_program("tests/call_003.jai", gb,cpu(.A, 4));
    test_program("tests/call_004.jai", gb,cpu(.A, 122));
    test_program("tests/call_005.jai", gb,cpu(.A, 133));
    test_program("tests/if_005.jai", gb,cpu(.A, 1));
    test_program("tests/if_006.jai", gb,cpu(.A, 0));
    test_program("tests/memory_write_001.jai", gb, ram(0xC000, 0x69));
    test_program("tests/while_001.jai", gb,cpu(.A, 10));
    test_program("tests/if_wide_001.jai", gb,cpu(.A, 69));
    test_program("tests/if_wide_002.jai", gb,cpu(.A, 69));
    test_program("tests/if_wide_003.jai", gb,cpu(.A, 69));
    test_program("tests/if_wide_004.jai", gb,cpu(.A, 69));
    test_program("tests/if_wide_005.jai", gb,cpu(.A, 69));
    test_program("tests/if_wide_006.jai", gb,cpu(.A, 69));
    test_program("tests/add_u16_001.jai", gb,cpu(.H, 0xFE), cpu(.L, 0x10));
    test_program("tests/add_u16_002.jai", gb,cpu(.H, 0xFF), cpu(.L, 0x00));
    test_program("tests/add_u16_003.jai", gb,cpu(.H, 0xFF), cpu(.L, 0x00));
    test_program("tests/or_wide_001.jai", gb,cpu(.H, 0x80), cpu(.L, 0xF1));
    test_program("tests/array_001.jai", gb,cpu(.A, 0x69));
    test_program("tests/array_002.jai", gb,cpu(.A, 0x69));
    // test_program("tests/less_or_equal_001.jai", gb,cpu(.A, 69));
    // test_program("tests/less_or_equal_002.jai", gb,cpu(.A, 69));
    // test_program("tests/sub_002.jai", gb,cpu(.A, 1));
}
