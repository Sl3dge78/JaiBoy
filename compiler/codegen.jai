#add_context current_procedure: *Compiled_Procedure;
#add_context current_node: *Code_Node;

build_cart :: (file: string) -> MBC1 {
    log_verbose("%", file);
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
            case .DECLARATION; {
                decl := expr.(*Code_Declaration);
                if decl.type_inst != null {
                    log("type inst: %", decl.type_inst);
                }
                if decl.expression.kind == .PROCEDURE_HEADER {
                    proc_header := cast(*Code_Procedure_Header) decl.expression;
                    if proc_header.procedure_flags & .ELSEWHERE then continue;
                    array_add(procedures, proc_header);
                } else {
                    error(tprint("Unhanded top level declaration: %", decl.expression.kind));
                    return;
                }
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
    }
    if errored { 
        return false, .{};
    }

    if !place_procedures(compiled) {
        return false, .{};
    }

    if !resolve_calls(compiled) {
        return false, .{};
    }

    log_verbose("=====");
    for compiled {
        log_verbose("%:", it.procedure_header.name);
        builder: String_Builder;
        disassemble_procedure(*builder, it);
        log_verbose("%", builder_to_string(*builder));
    }

    cart := output_rom(compiled);
    return true, cart;
}

output_rom :: (compiled: []Compiled_Procedure) -> MBC1 {
    builder: String_Builder;
    cart := New(MBC1,, temp);

    cart.header.entry_point = .[0xc3, 0x50, 0x1, 0x0];
    for compiled {
        assert(it.base_address != 0, "Procedure \"%\" wasn't placed in program!", it.procedure_header.name);
        i := it.base_address;
        memcpy(cart.contents.data + i, it.bytes.data, it.bytes.count);
    }

    return cart;
}

disassemble_procedure :: (builder: *String_Builder, proc: Compiled_Procedure) {
    disassemble_bytes(builder, proc.bytes, true, proc.base_address);
}

generate_procedure :: (proc: *Code_Procedure_Header) -> Compiled_Procedure {
    log_verbose("Compiling %", proc.name);
    result: Compiled_Procedure;
    result.procedure_header = proc;
    assert(proc.body_or_null != null, "Procedure didn't compile?");
    body := proc.body_or_null;
    compile_block(,, current_procedure = *result, current_node = body.block);
    if result.errors.count > 0 {
        return result;
    }

    if proc.name == "main" {
        output_bytes(.HALT,, current_procedure = *result);
    } else if !result.return_added {
        output_bytes(.RET,, current_procedure = *result);
    }

    return result;
}

place_procedures :: (procs: []Compiled_Procedure) -> bool {
    // Find main
    main : *Compiled_Procedure;
    for *procs {
        if it.procedure_header.name == "main" {
            main = it;
        }
    }
    if main == null {
        log_error("No entry point found in program!");
        return false;
    }
    padding : u16 : 1;
    main.base_address = 0x150;
    next_pos : u16 = main.base_address + xx main.bytes.count + padding;
    for *procs {
        if it == main then continue;
        it.base_address = next_pos;
        next_pos += xx it.bytes.count + padding;
    }
    return true;
}

resolve_calls :: (procs: []Compiled_Procedure) -> bool {
    for *proc: procs {
        for call: proc.external_calls {
            addr := call.instr;
            ok, other := find_procedure(call.procedure, procs);
            if !ok {
                log_error("Couldnt find procedure \"%\" called in \"%\".", call.procedure.name, proc.procedure_header.name);
                return false;
            }
            other_addr := other.base_address;
            proc.bytes[addr + 1] = cast(u8)(other_addr & 0xFF);
            other_addr >>= 8;
            proc.bytes[addr + 2] = cast(u8)(other_addr & 0xFF);
        }
        array_reset(*proc.external_calls);
    }
    return true;
}

find_procedure :: (header: *Code_Procedure_Header, procs: []Compiled_Procedure) -> bool, *Compiled_Procedure {
    for *procs {
        if it.procedure_header == header then return true, it;
    }

    return false, null;
}

compile_block :: () {
    block := context.current_node.(*Code_Block);
    for block.members {
        assert(it.kind == .DECLARATION);
        push_member(it.name, null);
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
        pop_member(it.name);
    }
}

