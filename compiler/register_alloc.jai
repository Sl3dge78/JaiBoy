
Register_Size :: enum {
    BYTE;
    SHORT;
}

Occupant :: struct {
    empty: bool;
    member: string;
    part: enum {
        FULL;
        LOW;
        HIGH;
    };
}

operator == :: (a: Occupant, b: Occupant) -> bool {
    if a.empty && b.empty then return true;
    if a.empty != b.empty then return false;
    return a.member == b.member;
}

Slot :: enum u8 {
    A :: 0;
    B :: 1;
    C :: 2;
    D :: 3;
    E :: 4;
    H :: 5;
    L :: 6;
    STACK_00 :: 7;
    // ...
    STACK_MAX :: 255;
}

Slot_Table :: [256]Occupant;

to_register :: (s: Slot) -> Register {
    if s == {
        case .A; return .A;
        case .B; return .B;
        case .C; return .C;
        case .D; return .D;
        case .E; return .E;
        case .H; return .H;
        case .L; return .L;
        case; assert(s <= .L); return .NONE;
    }
}

to_register :: (hi: Slot, lo: Slot) -> Register {
    return to_register(hi) | to_register(lo);
}

to_slot :: (r: Register) -> Slot {
    assert(!is_wide(r));
    if r == {
        case .A; return .A;
        case .B; return .B;
        case .C; return .C;
        case .D; return .D;
        case .E; return .E;
        case .H; return .H;
        case .L; return .L;
        case; assert(false); return .STACK_MAX;
    }
}

to_slot_wide :: (r: Register) -> hi: Slot, lo: Slot {
    assert(is_wide(r));
    lor, hir := split_register(r);
    assert(hir != .NONE);
    hi := to_slot(hir);
    lo := to_slot(lor);
    return hi,lo;
}

is_stack :: inline (s: Slot) -> bool {
    return s >= .STACK_00;
}

is_register :: inline (s: Slot) -> bool {
    return !is_stack(s);
}


has_free_register :: () -> bool {
    for 0..(Slot.STACK_00 - 1) {
        if slots[it].empty then return true;
    }
    return false;
}

has_free_wide :: () -> bool {
    for Slot.B..(Slot.STACK_00 - 1) {
        if slots[it].empty && slot[it + 1].empty then return true;
    }
    return false;
}

alloc_register :: () -> Slot {
    using context.current_procedure;
    if !has_free_register() {
        spill_coldest();
    }
    for 0..(Slot.STACK_00 - 1) {
        if slots[it].empty {
            slots[it].empty = false;
            return it;
        }
    }
    assert(false);
    return .STACK_MAX;
}

alloc_wide_register :: () -> Slot, Slot {
    using context.current_procedure;

    if !has_free_wide() {
        spill_coldest_wide();
    }

    if slots[Slot.B].empty && slots[Slot.C].empty {
        slots[Slot.B].empty = false;
        slots[Slot.C].empty = false;
        return .B, .C;
    } else if slots[Slot.D].empty && slots[Slot.E].empty {
        slots[Slot.D].empty = false;
        slots[Slot.E].empty = false;
        return .D, .E;
    } else if slots[Slot.H].empty && slots[Slot.L].empty {
        slots[Slot.H].empty = false;
        slots[Slot.L].empty = false;
        return .H, .L;
    } 
    assert(false);
    return .STACK_MAX, .STACK_MAX;
}

alloc_stack :: () -> Slot {
    using context.current_procedure;
    for Slot.STACK_00.(s32)..255 {
        if slots[it].empty {
            slots[it].empty = false;
            return xx it;
        }
    }

    assert(false);
    return .STACK_MAX;
}

alloc_any :: () -> Slot {
    using context.current_procedure;
    for slots {
        if it.empty then return xx it_index;
    }
    assert(false);
    return .STACK_MAX;
}

alloc_any_wide :: () -> hi: Slot, lo: Slot {
    using context.current_procedure;
    for slots {
        if xx it_index == Slot.A then continue;
        if it.empty && slots[it_index + 1].empty {
            return xx it_index, xx (it_index + 1);
        }
    }
    assert(false);
    return .STACK_MAX, .STACK_MAX;
}

free_member :: (member: string) {
    using context.current_procedure;
    for *slots {
        if !it.empty && it.member == member {
            it.empty = true;
            it.member = "";
        }
    }
}

