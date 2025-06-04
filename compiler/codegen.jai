global_verbose := false;

#add_context current_procedure: *Compiled_Procedure;
#add_context current_node: *Code_Node;

build_cart :: (file: string, verbose := false) -> MBC1 {
    global_verbose = verbose;
    if global_verbose {
        log("%", file);
    }
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
    ok, cart := generate_assembly(procedures);
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


generate_assembly :: (procedures: [..]*Code_Procedure_Header) -> bool, MBC1 {
    compiled : [..]Compiled_Procedure;
    errored := false;
    for procedures {
        proc := generate_procedure(it);

        if proc.errors.count > 0 {
            errored = true;
            for proc.errors {
                loc := it.location;
                compiler_report(loc.enclosing_load.fully_pathed_filename, loc.l0, loc.c0, it.message); 
            }
            continue;
        }
        array_add(*compiled, proc);
        if global_verbose {
            log("%:", it.name);
            builder: String_Builder;
            disassemble_procedure(*builder, proc);
            log("%", builder_to_string(*builder));
        }
    }
    if errored { 
        return false, .{};
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

disassemble_procedure :: (builder: *String_Builder, proc: Compiled_Procedure) {
    disassemble_bytes(builder, ..proc.bytes);
}

generate_procedure :: (proc: *Code_Procedure_Header) -> Compiled_Procedure {
    result: Compiled_Procedure;
    assert(proc.body_or_null != null, "Procedure didn't compile?");
    body := proc.body_or_null;
    compile_block(,, current_procedure = *result, current_node = body.block);
    if result.errors.count > 0 {
        return result;
    }

    if proc.name == "main" {
        result.base_address = 0x150;
        output_bytes(*result, .HALT);
    }

    return result;
}

compile_block :: () {
    block := context.current_node;
    for block.members {
        push_member(it.name);
    }

    if block.block_type != .IMPERATIVE {
        error(tprint("Unhandled block type: %", block.block_type));
        return;
    }

    for block.statements {
        compile_statement(,, current_node = it);
        if context.current_procedure.errors.count > 0 then break;
    }

    for block.members {
        pop_member();
    }
}

compile_statement :: () {
    if node.kind == {
        case .DECLARATION; {
            decl := cast(*Code_Declaration)node;
            if decl.type_inst != null {
                if decl.type_inst.pointer_to != null {
                    error("Pointers aren't implemented yet");
                    return;
                }
                if decl.type_inst.array_element_type != null {
                    error("Arrays aren't implemented yet");
                    return;
                }
                ti := decl.type_inst.result;
                if ti.type != .INTEGER {
                    error("Only integers are supported");
                    return;
                }
                if ti.runtime_size > 1 {
                    error("Only 8 bit integers are supported");
                    return;
                }
            }
            if decl.expression != null {
                target := member_location(procedure, decl.name);
                compile_expression(procedure, decl.expression, target);
            }

            return;
        }
        case .IF; { 
            code := node.(*Code_If);
            if code.if_flags != 0 {
                error(tprint("Unhandled if %.", code.if_flags));
                return ;
            }
            // If expects the result of the condition to be in .A
            compile_condition(procedure, code.condition);
            then_jump := add_jump(procedure, .IF_FALSE); 
            compile_block(procedure, code.then_block);
            else_jump : int = -1;  
            if code.else_block != null {
                else_jump = add_jump(procedure, .ALWAYS);
            }
            patch_jump(then_jump, procedure);
            compile_block(procedure, code.else_block);
            if code.else_block != null {
                patch_jump(else_jump, procedure);
            }

            return;
        }
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;
            if bin_op.left.kind != .IDENT {
                error(tprint("We expected an identifier to the left of a = operator, but we got a %", bin_op.left.kind));
                return;
            }

            if op == {
                case #char "="; {
                    target := member_location(procedure, bin_op.left.(*Code_Ident).name);
                    compile_expression(procedure, bin_op.right, target);
                }
                // @TODO, keep target in A
                case .PLUS_ASSIGN; #through;
                case .MINUS_ASSIGN; #through;
                case .BITWISE_AND_ASSIGN; #through;
                case .BITWISE_OR_ASSIGN; #through;
                case .BITWISE_XOR_ASSIGN; {
                    get_instruction :: (op: Operator_Type) -> Arithmetic_Instruction {
                        if op == {
                            case .PLUS_ASSIGN; return .ADD;
                            case .MINUS_ASSIGN; return .SUB;
                            case .BITWISE_AND_ASSIGN; return .AND;
                            case .BITWISE_OR_ASSIGN; return .OR;
                            case .BITWISE_XOR_ASSIGN; return .XOR;
                            case; unreachable();  return 0;
                        }
                    }

                    temp := push_temporary(procedure);
                    defer pop_temporary(procedure, temp);
                    compile_expression(procedure, bin_op.right, member_location(procedure, temp));

                    move_member(procedure, bin_op.left.(*Code_Ident).name, .A);
                    output_bytes(procedure, arithmetic_instruction(get_instruction(op), member_location(procedure, temp)));
                }
                case; {
                    error(tprint("Unhandled binary operator statement %", operator_to_string2(xx op)));
                    return;
                }
            };
        }
        case; {
            error(tprint("Unhandled statement kind: %", node.kind));
            return;
        }
    }
}

compile_expression :: (procedure: *Compiled_Procedure, node: *Code_Node, destination_register : Register = .A) {
    if node.kind == {
        case .LITERAL; {
            lit := node.(*Code_Literal);
            if lit.value_type == {
                case .NUMBER; {
                    if lit.value_flags & .FLOAT { 
                        error("Floats aren't supported");
                        return;
                    }
                    if lit._u64 > 0xFF {
                        error("u16s aren't supported"); // @TODO
                        return;
                    }
                    output_bytes(procedure, load_imm8(destination_register), lit._u64.(u8));
                    return;
                }
                case .BOOLEAN;{
                    output_bytes(procedure, load_imm8(destination_register), lit._u64.(u8));
                    return;
                }
                case; {
                    error(tprint("Unhandled literal %", lit.value_type));
                    return;
                }
            };
        }
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;
            compile_expression(procedure, bin_op.right, .B);
            compile_expression(procedure, bin_op.left, .A); 

            instr: Arithmetic_Instruction;
            if op == {
                case #char "+"; instr = .ADD;
                case #char "-"; {
                    instr = .SUB;
                }
                case #char "&"; instr = .AND;
                case #char "|"; instr = .OR;
                case; { 
                    error(tprint("Unhandled binary operator expression '%'", operator_to_string2(op))); 
                    return;
                }
            }
            output_bytes(procedure, arithmetic_instruction(instr, .B)); 
        }
        case .IDENT; {
            ident := node.(*Code_Ident);
            move_member(procedure, ident.name, destination_register);
        }
        case; {
            error(tprint("Unhandled expression kind: %", node.kind));
            return;
        }
    }
}

