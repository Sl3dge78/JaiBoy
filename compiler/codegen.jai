build_cart :: (file: string, verbose := false) -> MBC1 {
    w := compiler_create_workspace();
    
    options := get_build_options();
    options.output_type = .NO_OUTPUT;
    options.runtime_support_definitions = .OMIT;

    procedures : [..] *Code_Procedure_Header;

    set_build_options(options, w);
    compiler_begin_intercept(w);
    add_build_file(file, w);

    while true {
        msg := compiler_wait_for_message();
        if !msg continue;
        if msg.kind == .TYPECHECKED {
            tc := cast(*Message_Typechecked) msg;
            gather(tc, *procedures);
        }

        if msg.kind == .COMPLETE {
            break;
        }

    }
    compiler_end_intercept(w);
    set_build_options_dc(.{do_output = false});
    ok, cart := generate_assembly(procedures, verbose);
    assert(ok);
    return cart;
}

gather :: (msg: *Message_Typechecked, procedures: *[..]*Code_Procedure_Header) {
    for tc: msg.all {
        expr := tc.expression;
        if expr.enclosing_load {
            if expr.enclosing_load.enclosing_import.module_type != .MAIN_PROGRAM then continue;
        }

        if expr.kind == {
            case .PROCEDURE_HEADER; {
                array_add(procedures, cast(*Code_Procedure_Header) expr);
            }
            case; {
                // We don't care about the rest. yet!
            }
        }
    }
}


generate_assembly :: (procedures: [..]*Code_Procedure_Header, verbose := false) -> bool, MBC1 {
    compiled : [..]Compiled_Procedure;
    for procedures {
        ok, proc := generate_procedure(it);
        if !ok {
            log_error("Error compiling procedure. Exiting.");
            return false, .{};
        }
        array_add(*compiled, proc);
        if verbose {
            log("%:", it.name);
            dump_procedure(proc);
        }
    }
    cart := output_rom(compiled);
    return true, cart;
}

output_rom :: (compiled: []Compiled_Procedure) -> MBC1 {
    builder: String_Builder;
    cart := New(MBC1,, temp);

    cart.header.entry_point = .[0xc3, 0x50, 0x1, 0x0];
    for compiled {
        assert(it.base_address != 0);
        i := it.base_address;
        memcpy(cart.contents.data + i, it.bytes.data, it.bytes.count);
    }

    return cart;

}

