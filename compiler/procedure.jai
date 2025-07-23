Compile_Error :: struct {
    message: string;
    location: Code_Node.Location;
}

Compiled_Procedure :: struct {
    procedure_header: *Code_Procedure_Header;

    base_address : u16;
    bytes: [..]u8;
    members: Member_Table;
    slots: Slot_Table;
    stack_size := 0;
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

procedure_header :: () {
    output_bytes(.PUSH_BC);
    output_bytes(.PUSH_DE);
    output_bytes(.PUSH_HL);
}

procedure_footer :: () {
    output_bytes(.POP_HL);
    output_bytes(.POP_DE);
    output_bytes(.POP_BC);
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
    IF_NON_ZERO;
    IF_ZERO;
    ALWAYS;
    IF_CARRY;
    IF_NON_CARRY;

    NONE;
}

begin_jump :: (kind: Jump_Kind) -> int {
    using context.current_procedure;
    addr := bytes.count;
    if #complete kind == {
        case .IF_NON_ZERO; output_bytes(.JR_NZ_REL, 0x00);
        case .IF_ZERO; output_bytes(.JR_Z_REL, 0x00);
        case .IF_CARRY; output_bytes(.JR_C_REL, 0x00);
        case .IF_NON_CARRY; output_bytes(.JR_NC_REL, 0x00);
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
    assert(distance <= 127 && distance >= -128, "Long jumps arent supported yet");
    bytes[jump_addr + 1] = cast,no_check(u8)(distance.(s8));
}

mark_jump :: () -> int {
    using context.current_procedure;
    return bytes.count;
}

jump_to :: (addr: int) {
    using context.current_procedure;
    current_addr := bytes.count;
    distance : s8 = xx (addr - current_addr);
    distance -= 2; // Size of JR_REL
    assert(distance <= 127 && distance >= -128, "Long jumps arent supported yet");
    output_bytes(.JR_REL, cast,no_check(u8)(distance));
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


error :: (message: string) {
    array_add(*context.current_procedure.errors, .{message, context.current_node.location});
}

fatal :: (message: string) {
    log_error("FATAL: %", message);
}
