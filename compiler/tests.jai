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
    r := load_instruction(.A, .IMM_8);
    assert(load_instruction(.A, .IMM_8) == 0x3E);
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
    reg: Operation_Target;
    val : u8;
}

check_register :: (gb: *Gameboy, reg: Operation_Target, val: u8, builder: *String_Builder) -> bool{
    if reg == {
        case .A; {
            ok := gb.cpu.a == val;
            if !ok {
                print_to_builder(builder, "> Register % is %. Expected %.", reg, gb.cpu.a, val);
            }
            return ok;
        }
        case .B; {
            ok := gb.cpu.b == val;
            if !ok {
                print_to_builder(builder, "> Register % is %. Expected %.", reg, gb.cpu.a, val);
            }
            return ok;

        }
        case; {
            assert(false, "Register test not implemented");
            return false;
        }
    }
}

test_programs :: () {
    gb := New(Gameboy,, temp);

    init(gb,, temp);

    test_program("tests/add.jai", gb, .{ .B, 2 } );
    test_program("tests/sub.jai", gb, .{ .B, 1 } );
    test_program("tests/or.jai", gb,  .{ .B, 0b1110_1101 } );
    test_program("tests/and.jai", gb, .{ .B, 0b1100_0000 } );
    test_program("tests/if_001.jai", gb, .{ .B, 1 } );
    test_program("tests/if_002.jai", gb, .{ .B, 2 } );
}
