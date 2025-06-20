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
    table_add(*members, name, member(to_gb_type(ti)));
}

push_temporary :: () -> string {
    using context.current_procedure;
    name := tprint("temp_%", formatInt(nb_temporaries, minimum_digits = 2));
    table_add(*members, name, member(.NONE));
    nb_temporaries += 1;
    log_verbose("Adding temporary %", name);
    return name;
}

pop_member :: (name: string) {
    using context.current_procedure;
    ok := table_remove(*members, name); 
    assert(ok, "Member % couldn't be found", name);
}

pop_temporary :: (name: string) {
    using context.current_procedure;
    ok := table_remove(*members, name); 
    assert(ok, "Member % couldn't be found", name);
    log_verbose("Popping temporary %", name);
    nb_temporaries -= 1;
}

get_member :: (name: string) -> *Member {
    member := table_find_pointer(*context.current_procedure.members, name);
    assert(member != null, "Couldn't find member %", name);
    return member;
}

// --------
// Types

to_gb_type :: (ti: *Type_Info) -> GB_Type {
    if ti == null then return .NONE;
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

to_size :: (t: GB_Type) -> Register_Size {
    if #complete t == {
        case .U8; return .BYTE;
        case .U16; #through;
        case .POINTER; return .SHORT;
        case .NONE; assert(false); return .SHORT;
    }
}

is_wide :: (name: string) -> bool {
    return to_size(get_member(name).type) == .SHORT;
}

is_wide :: (member: Member) -> bool {
    return to_size(member.type) == .SHORT;
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

type_member :: (name: string, type: GB_Type) {
    assert(type != .NONE, "Giving a % type to type a member", type);
    member := get_member(name);

    if member.type != .NONE {
        assert(member.type == type, "Member is already typed differently: % (trying %)", member.type, type);
    } else {
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
    force_empty(register);
    if is_wide(register) {
        hi, lo := to_slot_wide(register);
        slots[hi].empty = false;
        slots[hi].member = name;
        slots[hi].part = .HIGH;
        slots[lo].empty = false;
        slots[lo].member = name;
        slots[lo].part = .LOW;

    } else {
        slot := to_slot(register);
        slots[slot].empty = false;
        slots[slot].member = name;
        slots[slot].part = .FULL;
    }

}

member_location :: (name: string) -> Register {
    using context.current_procedure;
    full : Register;
    filled := 0;
    for slots {
        if it.empty then continue;
        if it.member == name {
            assert(it_index >= xx Slot.STACK_00, "Trying to operate on a member that is on the stack");
            full |= to_register(xx it_index);
            if it.part == {
                case .FULL; filled |= 0b11;
                case .LOW; filled |= 0b01;
                case .HIGH; filled |= 0b11;
            }
            if filled == 0b11 then return full;
        }
    }
    assert(false);
    return .NONE;
}

// ensure_slot_empty :: (s: Member_Slot) {
//     using context.current_procedure;
//     assert(s.kind != .NONE);
//     for *members {
//         if overlapping(it.slot, s) {
//             move_member_to_next_available_slot(it_index);
//         }
//     }
// }
//
// ensure_register_empty :: (r: Register) {
//     using context.current_procedure;
//     assert(r != .NONE);
//     for *members {
//         if it.slot.kind != .REGISTER then continue;
//         if it.slot.register & r == 0 then continue;
//         new : Register;
//         if !is_wide(it) {
//             ok:, new = find_next_available_register(.BYTE);
//         } else {
//             ok:, new = find_next_available_wide(.SHORT);
//         }
//         log_verbose("Making sure % is empty by moving %", r, it_index);
//         load_instruction(new, r);
//         it.slot = new;
//         if !is_wide(r) then return;
//     }
// }

move_member :: (name: string, new: Register) {
    using context.current_procedure;
    if !is_wide(name) {
        assert(!is_wide(new));
        src := find_single(name);
        dst := to_slot(new);
        if src == dst then return; // Nothing to do
        force_empty(new);
        move(src, dst);
    } else {
        assert(is_wide(new));
        lo_n, hi_n := split_wide_slot(new);
        hi_m, lo_m := find_wide(name);
        if lo_n == lo_m && hi_n == hi_m then return; // Nothing to do;
        force_empty(new);
        move_wide(hi_m, lo_m, hi_n, lo_n);
    }
}

ensure_member_in_register :: (name: string) -> Register {
    member := get_member(name);
    size := to_size(member.type);
    if !is_wide(member) {
        from := find_single(name);
        if is_register(from) {
            return to_register(from);
        } else {
            spill_coldest();
            to := alloc_register(); // Guaranteed to succeed
            move(from, to);
            return to_register(to);
        }
    } else {
        hi, lo := find_wide(name);
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
//
// move_member_to_next_available_slot :: (name: string) {
//     using context.current_procedure;
//     member := get_member(name);
//     new_slot : Member_Slot;
//     if member.type == {
//         case .NONE; assert(false, "I don't know how to place a non typed member");
//         case .U8; {
//             ok:, new_slot = find_next_available(.BYTE);
//             assert(ok, "Too many members");
//         } 
//         case .POINTER; #through;
//         case .U16; {
//             ok:, new_slot = find_next_available(.SHORT);
//             assert(ok, "Too many members");
//         }
//         case; assert(false, "Todo (type %)", member.type);
//     }
//     move_member(name, slot);
// }

// get_member_at :: (r: Register) -> bool, string {
//     using context.current_procedure;
//     for members {
//         if it.slot.kind != .REGISTER then continue;
//         if it.slot.register == r then return true, it_index;
//     }
//     s : string = ---;
//     return true, s;
// }

print_members :: () {
    builder: String_Builder;
    for context.current_procedure.members {
        print_to_builder(*builder, "%: %, ", it_index, it);
    }
    log_verbose("{ % }", builder_to_string(*builder));
}

