Compile_Error :: struct {
    message: string;
    location: Code_Node.Location;
}

Compiled_Procedure :: struct {
    procedure_header: *Code_Procedure_Header;

    base_address : u16;
    bytes: [..]u8;
    members: Table(string, Register);
    nb_temporaries := 0;
    return_added : bool;

    external_calls: [..] Call;

    errors: [..]Compile_Error;
}

Call :: struct {
    instr: u16;
    procedure: *Code_Procedure_Header;
}

output_bytes :: (bytes: ..u8, loc := #caller_location) {
    output_bytes(bytes, loc); 
}

output_bytes :: (instr: Instruction_Kind, bytes : ..u8, loc := #caller_location) {
    all : [..]u8;
    all.allocator = temp;
    array_add(*all, xx instr);
    array_add(*all, ..bytes);
    output_bytes(all, loc);
}

output_bytes :: (bytes: []u8, loc := #caller_location) {
    array_add(*context.current_procedure.bytes, ..bytes);
    builder: String_Builder;
    disassemble_bytes(*builder, bytes, false);
    log_verbose("%", builder_to_string(*builder));
}

disassemble_bytes :: (builder: *String_Builder, bytes: []u8, new_line : bool, base_address : u16 = 0x00) {
    i := 0;
    while i < bytes.count {
        inner : String_Builder;
        op := OPCODE_DESC_TABLE[bytes[i]];
        
        // Addr
        print_to_builder(*inner, "0x% ", formatInt(base_address + i, 16, 4));

        // Bytes
        print_to_builder(*inner, "% ", formatInt(bytes[i], 16, 2));
        if (i + (op.bytes-1)) > bytes.count - 1 {
            assert(false, "Malformed instruction: % (%)", formatInt(bytes[i], 16), op.desc);
            return;
        }
        for 1..op.bytes - 1 {
            print_to_builder(*inner, "% ", formatInt(bytes[i + it], 16, 2));
        }
        while builder_string_length(*inner) < 16 {
            append(*inner, " ");
        }

        // Desc
        print_to_builder(*inner, "%", op.desc);
        while builder_string_length(*inner) < 28 {
            append(*inner, " ");
        }

        // Operands
        i2 := op.bytes - 1;
        while (i2 >= 1) {
            print_to_builder(*inner, "%", formatInt(bytes[i + i2], 16, 2));
            i2 -= 1;
        }

        if new_line {
            append(*inner, "\n");
        }

        append(builder, "\t");
        append(builder, builder_to_string(*inner));

        i += op.bytes;
    }
}

Jump_Kind :: enum {
    IF_FALSE;
    IF_TRUE;
    ALWAYS;

    NONE;
}

begin_jump :: (kind: Jump_Kind) -> int {
    using context.current_procedure;
    addr := bytes.count;
    if #complete kind == {
        case .IF_FALSE; output_bytes(.JR_NZ_REL, 0x00);
        case .IF_TRUE; output_bytes(.JR_Z_REL, 0x00);
        case .ALWAYS; output_bytes(.JR_REL, 0x00);
        case .NONE; assert(false, "Invalid jump");
    };
    return addr;
}

end_jump :: (jump_addr: int) {
    using context.current_procedure;
    current_addr := bytes.count;
    end_of_jump := jump_addr + 2;
    distance := current_addr - end_of_jump;
    assert(distance <= 127, "Long jumps arent supported yet");
    bytes[jump_addr + 1] = cast,no_check(u8)(distance.(s8));
}

add_call :: (proc: *Code_Procedure_Header) {
    using context.current_procedure;
    c := Call.{
        instr = xx bytes.count,
        procedure = proc
    };
    array_add(*external_calls, c);
    output_bytes(.CALL, 0x00, 0x00);
}

push_member :: (name: string) {
    using context.current_procedure;
    if table_contains(*members, name) {
        error("Shadowing isn't supported yet");
        return;
    }
    table_add(*members, name, .NONE);
}

push_temporary :: () -> string {
    using context.current_procedure;
    name := tprint("temp_%", formatInt(nb_temporaries, minimum_digits = 2));
    table_add(*members, name, .NONE);
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

set_member_location :: (name: string, slot: Register) {
    assert(slot != .NONE);
    ensure_register_empty(slot);
    table_set(*context.current_procedure.members, name, slot);
}

copy_members :: () -> Table(string, Register) {
    using context.current_procedure;
    result : Table(string, Register);

    for members {
        table_add(*result, it_index, it);
    }
    return result;
}

reconcile_members :: (original: Table(string, Register)) {
    using context.current_procedure;
    for *members {
        ok, initial := table_find_new(*original, it_index);
        assert(ok);
        if it.* != initial {
            ensure_register_empty(initial);
            log_verbose("Reconciling % (% to %)", it_index, it.*, initial);
            output_bytes(load_instruction(initial, it.*));
            it.* = initial;
        }
    }
    assert(check_members(members), "Reconciliation asked, but not complete!");
}

check_members :: (original: Table(string, Register)) -> bool {
    using context.current_procedure;
    for members {
        ok, initial := table_find_new(*original, it_index);
        assert(ok);
        if it != initial then return false;
    }
    return true;
}

// If member is not place, will be placed
member_location :: (name: string) -> Register {
    using context.current_procedure;
    ok, slot := table_find_new(*members, name);
    assert(ok, "Member % couldn't be found", name);
    return slot;
}

ensure_register_empty :: (r: Register) {
    using context.current_procedure;
    assert(r != .NONE);
    for *members {
        if it.* == r {
            ok, new := find_next_available_register();
            log_verbose("Making sure % is empty by moving %", r, it_index);
            output_bytes(load_instruction(new, r));
            it.* = new;
            return;
        }
    }
}

move_member :: (name: string, new_slot: Register) {
    using context.current_procedure;
    assert(new_slot != .NONE);
    ok, slot := table_find_new(*members, name);
    assert(ok, "Member % couldn't be found", name);
    if slot == new_slot then return; // Nothing to do
    ensure_register_empty(new_slot);
    log_verbose("Moving % to % (was in %)", name, new_slot, slot);
    if slot != .NONE {
        output_bytes(load_instruction(new_slot, slot));
    }
    table_set(*members, name, new_slot);
}

move_member_to_next_available_slot :: (name: string) {
    using context.current_procedure;
    ok, slot := find_next_available_register();
    assert(ok, "Too many members");
    ok=, current_slot := table_find_new(*members, name);
    assert(ok, "Member % couldn't be found", name);
    log_verbose("Moving % to % (was in %)", name, slot, current_slot);
    if current_slot != .NONE {
        output_bytes(load_instruction(slot, current_slot));
    }
    table_set(*members, name, slot);
}

get_member_at :: (r: Register) -> bool, string {
    using context.current_procedure;
    for members {
        if it == r then return true, it_index;
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
            if it == xx r then continue r;
        }

        return true, xx r;
    }
    assert(false, "Unable to find a free spot for member");
    return false, 0;
}

error :: (message: string) {
    array_add(*context.current_procedure.errors, .{message, context.current_node.location});
}