is_empty :: (slot: Slot) -> bool {
    using context.current_procedure;
    return slots[slot].empty;
}

force_empty :: (register: Register) {
    if is_wide(register) {
        lo_src, hi_src := split_register(register);
        lo_s := to_slot(lo_src);
        hi_s := to_slot(hi_src);
        if is_empty(lo_s) && is_empty(hi_s) then return;

        hi_dst, lo_dst := alloc_any_wide();
        move_wide(hi_s, lo_s, hi_dst, lo_dst);
    } else {
        if is_empty(to_slot(register)) then return;
        dst := alloc_any();
        move(to_slot(register), dst);
    }
}

move :: (from: Slot, to: Slot) {
    using context.current_procedure;
    if is_register(from) && is_register(to) {
        load_instruction(to_register(to), to_register(from));
    } else if is_stack(from) && is_register(to) { // Stack -> Register
        stack_in_hl(from);
        load_instruction(to_opcode(to_register(to)), .HL_INDIRECT);
    } else if is_register(from) && is_stack(to) { // Register -> Stack
        if stack_size <= from_top_of_stack(to) {
            push_stack();
        } else {
            stack_in_hl(to);
        }
        load_instruction(.HL_INDIRECT, to_opcode(to_register(from)));
    } else { // Stack -> Stack
        // Kinda dumb
        assert(false, "Trying to move from stack to stack");
    }
    slots[to] = slots[from];
    slots[from].empty = true;
}

move_wide :: (from_hi: Slot, from_lo : Slot, to_hi: Slot, to_lo: Slot) {
    // @TODO Check if from == register and to == stack to use PUSH
    move(from_hi, to_hi);
    move(from_lo, to_lo);
}

from_top_of_stack :: (slot: Slot) -> s8 {
    return slot.(s8) - Slot.STACK_00.(s8);
}

// Base address in HL
push_stack :: () {
    using context.current_procedure;

    force_empty(.HL);
    output_bytes(.LD_HL_SP_PLUS_S8, 0);
    output_bytes(.ADD_SP_S8, cast,no_check(u8)(1));
    stack_size += 1;
}

pop_stack :: (size: s8) {
    using context.current_procedure;
    assert(size <= stack_size);
    output_bytes(.ADD_SP_S8, cast,no_check(u8)(-size));
    stack_size -= size;
}

stack_in_hl :: (slot: Slot) {
    assert(slot >= .STACK_00);
    stack_addr := stack_size - from_top_of_stack(from);
    force_empty(.HL);
    output_bytes(.LD_HL_SP_PLUS_S8, stack_addr);
}

find_single :: (member: string) -> Slot {
    using context.current_procedure;
    for slots {
        assert(it.part == .FULL);
        if it.member == member return xx it_index;
    }
    assert(false);
    return .STACK_MAX;
}

find_wide :: (member: string) -> hi: Slot, lo: Slot {
    using context.current_procedure;
    found := 0;
    lo: Slot;
    hi: Slot;
    for slots {
        if it.member == member {
            assert(it.part != .FULL);
            if it.part == .LOW {
                lo = xx it_index;
                found |= 0b01;
            }
            if it.part == .HIGH {
                hi = xx it_index;
                found |= 0b10;
            }
            if found == 0b11 {
                return hi, lo;
            }
        }
    }
    assert(false);
    return .STACK_MAX, .STACK_MAX;
}

split_wide_slot :: (register: Register) -> hi: Slot, lo: Slot {
    lo, hi:= split_register(register);
    return to_slot(hi), to_slot(lo);
}


spill_coldest :: () {
    using context.current_procedure;
    name := coldest_member_in_register();
    coldest := get_member(name);
    if !is_wide(coldest) {
        from := find_single(name);
        to := alloc_stack();
        move(from, to);
    } else {
        lo_src, hi_src := find_wide(name);
        hi_dst := alloc_stack();
        lo_dst := alloc_stack();
        if hi_src == .B && lo_src == .C {
            output_bytes(.PUSH_BC);
        } else if hi_src == .D && lo_src == .E {
            output_bytes(.PUSH_DE);
        } else if hi_src == .H && lo_src == .L {
            output_bytes(.PUSH_HL);
        } else {
            move(hi_src, hi_dst);
            move(lo_src, lo_dst);
        }
        slots[hi_dst] = slots[hi_src];
        slots[lo_dst] = slots[lo_src];
        slots[lo_src].empty = true;
        slots[hi_src].empty = true;
    }
}

