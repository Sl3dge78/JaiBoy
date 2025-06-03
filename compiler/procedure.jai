Member :: struct {
    name: string;
    register: Register;
}

Compile_Error :: struct {
    message: string;
    location: Code_Node.Location;
}

Compiled_Procedure :: struct {
    base_address : u16;
    bytes: [..]u8;
    members: [..] Member; // @TODO @Speed: Hash_Table ?
    nb_temporaries := 0;

    errors: [..]Compile_Error;
}


output_bytes :: (procedure: *Compiled_Procedure, bytes: ..u8, loc := #caller_location) {
    array_add(*procedure.bytes, ..bytes);
    if global_verbose { 
        print("%:%:%:\t", loc.fully_pathed_filename, loc.line_number, loc.character_number);
        disassemble_bytes(bytes);
    }
}

output_bytes :: (procedure: *Compiled_Procedure, bytes: []u8, loc := #caller_location) {
    array_add(*procedure.bytes, ..bytes);
    if global_verbose {
        print("%:%:%:\t", loc.fully_pathed_filename, loc.line_number, loc.character_number);
        disassemble_bytes(bytes);
    }
}

output_bytes :: (procedure: *Compiled_Procedure, instr: Instruction_Kind, bytes : ..u8, loc := #caller_location) {
    nb := procedure.bytes.count;
    array_add(*procedure.bytes, xx instr);
    array_add(*procedure.bytes, ..bytes);
    if global_verbose { 
        b := procedure.bytes;
        b.data += nb;
        b.count -= nb;
        print("%:%:%:\t", loc.fully_pathed_filename, loc.line_number, loc.character_number);
        disassemble_bytes(b);
    }
}

disassemble_bytes :: (bytes: ..u8) {
    disassemble_bytes(bytes);
}

disassemble_bytes :: (bytes: []u8) {
    i := 0;
    while i < bytes.count {
        builder : String_Builder;
        op := OPCODE_DESC_TABLE[bytes[i]];
        
        // Addr
        print_to_builder(*builder, "0x% ", formatInt(i, 16, 4));

        // Bytes
        print_to_builder(*builder, "% ", formatInt(bytes[i], 16, 2));
        if (i + (op.bytes-1)) > bytes.count - 1 {
            assert(false, "Malformed instruction: % (%)", formatInt(bytes[i], 16), op.desc);
            return;
        }
        for 1..op.bytes - 1 {
            print_to_builder(*builder, "% ", formatInt(bytes[i + it], 16, 2));
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
            print_to_builder(*builder, "%", formatInt(bytes[i + i2], 16, 2));
            i2 -= 1;
        }

        builder_string := builder_to_string(*builder,, temp);
        log("%", builder_string);
        i += op.bytes;
    }
}

Jump_Kind :: enum {
    IF_FALSE;
    ALWAYS;
}

add_jump :: (procedure: *Compiled_Procedure, kind: Jump_Kind) -> int {
    if #complete kind == {
        case .IF_FALSE; {
            addr := procedure.bytes.count;
            output_bytes(procedure, .JR_NZ_REL, 0x00);
            return addr;
        }
        case .ALWAYS; {
            addr := procedure.bytes.count;
            output_bytes(procedure, .JR_REL, 0x00);
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

push_temporary :: (using procedure: *Compiled_Procedure) -> string {
    ok, reg := find_next_available_register(procedure);
    assert(ok);
    name := tprint("temp_%", formatInt(nb_temporaries, minimum_digits = 2));
    array_add(*members, .{name, reg});
    nb_temporaries += 1;
    return name;
}

pop_member :: (using procedure: *Compiled_Procedure) {
    members.count -= 1;
}

pop_temporary :: (using procedure: *Compiled_Procedure, name: string) {
    id := -1;
    for members {
        if it.name == name {
            id = it_index;
            break;
        }
    }
    assert(id != -1, "Unable to find % in procedure members", name);
    array_ordered_remove_by_index(*procedure.members, id);
    nb_temporaries -= 1;
}

member_location :: (using procedure: *Compiled_Procedure, name: string) -> Register {
    for members {
        if it.name == name then return it.register;
    }
    assert(false, "Member % couldn't be found.", name);
    return .A;
}

ensure_register_empty :: (using procedure: *Compiled_Procedure, r: Register) {
    for *members {
        if it.register == r {
            ok, new := find_next_available_register(procedure);
            output_bytes(procedure, load_instruction(new, r));
            it.register = new;
            return;
        }
    }
}

move_member :: (using procedure: *Compiled_Procedure, name: string, move_to: Register) {
    target: *Member;
    for *members {
        if it.name == name {
            target = it;
            break;
        }
    }
    assert(target != null, "Member % couldn't be found", name);
    if target.register == move_to then return; // Nothing to do
    ensure_register_empty(procedure, move_to);
    output_bytes(procedure, load_instruction(move_to, target.register));
}

get_member_at :: (using procedure: *Compiled_Procedure, r: Register) -> *Member {
    for *members {
        if it.register == r then return it;
    }
    return null;
}

find_next_available_register :: (using procedure: *Compiled_Procedure) -> bool, Register {
    for r: register_preference {
        for members {
            if it.register == xx r then continue r;
        }

        return true, xx r;
    }
    assert(false, "Unable to find a free spot for member");
    return false, 0;
}

error :: (using procedure: *Compiled_Procedure, message: string, location: Code_Node.Location) {
    array_add(*procedure.errors, .{message, location});
}

error :: (message: string) #expand {
    error(`procedure, message, `node.location);
}
