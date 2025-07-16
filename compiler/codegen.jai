#add_context current_procedure: *Compiled_Procedure;
#add_context current_node: *Code_Node;
#add_context constants: []Constant;

Constant :: struct {
    name : string;
    address : u16;
    value : []u8;
}

build_cart :: (file: string) -> MBC1 {
    log_verbose("%", file);
    set_build_options_dc(.{do_output = false});
    w := compiler_create_workspace();
    
    options := get_build_options();
    options.output_type = .NO_OUTPUT;
    options.runtime_support_definitions = .OMIT;

    procedures : [..] *Code_Procedure_Header;
    constants : [..] Constant;

    set_build_options(options, w);
    compiler_begin_intercept(w);
    add_build_file(file, w);

    while true {
        msg := compiler_wait_for_message();
        if !msg continue;
        if msg.kind == .TYPECHECKED {
            tc := cast(*Message_Typechecked) msg;
            if !gather(tc, *procedures, *constants) then return .{};
        }

        if msg.kind == .COMPLETE {
            com := msg.(*Message_Complete);
            if com.error_code != 0 {
                return .{};
            } else {
                break;
            }
        }

    }
    compiler_end_intercept(w);
    ok, cart := generate_assembly(constants, procedures);
    assert(ok);
    return cart;
}

gather :: (msg: *Message_Typechecked, procedures: *[..]*Code_Procedure_Header, constants: *[..] Constant) -> bool {
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
                if !(decl.flags & .IS_CONSTANT) {
                    fatal(tprint("Non constant top level declaration: % (%)", decl.name, decl.*));
                    return false;
                }

                if decl.expression.kind == {
                    case .PROCEDURE_HEADER; {
                        proc_header := cast(*Code_Procedure_Header) decl.expression;
                        if proc_header.procedure_flags & .ELSEWHERE then continue;
                        if proc_header.procedure_flags & .COMPILE_TIME_ONLY then continue;
                        array_add(procedures, proc_header);
                    }
                    case .LITERAL; {
                        lit := decl.expression.(*Code_Literal);
                        if lit.value_type == {
                            case .ARRAY; {
                                values := lit.array_literal_info;
                                data := NewArray(values.array_members.count, u8);
                                for values.array_members {
                                    assert(it.kind == .LITERAL);
                                    value_literal := it.(*Code_Literal);
                                    assert(value_literal.value_type == .NUMBER);
                                    data[it_index] = xx value_literal._u64;
                                }
                                log_verbose(tprint("Added constant %", decl.name));
                                array_add(constants, .{ decl.name, 0, data });

                            }
                            case; {
                                fatal(tprint("Unhandled constant literal: %", lit.value_type));
                                return false;

                            }

                        }
                    }
                    case; {
                        fatal(tprint("Unhandled top level declaration: %", decl.expression.kind));
                        return false;
                    }
                }
            }
            case; {
                // log("Ignored: %", expr.kind);
                // We don't care about the rest. yet!
            }
        }
    }
    return true;
}

generate_assembly :: (constants: [..] Constant, procedures: [..]*Code_Procedure_Header) -> bool, MBC1 {
    compiled : [..]Compiled_Procedure;
    errored := false;

    // Place constants
    base_constant_address : u16 = 0x4000;
    for *constants {
        it.address = base_constant_address;
        base_constant_address += it.value.count.(u16);
    }
    if base_constant_address > 0x7FFF {
        log_error("Too many constants!");
        return false, .{};
    }

    context.constants = constants;

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

    cart := output_rom(compiled, constants);
    return true, cart;
}

output_rom :: (compiled: []Compiled_Procedure, constants: [] Constant) -> MBC1 {
    builder: String_Builder;
    cart := New(MBC1,, temp);

    cart.header.entry_point = .[0xc3, 0x50, 0x1, 0x0];
    for compiled {
        assert(it.base_address != 0, "Procedure \"%\" wasn't placed in program!", it.procedure_header.name);
        i := it.base_address;
        memcpy(cart.contents.data + i, it.bytes.data, it.bytes.count);
    }
    for constants {
        memcpy(cart.contents.data + it.address, it.value.data, it.value.count);
    }

    return cart;
}

