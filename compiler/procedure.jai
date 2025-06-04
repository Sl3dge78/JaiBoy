Member :: struct {
    name: string;
    register: Register;
}

Compile_Error :: struct {
    message: string;
    location: Code_Node.Location;
}

Compiled_Procedure :: struct {
    procedure_header: *Code_Procedure_Header;

    base_address : u16;
    bytes: [..]u8;
    members: [..] Member; // @TODO @Speed: Hash_Table ?
    nb_temporaries := 0;

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
    if global_verbose {
        builder: String_Builder;
        print_to_builder(*builder, "%:%:%:\t", loc.fully_pathed_filename, loc.line_number, loc.character_number);
        disassemble_bytes(*builder, bytes, false);
        log("%", builder_to_string(*builder));
    }
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

        append(builder, builder_to_string(*inner));

        i += op.bytes;
    }
}

Jump_Kind :: enum {
    IF_FALSE;
    ALWAYS;
}

add_jump :: (kind: Jump_Kind) -> int {
    using context.current_procedure;
    if #complete kind == {
        case .IF_FALSE; {
            addr := bytes.count;
            output_bytes(.JR_NZ_REL, 0x00);
            return addr;
        }
        case .ALWAYS; {
            addr := bytes.count;
            output_bytes(.JR_REL, 0x00);
            return addr;
        }
    };
}

patch_jump :: (jump_addr: int) {
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
    ok, pos := find_next_available_register();
    assert(ok, "Too many members in procedure.");
    array_add(*members, .{name, pos});
}

push_temporary :: () -> string {
    using context.current_procedure;
    ok, reg := find_next_available_register();
    assert(ok);
    name := tprint("temp_%", formatInt(nb_temporaries, minimum_digits = 2));
    array_add(*members, .{name, reg});
    nb_temporaries += 1;
    return name;
}

pop_member :: () {
    using context.current_procedure;
    members.count -= 1;
}

pop_temporary :: (name: string) {
    using context.current_procedure;
    id := -1;
    for members {
        if it.name == name {
            id = it_index;
            break;
        }
    }
    assert(id != -1, "Unable to find % in procedure members", name);
    array_ordered_remove_by_index(*context.current_procedure.members, id);
    nb_temporaries -= 1;
}

member_location :: (name: string) -> Register {
    using context.current_procedure;
    for members {
        if it.name == name then return it.register;
    }
    assert(false, "Member % couldn't be found.", name);
    return .A;
}

ensure_register_empty :: (r: Register) {
    using context.current_procedure;
    for *members {
        if it.register == r {
            ok, new := find_next_available_register();
            output_bytes(load_instruction(new, r));
            it.register = new;
            return;
        }
    }
}

move_member :: (name: string, move_to: Register) {
    using context.current_procedure;
    target: *Member;
    for *members {
        if it.name == name {
            target = it;
            break;
        }
    }
    assert(target != null, "Member % couldn't be found", name);
    if target.register == move_to then return; // Nothing to do
    ensure_register_empty(move_to);
    output_bytes(load_instruction(move_to, target.register));
}

get_member_at :: (r: Register) -> *Member {
    using context.current_procedure;
    for *members {
        if it.register == r then return it;
    }
    return null;
}

find_next_available_register :: () -> bool, Register {
    using context.current_procedure;
    for r: register_preference {
        for members {
            if it.register == xx r then continue r;
        }

        return true, xx r;
    }
    assert(false, "Unable to find a free spot for member");
    return false, 0;
}

error :: (message: string) {
    array_add(*context.current_procedure.errors, .{message, context.current_node.location});
}
