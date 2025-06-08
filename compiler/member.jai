Member_Table :: Table(string, Member);

Member :: struct {
    slot: Register;
    type: GB_Type;
}

GB_Type :: enum {
    NONE;
    U8;
    U16;
    POINTER;
}

member :: (type: GB_Type) -> Member {
    return .{ .NONE, type };
}

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

get_member_type :: (name: string) -> GB_Type {
    return get_member(name).type;
}

set_member_location :: (name: string, slot: Register) {
    assert(slot != .NONE);
    ensure_register_empty(slot);
    member := get_member(name);
    member.slot = slot;
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

copy_members :: () -> Member_Table {
    using context.current_procedure;
    result: Member_Table;

    for members {
        table_add(*result, it_index, it);
    }
    return result;
}

reconcile_members :: (original: Member_Table) {
    using context.current_procedure;
    for *members {
        ok, initial := table_find_new(*original, it_index);
        assert(ok);
        if it.slot != initial.slot {
            ensure_register_empty(initial.slot);
            log_verbose("Reconciling % (% to %)", it_index, it.slot, initial.slot);
            load_instruction(initial.slot, it.slot);
            it.slot = initial.slot;
        }
    }
    assert(check_members(members), "Reconciliation asked, but not complete!");
}

check_members :: (original: Member_Table) -> bool {
    using context.current_procedure;
    for members {
        ok, initial := table_find_new(*original, it_index);
        assert(ok);
        if it.slot != initial.slot then return false;
    }
    return true;
}

// If member is not place, will be placed
member_location :: (name: string) -> Register {
    using context.current_procedure;
    ok, member := table_find_new(*members, name);
    assert(ok, "Member % couldn't be found", name);
    return member.slot;
}

ensure_register_empty :: (r: Register) {
    using context.current_procedure;
    assert(r != .NONE);
    for *members {
        if it.slot == r {
            ok, new := find_next_available_register();
            log_verbose("Making sure % is empty by moving %", r, it_index);
            load_instruction(new, r);
            it.slot = new;
            return;
        }
    }
}

move_member :: (name: string, new_slot: Register) {
    using context.current_procedure;
    assert(new_slot != .NONE);
    member := get_member(name);
    if member.slot == new_slot then return; // Nothing to do
    ensure_register_empty(new_slot);
    log_verbose("Moving % to % (was in %)", name, new_slot, member.slot);
    if member.slot != .NONE {
        load_instruction(new_slot, member.slot);
    }
    member.slot = new_slot;
}

ensure_member_placed :: (name: string) {
    if get_member(name).slot != 0 then return;
    move_member_to_next_available_slot(name);
}

move_member_to_next_available_slot :: (name: string) {
    using context.current_procedure;
    member := get_member(name);
    if member.type == {
        case .NONE; {
            assert(false, "I don't know how to place a non typed member");
        }
        case .U8; {
            ok, slot := find_next_available_register();
            assert(ok, "Too many members");
            log_verbose("Moving % to % (was in %)", name, slot, member.slot);
            if member.slot != .NONE {
                load_instruction(slot, member.slot);
            }
            member.slot = slot;
        } 
        case .POINTER; #through;
        case .U16; {
            ok, slot := find_next_available_wide();
            assert(ok, "Too many members");
            log_verbose("Moving % to % (was in %)", name, slot, member.slot);
            if member.slot != .NONE {
                load_instruction(slot, member.slot);
            }
            member.slot = slot;
        }
        case; {
            assert(false, "Todo (type %)", member.type);
        }
    }
}

get_member_at :: (r: Register) -> bool, string {
    using context.current_procedure;
    for members {
        if it.slot == r then return true, it_index;
    }
    s : string = ---;
    return true, s;
}

print_members :: () {
    builder: String_Builder;
    for context.current_procedure.members {
        print_to_builder(*builder, "%: %, ", it_index, it);
    }
    log_verbose("{ % }", builder_to_string(*builder));
}

find_next_available_register :: () -> bool, Register {
    using context.current_procedure;
    for r: register_preference {
        for members {
            if it.slot == xx r then continue r;
        }

        return true, xx r;
    }
    assert(false, "Unable to find a free spot for member");
    return false, 0;
}

find_next_available_wide :: () -> bool, Register {
    using context.current_procedure;
    for r: wide_register_preference {
        for members {
            if (it.slot & r) == 1 then continue r;
        }
        return true, r;
    }
    assert(false, "Unable to find a free sport for member");
    return false, 0;
}