disassemble_procedure :: (builder: *String_Builder, proc: Compiled_Procedure) {
    disassemble_bytes(builder, proc.bytes, true, proc.base_address);
}

generate_procedure :: (proc: *Code_Procedure_Header) -> Compiled_Procedure {
    log_verbose("==== Compiling %", proc.name);
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
        t := type_declaration(it.(*Code_Declaration));
        push_member(it.name, t);
    }

    stack_size := context.current_procedure.stack_size;

    if block.block_type != .IMPERATIVE {
        error(tprint("Unhandled block type: %", block.block_type));
        return;
    }

    for block.statements {
        compile_statement(,, current_node = it);
        cool_members();
        if context.current_procedure.errors.count > 0 then break;
    }

    for block.members {
        pop_member(it.name);
    }

    // Clear stack
    new_stack_size := context.current_procedure.stack_size;
    diff := new_stack_size - stack_size;
    log_verbose("Stack size ! % vs %", new_stack_size, stack_size);
    if diff != 0 {
        output_bytes(.ADD_SP_S8, cast,no_check(u8)diff);
    }
    context.current_procedure.stack_size = stack_size;
}

compile_statement :: () {
    node := context.current_node;
    log_verbose("Statement %", node.kind);
    if node.kind == {
        case .DECLARATION; {
            decl := cast(*Code_Declaration)node;
            type := type_declaration(decl);
            t := to_gb_type(type);
            if t != .NONE {
                type_member(decl.name, t);
            } 
            if decl.expression != null {
                name := decl.name;
                compile_expression(*name,, current_node = decl.expression);
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
            initial_members := copy_slots(,, temp);

            log_verbose("Compiling then block...");
            compile_block(,, current_node = code.then_block);
            then_members := copy_slots(,, temp);

            else_jump : int = -1;  
            if code.else_block != null {
                skip_else := begin_jump(.ALWAYS);
                for jumps {
                    end_jump(it);
                }
                log_verbose("Compiling else block...");
                compile_block(,, current_node = code.else_block);
                reconcile_slots(then_members);
                end_jump(skip_else);
            } else {
                reconcile_slots(initial_members);
                for jumps {
                    end_jump(it);
                }
            }

        }
        case .BINARY_OPERATOR; {
            bin_op := node.(*Code_Binary_Operator);
            op : Operator_Type = xx bin_op.operator_type;
            ok, left, pointer_to := rvalue(bin_op.left);
            if !ok then return;
            defer {
                if pointer_to != "" {
                    move_member(pointer_to, .HL);
                    load_instruction(.HL_INDIRECT, to_opcode(member_location(left)));
                    pop_temporary(left);
                }
            }

            if op == {
                case #char "="; {
                    compile_expression(*left,, current_node = bin_op.right);
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
                    compile_expression(*temp,, current_node = bin_op.right);

                    arithmetic_instruction(get_instruction(op), left, temp);
                    set_member_location(left, .A);
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
                force_empty(.A);
                temp := push_temporary();
                defer pop_temporary(temp);
                set_member_location(temp, .A);
                compile_expression(*temp,, current_node = ret.arguments_sorted[0]);
                move_member(temp, .A);
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
            initial_members := copy_slots(,, temp);
            loop_start := mark_jump();
            jumps := compile_condition(,, current_node = w.condition);
            if jumps.count == 0 then return; 
            compile_block(,, current_node = w.block);
            reconcile_slots(initial_members);
            jump_to(loop_start);
            for jumps {
                end_jump(it);
            }
        }
        case; {
            error(tprint("Unhandled statement kind: %", node.kind));
            return;
        }
    }
}

rvalue :: (node: *Code_Node) -> ok: bool, member: string, pointer_to: string {
    using context.current_procedure;
    if node.kind == {
        case .IDENT; {
            ident := node.(*Code_Ident);
            return true, ident.name, pointer_to = "";
        }
        case .UNARY_OPERATOR; {
            unary := node.(*Code_Unary_Operator);
            op : Operator_Type = xx unary.operator_type;
            if op == {
                case .POSTFIX_DEREFERENCE; #through;
                case .POINTER_DEREFERENCE; {
                    ok, name := rvalue(unary.subexpression);
                    if !ok then return false, "", pointer_to = "";
                    move_member(name, .HL);

                    temp := push_temporary();
                    slot := alloc_register();
                    slots[slot].member = temp;
                    slots[slot].part = .FULL;
                    load_instruction(to_opcode(to_register(slot)), .HL_INDIRECT);

                    return true, temp, pointer_to = name;
                }
                case; {
                    error(tprint("Unsupported unary operator rvalue: %", operator_to_string2(xx unary.operator_type)));
                    return false, "", pointer_to = "";
                }
            }
        }
        case; 
            error(tprint("Unsupported rvalue: %", node.kind));
            return false, "", pointer_to = "";
    }
}

compile_expression :: (target_member: *string) {
    node := context.current_node;
    log_verbose("Expression %", node.kind);
    cool_members();
    warm(target_member.*);
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

                    if get_member_type(target_member.*) == .NONE {
                        log_verbose("Typing member: % - %", target_member, type);
                        type_member(target_member.*, type);
                    }
                    reg := ensure_member_in_register(target_member.*);
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
                    if get_member_type(target_member.*) == .NONE {
                        type_member(target_member.*, .U8);
                    }
                    reg := ensure_member_in_register(target_member.*);
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

            instr: Arithmetic_Instruction;
            if op == {
                case #char "."; {
                    assert(bin_op.right.kind == .IDENT);
                    assert(bin_op.left.kind == .IDENT);
                    dot_operator(target_member.*, bin_op.left.(*Code_Ident), bin_op.right.(*Code_Ident));
                    return;
                }
                case .ARRAY_SUBSCRIPT; {
                    assert(bin_op.right.kind == .IDENT);
                    assert(bin_op.left.kind == .IDENT);

                    force_empty(.HL);
                    ident := bin_op.left.(*Code_Ident);
                    assert((ident.resolved_declaration.flags & .IS_CONSTANT) != 0, "Array subscript isn't constant: %", ident.resolved_declaration.*);
                    load_imm16(.HL, get_constant_address(ident.name));
                    force_empty(.BC);
                    move_member(bin_op.right.(*Code_Ident).name, .BC);
                    output_bytes(.ADD_HL_BC);

                    type_member(target_member.*, .U8);
                    reg := ensure_member_in_register(target_member.*);
                    load_instruction(to_opcode(reg), .HL_INDIRECT);
                    return;
                }
                case #char "+"; instr = .ADD;
                case #char "-"; instr = .SUB;
                case #char "&"; instr = .AND;
                case #char "|"; instr = .OR;
                case; { 
                    error(tprint("Unhandled binary operator expression '%'", operator_to_string2(op))); 
                    return;
                }
            }

            right := push_temporary();
            defer pop_temporary(right);
            compile_expression(*right,, current_node = bin_op.right);
            left := push_temporary();
            defer pop_temporary(left);
            compile_expression(*left,, current_node = bin_op.left); 


            if (is_wide(left) || is_wide(right)) && instr == .SUB {
                error(tprint("Unhandled wide binary operator expression '%'", operator_to_string2(op)));
                return;

            }
            arithmetic_instruction(instr, left, right);
            if get_member_type(target_member.*) == .NONE {
                lt := get_member_type(left);
                rt := get_member_type(right);
                if lt == rt {
                    type_member(target_member.*, lt);
                } else {
                    type_member(target_member.*, auto_deduce_type(lt, rt));
                }
            }
            if !is_wide(target_member.*) {
                set_member_location(target_member.*, .A);
            } else {
                set_member_location(target_member.*, .HL);
            }
        } 
        case .IDENT; {
            ident := node.(*Code_Ident);
            if is_temporary(target_member.*) {
                log_verbose(tprint("Removing temporary %, because it maps to ident %", target_member.*, ident.name));
                pop_temporary(target_member.*);
                target_member.* = ident.name;
            } else {
                type_member(target_member.*, get_member_type(ident.name));
                l := ensure_member_in_register(target_member.*);
                copy_member_to(ident.name, l);
            }
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
                if member_location(target_member.*) != .A { 
                    force_empty(.A);
                }
            }
            add_call(call.resolved_procedure_expression.(*Code_Procedure_Header));
            if call.num_return_values_received != 0 {
                set_member_location(target_member.*, .A);
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
                cast_member(target_member.*, to_gb_type(cst.target_type.result));
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

            compile_expression(*right,, current_node = bin_op.right);
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
            compile_expression(*left,, current_node = bin_op.left); 
            r := ensure_member_in_register(right);
            l := ensure_member_in_register(left);

            if !is_wide(right) && !is_wide(left) {
                arithmetic_instruction(.CP, left, right); 
                if op == {
                    case .IS_EQUAL; array_add(*jumps, begin_jump(.IF_NON_ZERO));
                    case .IS_NOT_EQUAL; array_add(*jumps, begin_jump(.IF_ZERO));
                    case #char "<"; array_add(*jumps, begin_jump(.IF_NON_CARRY));
                    case .LESS_OR_EQUAL; array_add(*jumps, begin_jump(.IF_CARRY), begin_jump(.IF_NON_ZERO));
                    case; { 
                        error(tprint("Unhandled short binary operator comparison '%'", operator_to_string2(op))); 
                        return jumps;
                    }
                }
            } else { // One or both is wide
                hi_l, lo_l := split_register(l);
                hi_r, lo_r := split_register(r);
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
                    // @TODO
                    // case .LESS_OR_EQUAL; {
                    //     if hi_l == .NONE {
                    //         // Always below
                    //         return jumps;
                    //     }
                    //     force_empty(.A);
                    //     load_instruction(.A, lo_l);
                    //     arithmetic_instruction(.SUB, .A, lo_r);
                    //     array_add(*jumps, begin_jump(.IF_NON_CARRY));
                    //     load_instruction(.A, hi_l);
                    //     arithmetic_instruction(.SBC, .A, hi_r);
                    //     array_add(*jumps, begin_jump(.IF_NON_ZERO));
                    // }
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
            set_member_location(temp, .A);

            compile_expression(*temp,, current_node = node);
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


load_instruction :: (dst_register: Register, src_register: Register) {
    if !is_wide(dst_register) && !is_wide(src_register) {
        dst := to_opcode(dst_register);
        src := to_opcode(src_register);
        assert(!(src == .HL_INDIRECT && dst == .HL_INDIRECT), "This is HALT");
        assert(dst <= .A);
        if dst == src then return;
        load_instruction(dst, src);
    } else {
        hi_src, lo_src:= split_register(src_register);
        hi_dst, lo_dst:= split_register(dst_register);
        assert(lo_src != .NONE && lo_dst != .NONE, "One of the registers is None. src: % dst: %", lo_src, lo_dst);
        assert(hi_dst != .NONE, "Copying a wide register to a small one!");
        log_verbose("Copying from % to %", src_register, dst_register);
        load_instruction(lo_dst, lo_src);
        if hi_src != .NONE {
            load_instruction(hi_dst, hi_src);
        }
    }
}

load_instruction :: inline (dst: Operation_Target, src: Operation_Target) {
    output_bytes(0x40 + (dst.(u8) * 8) + src.(u8));
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
        case .DE; instr = 0x11;
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
    r_loc := member_location(right);
    l_loc := member_location(left);

    assert(!(kind == .CP && (is_wide(r_loc) || is_wide(l_loc))), "When outputting compares, please do it with small registers");
    if !is_wide(r_loc) && !is_wide(l_loc) {
        if kind == .SUB || (r_loc != .A && l_loc != .A) {
            move_member(left, .A);
            l_loc = .A;
        }
        r_loc = member_location(right);
        arithmetic_instruction(kind, l_loc, r_loc);
    } else {
        log_verbose("Wide arithmetic % > %", member_location(left), member_location(right));
        force_empty(.HL);
        force_empty(.A);
        if is_wide(left) && is_wide(right) {
            ensure_wide_members_in_bc_de(left, right);
        }
        hi_l, lo_l := split_register(member_location(left));
        hi_r, lo_r := split_register(member_location(right));
        log_verbose("Arith low part");
        load_instruction(.A, lo_l);
        arithmetic_instruction(kind, .A, lo_r);
        load_instruction(Register.L, Register.A);
        other: Register;

        log_verbose("Arith hi part");
        if hi_r != .NONE {
            other = hi_r;
        } else {
            log_verbose("Load imm");
            other = to_register(alloc_register_skip_a());
            load_imm8(other, 0);
        }

        if hi_l != .NONE {
            log_verbose("Load hi_l");
            load_instruction(.A, hi_l);
        } else {
            log_verbose("Load 0");
            load_imm8(.A, 0);
        }

        if kind == .ADD {
            arithmetic_instruction(.ADC, .A, other);
        } else if kind == .SUB {
            arithmetic_instruction(.SBC, .A, other);
        } else if kind == .OR {
            arithmetic_instruction(.OR, .A, other);
        } else {
            error(tprint("Unhandled wide arithmetic instruction: %", kind));
            return;
        }
        load_instruction(Register.H, Register.A);
    }
}

dot_operator :: (target_member: string, left: *Code_Ident, right: *Code_Ident) {
    ti := left.resolved_declaration.type;
    if ti.type == {
        case .ARRAY; {
            ti_arr := ti.(*Type_Info_Array);
            if right.name == {
                case "count"; {
                    if ti_arr.array_count > -1 {
                        if ti_arr.array_count > 0xFF {
                            error("Wide arrays aren't supported yet");
                            return;
                        }
                        type_member(target_member, .U8);
                        reg := ensure_member_in_register(target_member);
                        load_imm8(reg, xx ti_arr.array_count);
                        return;
                    } else {
                        error(tprint("Runtime arrays aren't supported yet"));
                        return;
                    }
                }
                case; error(tprint("Unhandled member % in array", right.name)); return;
            }
        }
        case; {
            error(tprint("Unhandled type with dot operator: %", ti.type));
            return;

        }
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

split_register :: (r: Register) -> hi: Register, lo: Register {
    if !is_wide(r) return .NONE, r;
    return get_hi(r), get_lo(r);
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
    assert(false, "Trying to opcode the % register", r);
    return 0;
}

Instruction_Kind :: enum u8 {
    NOP :: 0x0;
    ADD_HL_BC :: 0x09;
    JR_REL :: 0x18;
    ADD_HL_DE :: 0x19;
    JR_NZ_REL :: 0x20;
    JR_Z_REL :: 0x28;
    JR_NC_REL :: 0x30;
    LD_SP_IMM_16 :: 0x31;
    JR_C_REL :: 0x38;
    LD_A_IMM :: 0x3E;
    HALT :: 0x76;
    XOR_A :: 0xAF;
    PUSH_BC :: 0xC5;
    RET :: 0xC9;
    CALL :: 0xCD;
    PUSH_DE :: 0xD5;
    RETI :: 0xD9;
    ADD_SP_S8 :: 0xE8;
    PUSH_HL :: 0xE5;
    DI :: 0xF3;
    PUSH_AF :: 0xF5;
    LD_HL_SP_PLUS_S8 :: 0xF8;
    EI :: 0xFB;
    CP_D8 :: 0xFE;
    POP_HL :: 0xE1;
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
#load "register_alloc.jai";

#import "Hash_Table";
#import "Math";
#import "String";