coldest_member_in_register :: () -> string {
    using context.current_procedure;
    result := "";
    coldest := S64_MAX;
    for 0.. (Slot.STACK_00 - 1) {
        occ := slots[it];
        if occ.empty then continue; 
        member := get_member(occ.member);
        if member.hot > coldest {
            result = occ.member;
            coldest = member.hot;
        }
    }
    assert(result != "");
    return result;
}

coldest_wide_in_register :: () -> Slot, Slot {
    using context.current_procedure;

    score :: (a: Slot, b: Slot) -> int {
        using context.current_procedure;
        result := 0;
        if !slots[a].empty {
            ma := slots[a].member;
            result += get_member(ma).hot;
        }
        if !slots[b].empty {
            mb := slots[b].member;
            result += get_member(mb).hot;
        }
        return result / 2;
    }
    
    bc := score(.B, .C);
    de := score(.D, .E);
    hl := score(.H, .L);
    
    if bc < de && bc < hl {
        return .B, .C;
    } else if de < bc && de < hl {
        return .D, .E;
    } else {
        return .H, .L;
    }
}


spill_coldest_wide :: () {
    using context.current_procedure;
    hi_src, lo_src := coldest_wide_in_register();
    hi_dst := alloc_stack();
    lo_dst := alloc_stack();
    if hi_src == .B && lo_src == .C {
        output_bytes(.PUSH_BC);
    } else if hi_src == .D && lo_src == .E {
        output_bytes(.PUSH_DE);
    } else if hi_src == .H && lo_src == .L {
        output_bytes(.PUSH_HL);
    } else {
        move(hi_src, hi_dst);
        move(lo_src, lo_dst);
    }
    slots[hi_dst] = slots[hi_src];
    slots[lo_dst] = slots[lo_src];
    slots[lo_src].empty = true;
    slots[hi_src].empty = true;
}


copy_slots :: () -> Slot_Table {
    using context.current_procedure;
    new : Slot_Table;
    for slots {
        new[it_index] = it;
    }
    return new;
}

compare_slots :: (other: Slot_Table) -> bool {
    using context.current_procedure;
    for slots {
        if it != other[it_index] then return false;
    }
    return true;
}

reconcile_slots :: (original: Slot_Table) {
    using context.current_procedure;
    max_iters := 100;
    while !compare_slots(original) {
        for slots {
            if it != original[it_index] {
                initial := find_equivalent_occupant_in(original, it);
                log_verbose("Reconciling % (% to %)", it_index, it_index.(Slot), initial.(Slot));
                force_empty(to_register(initial));
                move(xx it_index, initial);
            }
        }
        max_iters -= 1;
        assert(max_iters > 0 , "Couldn't completely reconcile_members after 100 iterations");
    }
}

find_equivalent_occupant_in :: (table: Slot_Table, occ: Occupant) -> Slot {
    for table {
        if it == occ {
            return xx it_index;
        }
    }
    assert(false);
    return .STACK_MAX;
}

// Member_Slot :: struct {
//     kind : enum {
//         NONE;
//         REGISTER;
//         STACK;
//         HL_INDIRECT;
//     };
//     union {
//         register: Register;
//         rel_address: u8;
//     };
// }
//
// slot_none :: () -> Member_Slot {
//     return .{ .NONE };
// }
//
// slot_hl_indirect :: () -> Member_Slot {
//     return .{ .HL_INDIRECT };
// }
//
// slot :: (r: Register) -> Member_Slot {
//     return .{ kind = .REGISTER, register = r };
// }
//
// operator == :: (r: Member_Slot, l: Member_Slot) -> bool {
//     if r.kind != l.kind then return false;
//     if r.kind == {
//         case .REGISTER; return r.register == l.register;
//         case .STACK; return r.rel_address == l.rel_address;
//         case; return true;
//     }
// }
//
// // Returns true if the slots collide
// overlapping :: (r: Member_Slot, l: Member_Slot) -> bool {
//     if r.kind != l.kind return false;
//     if r.kind == {
//         case .REGISTER; return (r.register & l.register) != 0;
//         case .STACK; return r.rel_address == l.rel_address;
//         case; return true;
//     }
// }
//
// get_next_slot :: () -> Member_Slot {
//
// }
//
