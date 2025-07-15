Member_Table :: Table(string, Member);

Member :: struct {
    type: GB_Type;
    hot: int;
}

GB_Type :: enum {
    NONE;
    U8;
    U16;
    POINTER;
}

member :: (type: GB_Type) -> Member {
    return .{ type, 0 };
}

cool_members :: () {
    using context.current_procedure;
    for *members {
        it.hot -= 1;
    }
}

warm :: (member: string) {
    using context.current_procedure;
    get_member(member).hot += 1;
}

push_member :: (name: string, ti: *Type_Info) {
    using context.current_procedure;
    if table_contains(*members, name) {
        error("Shadowing isn't supported yet");
        return;
    }
    if ti == null { 
        table_add(*members, name, member(.NONE));
    } else { 
        table_add(*members, name, member(to_gb_type(ti)));
    }
}

TEMP_IDENT :: "\\temp";
push_temporary :: () -> string {
    using context.current_procedure;
    name := tprint("%_%", TEMP_IDENT, formatInt(nb_temporaries, minimum_digits = 2));
    mem := member(.NONE);
    mem.hot = 999;
    table_add(*members, name, mem);
    nb_temporaries += 1;
    log_verbose("Adding temporary %", name);
    return name;
}

pop_member :: (name: string) {
    using context.current_procedure;
    ok := table_remove(*members, name); 
    for *slots {
        if it.member == name {
            it.member = "";
        }
    }
    assert(ok, "Member % couldn't be found", name);
}

pop_temporary :: (name: string) {
    using context.current_procedure;
    if !is_temporary(name) return; // Has merge with other member
    found := table_remove(*members, name); 
    assert(found);
    for *slots {
        if it.member == name {
            it.member = "";
        }
    }
    log_verbose("Popping temporary %", name);
    nb_temporaries -= 1;
}

is_temporary :: (name: string) -> bool {
    return begins_with(name, TEMP_IDENT);
}

get_member :: (name: string) -> *Member {
    member := table_find_pointer(*context.current_procedure.members, name);
    assert(member != null, "Couldn't find member '%'", name);
    return member;
}

// --------
// Types

to_gb_type :: (ti: *Type_Info) -> GB_Type {
    if ti == null {
        assert(false, "You gave me a null type");
        return .NONE;
    }
    if ti.type == {
        case .INTEGER; {
            if ti.runtime_size == {
                case 1; return .U8;
                case 2; return .U16;
                case; {
                    return .NONE; // It will have to be deduced
                }
            }
        }
        case .POINTER; {
            return .POINTER;
        }
        case .BOOL;{
            return .U8;
        }
        case; {
            error(tprint("Unhandled type: %", ti.*));
            return .NONE;
        }
    }
}

type_declaration :: (decl: *Code_Declaration) -> *Type_Info {
    if decl.type != null then return decl.type;
    if decl.type_inst != null then return decl.type_inst.result;
    if decl.expression != null then return decl.expression.type;
    assert(false, "Cannot type this declaration");
    return null;
}

to_size :: (t: GB_Type) -> Register_Size {
    if #complete t == {
        case .U8; return .BYTE;
        case .U16; #through;
        case .POINTER; return .SHORT;
        case .NONE; assert(false, "Cannot size a None type"); return .SHORT;
    }
}

is_wide :: (t: GB_Type) -> bool {
    return to_size(t) == .SHORT;
}

is_wide :: (name: string) -> bool {
    member := get_member(name);
    assert(member.type != .NONE);
    result : bool;
    if to_size(member.type) == {
        case .BYTE; result = false;
        case .SHORT; result = true;
    }
    // loc := member_location(name);
    // assert(loc == .NONE || is_wide(loc) == result, "This member - % - should not be here (it is % but is in %)! Did you change its type without moving it?", name, to_size(member.type), loc);
    return result;
}

can_we_handle_type :: (ti: *Type_Info) -> bool {
    if ti.type == {
        case .INTEGER; {
            if ti.runtime_size > 2 {
                error(tprint("The maximum size we can handle is 2 bytes. This is % bytes.", ti.runtime_size));
                return false;
            }

            return true;
        }
        case .POINTER; {
            return can_we_handle_type(ti.(*Type_Info_Pointer).pointer_to);
        }
        case; {
            error("Only integers are supported");
            return false;
        }
    }
    return true;

}

get_member_type :: (name: string) -> GB_Type {
    return get_member(name).type;
}

auto_deduce_type :: (a: GB_Type, b: GB_Type) -> GB_Type {
    if a == .U8 && b == .U16 then return .U16;
    if b == .U8 && a == .U16 then return .U16;
    assert(false, "Auto deduction not implemented: % - %", a, b);
    return .NONE;
}

type_member :: (name: string, type: GB_Type) {
    assert(type != .NONE, "Giving a % type to type a member", type);
    member := get_member(name);
    loc := member_location(name);

    if member.type != .NONE {
        assert(member.type == type, "Member is already typed differently: % (trying %)", member.type, type);
    } else {
        if loc != .NONE {
            assert(is_wide(loc) == is_wide(type), "Typing a member that is placed in a different sized register (type: %, register:%)", type, loc);
        }
        member.type = type;
    }
}