compile_condition :: (procedure: *Compiled_Procedure, node: *Code_Node) {
    if node.kind == {
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;
            compile_expression(procedure, bin_op.right, .B);
            compile_expression(procedure, bin_op.left, .A); 

            instr: Arithmetic_Instruction;
            if op == {
                case .IS_EQUAL; instr = .CP;
                case; { 
                    error(tprint("Unhandled binary operator expression '%'", operator_to_string2(op))); 
                    return;
                }
            }

            output_bytes(procedure, arithmetic_instruction(instr, .B)); 
        }
        case .IDENT; #through;
        case .LITERAL; {
            compile_expression(procedure, node);
            output_bytes(procedure, .CP_D8, 0x1);
        }
        case; {
            error(tprint("Unhandled condition expression kind: %", node.kind));
            return;
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

Instruction_Kind :: enum u8 {
    NOP :: 0x0;
    JR_REL :: 0x18;
    JR_NZ_REL :: 0x20;
    LD_A_IMM :: 0x3E;
    HALT :: 0x76;
    CP_D8 :: 0xFE;
}

load_instruction :: (dst: Register, src: Register) -> u8 {
    assert(!(src == .HL_INDIRECT && src == .HL_INDIRECT), "This is HALT");
    assert(dst <= .A);
    assert(dst != src, "This is a dumb and useless operation");
    return 0x40 + (dst.(u8) * 8) + src.(u8);
}

load_imm8 :: (dst: Register) -> u8 {
    lo : u8 = 0x6 + ((dst.(u8) % 2) * 0x8);
    hi : u8 = (dst.(u8) / 2) << 4;
    return lo | hi;
}

Arithmetic_Instruction :: enum u8 {
    ADD :: 0x80;
    ADC :: 0x88;
    SUB :: 0x90;
    SBC :: 0x98;
    AND :: 0xA0;
    XOR :: 0xA8;
    OR  :: 0xB0;
    CP  :: 0xB8;
}

arithmetic_instruction :: (kind: Arithmetic_Instruction, src: Register) -> u8 {
    return kind.(u8) + src.(u8);
}

swap_instruction :: (dst: Register) -> [2]u8 {
    result : [2]u8;
    result[0] = 0xCB;
    result[1] = 0x30 + dst.(u8);
    return result;
}

Register :: enum {
    B :: 0;
    C :: 1;
    D :: 2;
    E :: 3;
    H :: 4;
    L :: 5;
    HL_INDIRECT :: 6;
    A :: 7;
}

register_preference :: Register.[
    .A,
    .B,
    .C,
    .D,
    .E,
    .H,
    .L
];

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

unreachable :: () #expand {
    assert(false, "Unreachable");
    return;
}

#load "../common/opcodes.jai";
#load "procedure.jai";