dump_procedure :: (proc: Compiled_Procedure) {
    i := 0;
    while i < proc.bytes.count {

        builder : String_Builder;
        op := OPCODE_DESC_TABLE[proc.bytes[i]];
        
        // Addr
        print_to_builder(*builder, "0x% ", formatInt(i, 16, 4));

        // Bytes
        print_to_builder(*builder, "% ", formatInt(proc.bytes[i], 16, 2));
        for 1..op.bytes - 1 {
            print_to_builder(*builder, "% ", formatInt(proc.bytes[i + it], 16, 2));
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
        i2 := op.bytes - 1;
        while (i2 >= 1) {
            print_to_builder(*builder, "%", formatInt(proc.bytes[i + i2], 16, 2));
            i2 -= 1;
        }

        builder_string := builder_to_string(*builder,, temp);
        log("%", builder_string);
        i += op.bytes;
    }
}

generate_procedure :: (proc: *Code_Procedure_Header) -> bool, Compiled_Procedure {
    result: Compiled_Procedure;
    assert(proc.body_or_null != null, "Procedure didn't compile?");
    body := proc.body_or_null;
    if !compile_block(body.block, *result) {
        return false, .{};
    }

    if proc.name == "main" {
        result.base_address = 0x150;
        output_bytes(*result, .HALT);
    }

    return true, result;
}

compile_block :: (block: *Code_Block, procedure: *Compiled_Procedure) -> bool {
    for block.members {
        push_member(procedure, it.name);
    }

    if block.block_type != .IMPERATIVE {
        log_error("Unhandled block type: %", block.block_type);
        return false;
    }

    for block.statements {
        compile_statement(it, procedure);
    }

    for block.members {
        pop_member(procedure);
    }
    return true;

}

compile_statement :: (node: *Code_Node, procedure: *Compiled_Procedure) -> bool {
    if node.kind == {
        case .DECLARATION; {
            decl := cast(*Code_Declaration)node;
            if decl.type_inst != null {
                if decl.type_inst.pointer_to != null {
                    log_error("Pointers aren't implemented yet");
                    return false;
                }
                if decl.type_inst.array_element_type != null {
                    log_error("Arrays aren't implemented yet");
                    return false;
                }
                ti := decl.type_inst.result;
                if ti.type != .INTEGER {
                    log_error("Only integers are supported");
                    return false;
                }
                if ti.runtime_size > 1 {
                    log_error("Only 8 bit integers are supported");
                    return false;
                }
            }
            if decl.expression == null {
                log_error("I don't know what to do here");
            } else {
                target := find_member(procedure, decl.name);
                if !compile_expression(decl.expression, procedure, target) { return false; }
            }

            return true;
        }
        case .IF; {
            code := node.(*Code_If);
            if code.if_flags != 0 {
                log_error("Unhandled if %.", code.if_flags);
                return false;
            }
            compile_expression(code.condition, procedure, .A);
            output_bytes(procedure, .CP_D8, 0x1);
            then_jump := add_jump(procedure, .IF_FALSE); 
            compile_block(code.then_block, procedure);
            else_jump : int = -1;  
            if code.else_block != null {
                else_jump = add_jump(procedure, .ALWAYS);
            }
            patch_jump(then_jump, procedure);
            compile_block(code.else_block, procedure);
            if code.else_block != null {
                patch_jump(else_jump, procedure);
            }

            return true;
        }
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;

            if op == {
                case #char "="; {
                    if bin_op.left.kind != .IDENT {
                        log_error("We expected an identifier to the left of a = operator, but we got a %", bin_op.left.kind);
                        return false;
                    }
                    target := find_member(procedure, bin_op.left.(*Code_Ident).name);
                    return compile_expression(bin_op.right, procedure, target);
                }
                case; {
                    log_error("Unhandled binary operator statement %", operator_to_string2(xx op));
                    return false;
                }
            };
        }
        case; {
            log_error("Unhandled statement kind: %", node.kind);
            return false;
        }
    }

}

compile_expression :: (node: *Code_Node, procedure: *Compiled_Procedure, destination_register : Operation_Target = .A) -> bool {
    if node.kind == {
        case .LITERAL; {
            lit := node.(*Code_Literal);
            if lit.value_type == {
                case .NUMBER; {
                    if lit.value_flags & .FLOAT { 
                        log_error("Floats aren't supported");
                        return false;
                    }
                    if lit._u64 > 0xFF {
                        log_error("u16s aren't supported"); // @TODO
                        return false;
                    }
                    output_bytes(procedure, load_instruction(destination_register, .IMM_8));
                    output_bytes(procedure, lit._u64.(u8));
                    return true;
                }
                case .BOOLEAN;{
                    output_bytes(procedure, load_instruction(destination_register, .IMM_8));
                    output_bytes(procedure, lit._u64.(u8));
                    return true;
                }
                case; {
                    log_error("Unhandled literal %", lit.value_type);
                    return false;
                }
            };
        }
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;

            if op == {
                case #char "+"; #through; 
                case #char "-"; #through; 
                case #char "&"; #through; 
                case #char "|"; {
                    compile_expression(bin_op.left, procedure, .A);
                    compile_expression(bin_op.right, procedure, .B);
                    op_byte : u8;
                    if op == {
                        case #char "+"; op_byte = 0x80; // ADD A, B
                        case #char "-"; op_byte = 0x90; // SUB B
                        case #char "&"; op_byte = 0xA0; // AND B
                        case #char "|"; op_byte = 0xB0; // OR  B
                        case; return false;
                    }
                    output_bytes(procedure, op_byte); 
                }
                case; { 
                    log_error("Unhandled binary operator expression %", operator_to_string2(op)); 
                    return false;
                }
            }
            if destination_register != .A {
                output_bytes(procedure, load_instruction(destination_register, .A));
            }
            return true;
        }
        case; {
            log_error("Unhandled expression kind: %", node.kind);
            return false;
        }
    }
}

operator_to_string2 :: (op: Operator_Type) -> string #expand {
    if op < 127 {
        return to_string(*op.(u8));
    } else {
        return operator_to_string(op);
    }
}

output_bytes :: (procedure: *Compiled_Procedure, bytes: ..u8) {
    array_add(*procedure.bytes, ..bytes);
}