cast_member :: (name: string, type: GB_Type) {
    assert(type != .NONE);
    member := get_member(name);

    if member.type == .NONE {
        member.type = type;
        return;
    }
}

// ------
// Loc

set_member_location :: (name: string, register: Register) {
    using context.current_procedure;
    for *slots {
        if it.member == name {
            it.member = "";
        }
    }
    force_empty(register);
    if is_wide(register) {
        hi, lo := to_slot_wide(register);
        slots[hi].member = name;
        slots[hi].part = .HIGH;
        slots[lo].member = name;
        slots[lo].part = .LOW;

    } else {
        slot := to_slot(register);
        slots[slot].member = name;
        slots[slot].part = .FULL;
    }

}

member_location :: (name: string) -> Register {
    using context.current_procedure;
    full : Register;
    filled := 0;
    for slots {
        if is_empty(it) then continue;
        if it.member == name {
            assert(it_index != xx Slot.STACK_MAX, "Trying to operate on a member that is in an unexpected slot");
            assert(it_index <  xx Slot.STACK_00,  "Trying to operate on a member that is on the stack: %", it_index.(Slot));
            full |= to_register(xx it_index);
            if it.part == {
                case .FULL; filled |= 0b11; 
                case .LOW;  filled |= 0b01;
                case .HIGH; filled |= 0b10;
            }
            if filled == 0b11 then return full;
        }
    }
    return .NONE;
}

ensure_wide_members_in_bc_de :: (a: string, b: string) {
    using context.current_procedure;
    log_verbose("Ensure % and % in BC DE", a, b);
    if !is_empty(.BC) {
        push_bc();
    }
    if !is_empty(.DE) {
        push_de();
    }
    log_verbose("Move % to BC", a);
    move_member(a, .BC);
    log_verbose("Move % to DE", b);
    move_member(b, .DE);
}

move_member :: (name: string, new: Register) {
    log_verbose("Moving % to %", name, new);
    using context.current_procedure;
    if !is_wide(name) {
        log_verbose("small");
        hi, lo := split_register(new);
        ok, src := find_single(name);
        assert(ok);
        dst := to_slot(lo);
        if src == dst then return; // Nothing to do
        force_empty(lo);
        move(src, dst);
        if hi != .NONE {
            output_bytes(.XOR_A);
            load_instruction(hi, .A);
        }
    } else {
        assert(is_wide(new), "Moving from a wide to small register");
        hi_n, lo_n := split_wide_slot(new);
        ok, hi_m, lo_m := find_wide(name);
        if !ok {
            force_empty(new);
            set_member_location(name, new);
            return;
        }
        assert(ok, "% not found", name);
        if lo_n == lo_m && hi_n == hi_m then return; // Nothing to do;
        force_empty(new);
        move_wide(hi_m, lo_m, hi_n, lo_n);
    }
}

copy_member_to :: (name: string, new: Register) {
    log_verbose("Copying % to %", name, new);
    using context.current_procedure;
    if !is_wide(name) {
        assert(!is_wide(new));
        ok, src := find_single(name);
        assert(ok);
        dst := to_slot(new);
        if src == dst then return; // Nothing to do
        copy(src, dst);
    } else {
        assert(is_wide(new), "Moving from a wide to small register");
        hi_n, lo_n := split_wide_slot(new);
        ok, hi_m, lo_m := find_wide(name);
        if !ok {
            set_member_location(name, new);
            return;
        }
        assert(ok, "% not found", name);
        if lo_n == lo_m && hi_n == hi_m then return; // Nothing to do;
        copy_wide(hi_m, lo_m, hi_n, lo_n);
    }
}

ensure_member_in_register :: (name: string) -> Register {
    using context.current_procedure;
    log_verbose("Ensuring % is in register", name);
    member := get_member(name);
    size := to_size(member.type);
    if !is_wide(name) {
        found, from := find_single(name);
        if !found { // Member not placed yet
            spill_coldest();
            to := alloc_register(); // Guaranteed to succeed
            slots[to].member = name;
            slots[to].part = .FULL;
            return to_register(to);
        }

        if is_register(from) {
            return to_register(from);
        } else {
            spill_coldest();
            to := alloc_register(); // Guaranteed to succeed
            move(from, to);
            return to_register(to);
        }
    } else {
        ok, hi, lo := find_wide(name);
        if !ok {
            hi, lo := alloc_wide_register();
            log_verbose("Allocating wide: % %", hi, lo);
            slots[hi].member = name;
            slots[lo].member = name;
            slots[hi].part = .HIGH;
            slots[lo].part = .LOW;
            return to_register(hi, lo);
        } else {
            if is_register(hi) && is_register(lo) {
                return to_register(hi, lo);
            } else {
                spill_coldest_wide();
                to_hi, to_lo := alloc_wide_register(); // Guaranteed to succeed
                move_wide(hi, lo, to_hi, to_lo);
                return to_register(to_hi, to_lo);
            }
        }
    }
}

print_members :: () {
    builder: String_Builder;
    for context.current_procedure.members {
        print_to_builder(*builder, "%: %, ", it_index, it);
    }
    log_verbose("{ % }", builder_to_string(*builder));
}

get_constant_address :: (name: string) -> u16 {
    for context.constants {
        if it.name == name {
            return it.address;
        }
    }
    assert(false, "Constant % not found", name);
    return 0;
}