compile_statement :: () {
    node := context.current_node;
    log_verbose("Statement %", node.kind);
    if node.kind == {
        case .DECLARATION; {
            decl := cast(*Code_Declaration)node;
            t := to_gb_type(decl.type);
            if t != .NONE {
                type_member(decl.name, t);
            }
            if decl.expression != null {
                compile_expression(decl.name,, current_node = decl.expression);
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
            jumps := compile_condition(,, current_node = code.condition);
            initial_members := copy_members(,, temp);

            compile_block(,, current_node = code.then_block);
            then_members := copy_members(,, temp);

            else_jump : int = -1;  
            if code.else_block != null {
                skip_else := begin_jump(.ALWAYS);
                for jumps {
                    end_jump(it);
                }
                compile_block(,, current_node = code.else_block);
                reconcile_members(then_members);
                end_jump(skip_else);
            } else {
                reconcile_members(initial_members);
                for jumps {
                    end_jump(it);
                }
            }

        }
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;
            ok, left, temp := rvalue(bin_op.left);
            if !ok then return;
            defer {
                if temp {
                    pop_temporary(left);
                }
            }

            if op == {
                case #char "="; {
                    compile_expression(left,, current_node = bin_op.right);
                }
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

                    temp := push_temporary();
                    defer pop_temporary(temp);
                    compile_expression(temp,, current_node = bin_op.right);

                    arithmetic_instruction(get_instruction(op), left, temp);
                    set_member_location(left, slot(.A));
                }
                case; {
                    error(tprint("Unhandled binary operator statement %", operator_to_string2(xx op)));
                    return;
                }
            };
        }
        case .RETURN; {
            ret := node.(*Code_Return);
            if ret.return_flags != 0 {
                error(tprint("Unsupported return flags: %", ret.return_flags));
                return;
            }
            if ret.arguments_sorted.count > 1 {
                error(tprint("Unsupported multiple arguments."));
                return;
            }
            if ret.arguments_sorted.count == 1 {
                ensure_register_empty(.A);
                temp := push_temporary();
                defer pop_temporary(temp);
                set_member_location(temp, slot(.A));
                compile_expression(temp,, current_node = ret.arguments_sorted[0]);
            }
            output_bytes(.RET);
            context.current_procedure.return_added = true;
        }
        case .PROCEDURE_CALL; {
            call := node.(*Code_Procedure_Call);
            if call.resolved_procedure_expression == null || call.resolved_procedure_expression.kind != .PROCEDURE_HEADER {
                error("The expression isn't a procedure header");
                return;
            }
            header := call.resolved_procedure_expression.(*Code_Procedure_Header);
            if header.procedure_flags & .ELSEWHERE {
                log_verbose("Inserting % in %", header.name, context.current_procedure.procedure_header.name);
                ok, bytes := get_intrinsic(header.name, call);
                if !ok return;
                output_bytes(bytes);
            } else {
                add_call(header);
            }
        }

        case .WHILE; {
            w := node.(*Code_While);
            initial_members := copy_members(,, temp);
            loop_start := mark_jump();
            jumps := compile_condition(,, current_node = w.condition);
            if jumps.count == 0 then return; 
            compile_block(,, current_node = w.block);
            jump_to(loop_start);
            for jumps {
                end_jump(it);
            }
            reconcile_members(initial_members);
        }
        case; {
            error(tprint("Unhandled statement kind: %", node.kind));
            return;
        }
    }
}

rvalue :: (node: *Code_Node) -> bool, string, temporary: bool {
    if node.kind == {
        case .IDENT; {
            ident := node.(*Code_Ident);
            return true, ident.name, false;
        }
        case .UNARY_OPERATOR; {
            unary := node.(*Code_Unary_Operator);
            op : Operator_Type = xx unary.operator_type;
            if op == {
                case .POSTFIX_DEREFERENCE; #through;
                case .POINTER_DEREFERENCE; {
                    temp := push_temporary();
                    set_member_location(temp, slot_hl_indirect());
                    ok, name := rvalue(unary.subexpression);
                    if !ok then return false, "", false;
                    move_member(name, slot(.HL));
                    return true, temp, true;
                }
                case; {
                    error(tprint("Unsupported unary operator rvalue: %", operator_to_string2(xx unary.operator_type)));
                    return false, "", false;
                }
            }
        }
        case; 
            error(tprint("Unsupported rvalue: %", node.kind));
            return false, "", false;
    }
}

