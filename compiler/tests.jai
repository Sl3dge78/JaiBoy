#import "Compiler";
#import "Basic";
#import "File";
#import "Print_Color";

#load "../common/gb.jai";
#load "codegen.jai";

#run {
    test_load_gen();
    test_programs();
    set_build_options_dc(.{do_output=false});
}

test_load_gen :: () {
    assert(load_imm8(.A) == 0x3E);
    assert(load_imm8(.B) == 0x06);
    assert(load_imm8(.C) == 0x0E);
    assert(load_imm8(.D) == 0x16);
}

run_program :: (path: string, gb: *Gameboy, builder: *String_Builder) -> bool {
    print("Testing %\t\t", path);
    cart := build_cart(path);

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

test_program :: (path: string, gb: *Gameboy, verifs: ..CPU_Verification) {
    builder : String_Builder;
    if !run_program(path, gb, *builder) {
        print_color("Failed!\n", color = .RED);
        print_color("%\n", builder_to_string(*builder), color = .RED);
        return;
    }

    success := true;
    for verifs {
        if !check_register(gb, it.reg, it.val, *builder) {
            success = false;
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

CPU_Verification :: struct {
    reg: Register;
    val : u8;
}

check_register :: (gb: *Gameboy, reg: Register, val: u8, builder: *String_Builder) -> bool{
    reg_val : u8;
    if reg == {
        case .A; reg_val = gb.cpu.a;
        case .B; reg_val = gb.cpu.b;
        case .C; reg_val = gb.cpu.c;
        case; {
            assert(false, "Register test not implemented");
            return false;
        }
    }
    ok := reg_val == val;
    if !ok {
        print_to_builder(builder, "> Register % is %. Expected %.\n", reg, reg_val, val);
        print_to_builder(builder, "Here's the state of the cpu: \n");
        print_to_builder(builder, "a: %, b: %, c: %, d: %, e: %", gb.cpu.a, gb.cpu.b, gb.cpu.c, gb.cpu.d, gb.cpu.e);
    }
    return ok;
}

test_programs :: () {
    gb := New(Gameboy,, temp);

    init(gb,, temp);

    test_program("tests/add.jai", gb, .{ .A, 2 } );
    test_program("tests/sub.jai", gb, .{ .A, 1 } );
    test_program("tests/or.jai", gb,  .{ .A, 0b1110_1101 } );
    test_program("tests/and.jai", gb, .{ .A, 0b1100_0000 } );
    test_program("tests/if_001.jai", gb, .{ .A, 1 } );
    test_program("tests/if_002.jai", gb, .{ .A, 2 } );
    test_program("tests/add_equals.jai", gb, .{ .A, 3 } );
    test_program("tests/sub_equals.jai", gb, .{ .A, 1 } );
    test_program("tests/or_equals.jai", gb, .{ .A, 0b1111_1101 } );
    test_program("tests/and_equals.jai", gb, .{ .A, 0b1000_0000 } );
    test_program("tests/xor_equals.jai", gb, .{ .A, 0b1000_1111 } );
    test_program("tests/if_003.jai", gb, .{ .C, 69 } );
    test_program("tests/if_004.jai", gb, .{ .A, 2 } );
    test_program("tests/call_001.jai", gb, .{ .A, 69 } );
    test_program("tests/call_002.jai", gb);
    test_program("tests/call_003.jai", gb, .{ .A, 4 });
    test_program("tests/call_004.jai", gb, .{ .A, 122 });
    test_program("tests/call_005.jai", gb, .{ .A, 133 });
}