output_bytes :: (procedure: *Compiled_Procedure, instr: Instruction_Kind, bytes : ..u8) {
    array_add(*procedure.bytes, xx instr);
    array_add(*procedure.bytes, ..bytes);
}

Jump_Kind :: enum {
    IF_FALSE;
    ALWAYS;
}


add_jump :: (procedure: *Compiled_Procedure, kind: Jump_Kind) -> int {
    if #complete kind == {
        case .IF_FALSE; {
            addr := procedure.bytes.count;
            output_bytes(procedure, .JR_NZ_REL);
            output_bytes(procedure, 0x00);
            return addr;
        }
        case .ALWAYS; {
            addr := procedure.bytes.count;
            output_bytes(procedure, .JR_REL);
            output_bytes(procedure, 0x00);
            return addr;
        }
    };
}

patch_jump :: (jump_addr: int, procedure: *Compiled_Procedure) {
    current_addr := procedure.bytes.count;
    end_of_jump := jump_addr + 2;
    distance := current_addr - end_of_jump;
    assert(distance <= 127, "Long jumps arent supported yet");
    procedure.bytes[jump_addr + 1] = cast,no_check(u8)(distance.(s8));
}

push_member :: (using procedure: *Compiled_Procedure, name: string) {
    ok, pos := find_next_available_register(procedure);
    assert(ok, "Too many members in procedure.");
    array_add(*members, .{name, pos});
}

pop_member :: (using procedure: *Compiled_Procedure) {
    members.count -= 1;
}

find_member :: (using procedure: *Compiled_Procedure, name: string) -> Operation_Target {
    for members {
        if it.name == name then return it.register;
    }
    assert(false, "Member % couldn't be found.", name);
    return .A;
}

find_next_available_register :: (using procedure: *Compiled_Procedure) -> bool, Operation_Target {
    for r: 0..5 {
        for members {
            if it.register == xx r then continue r;
        }

        return true, xx r;
    }
    return false, 0;
}

Member :: struct {
    name: string;
    register: Operation_Target;
}


Compiled_Procedure :: struct {
    base_address : u16;
    bytes: [..]u8;
    members: [..] Member;
}

Instruction_Kind :: enum u8 {
    NOP :: 0x0;
    JR_REL :: 0x18;
    JR_NZ_REL :: 0x20;
    LD_A_IMM :: 0x3E;
    HALT :: 0x76;
    CP_D8 :: 0xFE;
}

load_instruction :: (dst: Operation_Target, src: Operation_Target) -> u8 {
    if src <= .A {
        assert(!(src == .HL_INDIRECT && src == .HL_INDIRECT), "This is HALT");
        assert(dst <= .A);
        return 0x40 + (dst.(u8) * 8) + src.(u8);
    } 
    if src == {
        case .IMM_8; {
            lo : u8 = 0x6 + ((dst.(u8) % 2) * 0x8);
            hi : u8 = (dst.(u8) / 2) << 4;
            return lo | hi;
        }
        case; {
            assert(false, "Unsupported");
            return 0x0;
        }
    }
    assert(false, "Unsupported");
    return 0x0;
}

Operation_Target :: enum {
    B :: 0;
    C :: 1;
    D :: 2;
    E :: 3;
    H :: 4;
    L :: 5;
    HL_INDIRECT :: 6;
    A :: 7;
    BC;
    DE;
    HL;
    IMM_8;
    IMM_16;
    BC_INDIRECT;
    DE_INDIRECT;
    HL_PLUS_INDIRECT;
    HL_MINUS_INDIRECT;
}

Cart_Header :: struct {
    blank: [0x100]u8;
    entry_point: [0x4]u8; // 0x100
    stuff: [0x43]u8;      // 0x104
    cart_type: u8;        // 0x147
    rom_size: u8;         // 0x148
    ram_size: u8;         // 0x149
    destination_code: u8; // 0x14A
    licensee: u8;         // 0x14B
    mask: u8;             // 0x14C
    header_checksum: u8;  // 0x14D
    global_checksum: u16;

    #place blank;
    full_contents: [0x14f]u8;
}

MBC1 :: struct {
    header: Cart_Header;
    #place header;
    contents: [0x8000]u8;
}

#load "../common/opcodes.jai";