compile_expression :: (target_member: string) {
    node := context.current_node;
    log_verbose("Expression %", node.kind);
    if node.kind == {
        case .LITERAL; {
            lit := node.(*Code_Literal);
            if lit.value_type == {
                case .NUMBER; {
                    if lit.value_flags & .FLOAT { 
                        error("Floats aren't supported");
                        return;
                    }
                    type: GB_Type;
                    if lit._u64 <= 0xFF {
                        type = .U8;
                    } else if lit._u64 <= 0xFFFF {
                        type = .U16;
                    } else {
                        error("numbers larger than 2 bytes aren't supported"); 
                        return;
                    }

                    if get_member_type(target_member) == .NONE {
                        log_verbose("Typing member: % - %", target_member, type);
                        type_member(target_member, type);
                    }
                    reg := ensure_member_in_register(target_member);
                    if type == {
                        case .U8; {
                            load_imm8(reg, lit._u64.(u8));
                        }
                        case .U16; {
                            load_imm16(reg, lit._u64.(u16));
                        }
                        case; assert(false);

                    }
                    return;
                }
                case .BOOLEAN;{
                    if member_location(target_member).kind == .NONE {
                        type_member(target_member, .U8);
                    }
                    reg := ensure_member_in_register(target_member);
                    load_imm8(reg, lit._u64.(u8));
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
            right := push_temporary();
            defer pop_temporary(right);
            compile_expression(right,, current_node = bin_op.right);
            left := push_temporary();
            defer pop_temporary(left);
            compile_expression(left,, current_node = bin_op.left); 

            instr: Arithmetic_Instruction;
            if op == {
                case #char "+"; instr = .ADD;
                case #char "-"; instr = .SUB;
                case #char "&"; instr = .AND;
                case #char "|"; instr = .OR;
                case; { 
                    error(tprint("Unhandled binary operator expression '%'", operator_to_string2(op))); 
                    return;
                }
            }
            arithmetic_instruction(instr, left, right);
            if !is_wide(target_member) {
                set_member_location(target_member, slot(.A));
            } else {
                set_member_location(target_member, slot(.HL));
            }
        } 
        case .IDENT; {
            ident := node.(*Code_Ident);
            type_member(target_member, get_member_type(ident.name));
            l := ensure_member_in_register(target_member);
            r := ensure_member_in_register(ident.name);
            load_instruction(l, r);
        }
        case .PROCEDURE_CALL; {
            call := node.(*Code_Procedure_Call);
            if call.resolved_procedure_expression == null || call.resolved_procedure_expression.kind != .PROCEDURE_HEADER {
                error("The expression isn't a procedure header");
                return;
            }
            if call.num_return_values_received > 1 {
                error("Multiple return values aren't supported yet");
                return;
            }
            if call.num_return_values_received != 0 {
                if member_location(target_member) != slot(.A) { 
                    ensure_register_empty(.A);
                }
            }
            add_call(call.resolved_procedure_expression.(*Code_Procedure_Header));
            if call.num_return_values_received != 0 {
                set_member_location(target_member, slot(.A));
            }
        }
        case .CAST; {
            cst := node.(*Code_Cast);
            if (cst.cast_flags & ~(.IS_AUTO)) != 0 {
                error(tprint("Unhandled cast: %", cst.cast_flags));
                return;
            }
            if cst.cast_flags & .IS_AUTO {
                // Just use the type of the target_member
                compile_expression(target_member,, current_node = cst.expression);
                return;
            } else {
                cast_member(target_member, to_gb_type(cst.target_type.result));
                compile_expression(target_member,, current_node = cst.expression);
            }
        }
        case; {
            error(tprint("Unhandled expression kind: %", node.kind));
            return;
        }
    }
}

// Returns jumps addresses to be fixed up to the end
// of the if true
compile_condition :: () -> [..]int {
    node := context.current_node;
    jumps: [..]int;
    if node.kind == {
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;
            right := push_temporary();
            defer pop_temporary(right);

            compile_expression(right,, current_node = bin_op.right);
            if get_member_type(right) == {
                case .U8; #through;
                case .U16; { }
                case; {
                    error(tprint("Comparing % isn't supported yet", get_member_type(right)));
                    return jumps;
                }
            }

            left := push_temporary();
            defer pop_temporary(left);
            compile_expression(left,, current_node = bin_op.left); 
            r := ensure_member_in_register(right);
            l := ensure_member_in_register(left);

            if !is_wide(right) && !is_wide(left) {
                jump_kind: Jump_Kind;
                if op == {
                    case .IS_EQUAL; jump_kind =  .IF_NON_ZERO;
                    case .IS_NOT_EQUAL; jump_kind =  .IF_ZERO;
                    case #char "<"; jump_kind =  .IF_CARRY;
                    case; { 
                        error(tprint("Unhandled short binary operator comparison '%'", operator_to_string2(op))); 
                        return jumps;
                    }
                }
                arithmetic_instruction(.CP, left, right); 
                array_add(*jumps, begin_jump(jump_kind));
            } else { // One or both is wide
                lo_l, hi_l := split_register(member_location(left));
                lo_r, hi_r := split_register(member_location(right));
                if op == {
                    case .IS_EQUAL; {
                        if hi_l == .NONE || hi_r == .NONE {
                            // They are always non equal
                            array_add(*jumps, begin_jump(.ALWAYS));
                            return jumps;
                        }
                        arithmetic_instruction(.CP, lo_l, lo_r);
                        array_add(*jumps, begin_jump(.IF_NON_ZERO));
                        arithmetic_instruction(.CP, hi_l, hi_r);
                        array_add(*jumps, begin_jump(.IF_NON_ZERO));
                    } 
                    case .IS_NOT_EQUAL; {
                        if hi_l == .NONE || hi_r == .NONE {
                            // They are always non equal
                            return jumps;
                        }
                        arithmetic_instruction(.CP, lo_l, lo_r);
                        array_add(*jumps, begin_jump(.IF_ZERO));
                        arithmetic_instruction(.CP, hi_l, hi_r);
                        array_add(*jumps, begin_jump(.IF_ZERO));
                    }
                    case .LESS_OR_EQUAL; {
                        if hi_l == .NONE {
                            // Always below
                            return jumps;
                        }
                        arithmetic_instruction(.SUB, left, right);
                        array_add(*jumps, begin_jump(.IF_CARRY));
                        array_add(*jumps, begin_jump(.IF_NON_ZERO));
                    }
                    case; {
                        error(tprint("Unhandled wide binary operator comparison '%'", operator_to_string2(op))); 
                        return jumps;
                    }
                }
            }
            return jumps;

        }
        case .IDENT; #through;
        case .LITERAL; {
            temp := push_temporary();
            defer pop_temporary(temp);
            ensure_register_empty(.A);
            set_member_location(temp, .A);

            compile_expression(temp,, current_node = node);
            output_bytes(.CP_D8, 0x1);
            array_add(*jumps, begin_jump(.IF_NON_ZERO));
            return jumps;
        }
        case; {
            error(tprint("Unhandled condition expression kind: %", node.kind));
            return jumps;
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
    JR_Z_REL :: 0x28;
    LD_SP_IMM_16 :: 0x31;
    JR_C_REL :: 0x38;
    LD_A_IMM :: 0x3E;
    HALT :: 0x76;
    RET :: 0xC9;
    CALL :: 0xCD;
    DI :: 0xF3;
    EI :: 0xFB;
    RETI :: 0xD9;
    CP_D8 :: 0xFE;
}

load_instruction :: (dst_register: Register, src_register: Register) {
    if !is_wide(dst_register) && !is_wide(src_register) {
        dst := to_opcode(dst_register);
        src := to_opcode(src_register);
        assert(!(src == .HL_INDIRECT && dst == .HL_INDIRECT), "This is HALT");
        assert(dst <= .A);
        if dst == src then return;
        output_bytes(0x40 + (dst.(u8) * 8) + src.(u8));
    } else {
        lo_src, hi_src := split_register(src_register);
        lo_dst, hi_dst := split_register(dst_register);
        assert(lo_src != .NONE && lo_dst != .NONE, "One of the registers is None. src: % dst: %", lo_src, lo_dst);
        assert(hi_dst != .NONE, "Copying a wide register to a small one!");
        log_verbose("Copying from % to %", src_register, dst_register);
        load_instruction(lo_dst, lo_src);
        if hi_src != .NONE {
            load_instruction(hi_dst, hi_src);
        }
    }
}

load_imm8 :: (dst: Register, val: u8) {
    assert(!is_wide(dst), "Loading imm8 to wide register");
    tgt := to_opcode(dst);
    lo : u8 = 0x6 + ((tgt.(u8) % 2) * 0x8);
    hi : u8 = (tgt.(u8) / 2) << 4;
    output_bytes(lo | hi, val);
}

load_imm16 :: (dst: Register, val: u16) {
    assert(is_wide(dst), "Loading a u16 in an 8 bit register!");
    
    instr : u8;
    if dst == {
        case .BC; instr = 0x01;
        case .DE; instr = 0x01;
        case .HL; instr = 0x21;
        case; assert(false, "I don't know how to handle this: %", dst);
    }

    output_bytes(instr, (val & 0xFF).(u8), ((val >> 8) & 0xFF).(u8));
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

arithmetic_instruction :: (kind: Arithmetic_Instruction, left: string, right: string) {
    r_slot := member_location(right);
    assert(r_slot.kind == .REGISTER);
    l_slot := member_location(left);
    assert(l_slot.kind == .REGISTER);

    r_loc = r_slot.register;
    l_loc = l_slot.register;
    assert(!(kind == .CP && (is_wide(r_loc) || is_wide(l_loc))), "When outputting compares, please do it with small registers");
    if !is_wide(r_loc) && !is_wide(l_loc) {
        if kind == .SUB || (r_loc != .A && l_loc != .A) {
            move_member(left, slot(.A));
            l_loc = .A;
        }
        r_loc= member_location(right);
        arithmetic_instruction(kind, l_loc, r_loc);
    } else {
        ensure_register_empty(.HL);
        ensure_register_empty(.A);
        lo_l, hi_l := split_register(member_location(left));
        lo_r, hi_r := split_register(member_location(right));
        load_instruction(.A, lo_l);
        arithmetic_instruction(kind, .A, lo_r);
        load_instruction(.L, .A);
        other: Register;

        if hi_r != .NONE {
            other = hi_r;
        } else {
            ensure_register_empty(.B);
            other = .B;
            load_imm8(other, 0);
        }

        if hi_l != .NONE {
            load_instruction(.A, hi_l);
        } else {
            load_imm8(.A, 0);
        }

        if kind == .ADD {
            arithmetic_instruction(.ADC, .A, other);
        } else if kind == .SUB {
            arithmetic_instruction(.SBC, .A, other);
        } else {
            error(tprint("Unhandled wide arithmetic instruction: %", kind));
            return;
        }
        load_instruction(.H, .A);
    }
}

arithmetic_instruction :: (kind: Arithmetic_Instruction, left: Register, right: Register) {
    src := ifx left == .A then right else left;
    tgt := to_opcode(src);
    output_bytes(kind.(u8) + tgt.(u8));
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
}

Register :: enum_flags u8 {
    NONE:: 0;
    A :: 1;
    B :: 2;
    C :: 4;
    D :: 8;
    E :: 16;
    H :: 32;
    L :: 64;

    BC :: 2 | 4;
    DE :: 8 | 16;
    HL :: 32 | 64;
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

wide_register_preference :: Register.[
    .HL,
    .BC,
    .DE,
];

get_lo :: (r: Register) -> Register {
    return (r & .C) | (r & .E) | (r & .L);
}

get_hi :: (r: Register) -> Register {
    return (r & .B) | (r & .D) | (r & .H);
}

is_wide :: (r: Register) -> bool {
    return r == .BC || r == .DE || r == .HL;
}

split_register :: (r: Register) -> lo: Register, hi: Register {
    if !is_wide(r) return r, .NONE;
    return get_lo(r), get_hi(r);
}

to_opcode :: (r: Register) -> Operation_Target {
    assert(!is_wide(r), "R: %", r);
    if r & .A return .A;
    if r & .B return .B;
    if r & .C return .C;
    if r & .D return .D;
    if r & .E return .E;
    if r & .H return .H;
    if r & .L return .L;
    assert(false, "r: %", r);
    return 0;
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

unreachable :: () #expand {
    assert(false, "Unreachable");
    return;
}

log_verbose :: (format: string, args: ..Any) #expand {
    if context.log_level >= .VERBOSE {
        log(format, ..args, flags = .VERBOSE_ONLY);
    }
}

#load "../common/opcodes.jai";
#load "procedure.jai";
#load "member.jai";
#load "instrinsic.jai";

#import "Hash_Table";
