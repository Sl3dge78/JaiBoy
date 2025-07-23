
Register_Size :: enum {
    BYTE;
    SHORT;
}

Occupant :: struct {
    member: string; // Empty string if empty
    part: enum {
        FULL;
        LOW;
        HIGH;
    };
}

operator == :: (a: Occupant, b: Occupant) -> bool {
    return a.member == b.member;
}

Slot :: enum s16 {
    NOT_ASSIGNED :: -1;
    A :: 0;
    B :: 1;
    C :: 2;
    D :: 3;
    E :: 4;
    H :: 5;
    L :: 6;
    STACK_00 :: 7;
    STACK_01 :: 8;
    STACK_02 :: 9;
    STACK_03 :: 10;
    // ...
    STACK_MAX :: 255;
}

Slot_Table :: [256]Occupant;

print_slot_table :: (table: Slot_Table) {
    for 0..6 {
        if table[it].member == "" then continue;
        log_verbose("% : %", it.(Slot), table[it].member);
    }
    for 7..table.count - 1 {
        if table[it].member == "" then continue;
        log_verbose("STACK % : %", it, table[it].member);
    }

}

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
    hir, lor := split_register(r);
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
    using context.current_procedure;
    for 0..(Slot.STACK_00 - 1) {
        if is_empty(slots[it]) then return true;
    }
    return false;
}

has_free_wide :: () -> bool {
    using context.current_procedure;
    for Slot.B..(Slot.STACK_00 - 1) {
        if is_empty(slots[it]) && is_empty(slots[it + 1]) then return true;
    }
    return false;
}

alloc_register :: () -> Slot {
    using context.current_procedure;
    if !has_free_register() {
        spill_coldest();
    }
    for 0..(Slot.STACK_00 - 1) {
        if is_empty(slots[it]) {
            return it;
        }
    }
    assert(false);
    return .STACK_MAX;
}

// @Hack
alloc_register_skip_a :: () -> Slot {
    using context.current_procedure;
    if !has_free_register() {
        spill_coldest();
    }
    for 1..(Slot.STACK_00 - 1) {
        if is_empty(slots[it]) {
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

    if is_empty(slots[Slot.B]) && is_empty(slots[Slot.C]){
        return .B, .C;
    } else if is_empty(slots[Slot.D]) && is_empty(slots[Slot.E]) {
        return .D, .E;
    } else if is_empty(slots[Slot.H]) && is_empty(slots[Slot.L]) {
        return .H, .L;
    } 
    assert(false);
    return .STACK_MAX, .STACK_MAX;
}

alloc_stack :: () -> Slot {
    using context.current_procedure;
    for Slot.STACK_00.(s32)..255 {
        if is_empty(slots[it]) {
            return xx it;
        }
    }

    assert(false);
    return .STACK_MAX;
}

alloc_any :: () -> Slot {
    using context.current_procedure;
    for slots {
        if is_empty(it) then return xx it_index;
    }
    assert(false);
    return .STACK_MAX;
}

alloc_any_wide :: () -> hi: Slot, lo: Slot {
    using context.current_procedure;
    i := 1;
    while i < slots.count {
        if xx i == Slot.A then continue;
        if is_empty(slots[i]) && is_empty(slots[i + 1]) {
            return xx i, xx (i + 1);
        }
        i += 2;
    }
    assert(false);
    return .STACK_MAX, .STACK_MAX;
}

free_member :: (member: string) {
    using context.current_procedure;
    for *slots {
        if it.member == member {
            it.member = "";
        }
    }
}

is_empty :: (register: Register) -> bool {
    if is_wide(register) {
        hi, lo := to_slot_wide(register);
        return is_empty(hi) && is_empty(lo);
    } else {
        r := to_slot(register);
        return is_empty(r);
    }
}

is_empty :: (slot: Slot) -> bool {
    using context.current_procedure;
    return slots[slot].member == "";
}

is_empty :: (occupant: Occupant) -> bool {
    return occupant.member == "";
}

force_empty :: (register: Register) {
    log_verbose("Force empty %", register);
    defer log_verbose("Done emptying %", register);
    if is_wide(register) {
        hi_src, lo_src := split_register(register);
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
    copy(from, to);
    slots[to] = slots[from];
    slots[from].member = "";
}

copy :: (from: Slot, to: Slot) {
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
}

in_stack :: (slot: Slot) -> bool {
    return slot >= .STACK_00;
}

move_wide :: (from_hi: Slot, from_lo : Slot, to_hi: Slot, to_lo: Slot) {
    using context.current_procedure;
    log_verbose("Move wide : % % -> % % (stack : %)", from_hi, from_lo, to_hi, to_lo, stack_size);
    assert(!(in_stack(from_lo) && in_stack(from_hi) && in_stack(to_hi) && in_stack(to_lo)));
    if to_hi == Slot.STACK_00 + cast(Slot)stack_size && to_lo == to_hi + 1 { // Pushing
        assert(to_hi + 1 == to_lo);

        if from_hi == .H && from_lo == .L {
            push_hl();
        } else if from_hi == .B && from_lo == .C {
            push_bc();
        } else {
            assert(false);
        }
    } else if stack_size > 0 && from_lo == Slot.STACK_00 + cast(Slot)(stack_size - 1) && from_lo == from_hi + 1 {
        if to_hi == .H && to_lo == .L {
            pop_hl();
        } else if to_hi == .B && to_lo == .C {
            pop_bc();
        } else if to_hi == .D && to_lo == .E {
            pop_de();
        } else {
            assert(false);
        }
    } else {
        move(from_hi, to_hi);
        move(from_lo, to_lo);
    }
}

copy_wide :: (from_hi: Slot, from_lo : Slot, to_hi: Slot, to_lo: Slot) {
    copy(from_hi, to_hi);
    copy(from_lo, to_lo);
}

from_top_of_stack :: (slot: Slot) -> s8 {
    assert(slot != .STACK_MAX);
    assert(slot >= .STACK_00);
    return slot.(s8) - Slot.STACK_00.(s8);
}

// Base address in HL
push_stack :: () {
    using context.current_procedure;
    push_hl_if_not_empty();
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

push_hl_if_not_empty :: () {
    using context.current_procedure;
    if !is_empty(.HL) {
        log_verbose("Pushing HL to free space");
        output_bytes(.PUSH_HL);
        slots[xx(Slot.STACK_00) + stack_size] = slots[Slot.H];
        stack_size += 1;
        slots[xx(Slot.STACK_00) + stack_size] = slots[Slot.L];
        stack_size += 1;
        slots[Slot.H] = Occupant.{};
        slots[Slot.L] = Occupant.{};
    }
}

stack_in_hl :: (slot: Slot) {
    using context.current_procedure;
    assert(slot >= .STACK_00);
    stack_addr := stack_size - from_top_of_stack(slot);
    force_empty(.HL);
    output_bytes(.LD_HL_SP_PLUS_S8, cast,no_check(u8)(stack_addr));
    output_bytes(.ADD_SP_S8, cast,no_check(u8)(-stack_addr));
}

find_single :: (member: string) -> bool, Slot {
    using context.current_procedure;
    for slots {
        if it.member == member {
            assert(it.part == .FULL);
            return true, xx it_index;
        }
    }
    return false, .STACK_MAX;
}

find_wide :: (member: string) -> bool, hi: Slot, lo: Slot {
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
                return true, hi, lo;
            }
        }
    }
    return false, .STACK_MAX, .STACK_MAX;
}

split_wide_slot :: (register: Register) -> hi: Slot, lo: Slot {
    hi, lo := split_register(register);
    return to_slot(hi), to_slot(lo);
}

spill_coldest :: () {
    using context.current_procedure;
    found, name := coldest_member_in_register();
    if !found then return;
    coldest := get_member(name);

    if !is_wide(name) {
        ok, from := find_single(name);
        assert(ok);
        to := alloc_stack();
        move(from, to);
    } else {
        ok, lo_src, hi_src := find_wide(name);
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
        slots[lo_src].member = "";
        slots[hi_src].member = "";
    }
}

coldest_member_in_register :: () -> bool, string {
    using context.current_procedure;
    result := "";
    coldest := S64_MAX;
    for 0.. (Slot.STACK_00 - 1) {
        occ := slots[it];
        if is_empty(occ) then continue; 
        member := get_member(occ.member);
        if member.hot > coldest {
            result = occ.member;
            coldest = member.hot;
        }
    }
    return result != "", result;
}

coldest_wide_in_register :: () -> Slot, Slot {
    using context.current_procedure;

    score :: (a: Slot, b: Slot) -> int {
        using context.current_procedure;
        result := 0;
        if !is_empty(slots[a]) {
            ma := slots[a].member;
            result += get_member(ma).hot;
        }
        if !is_empty(slots[b]) {
            mb := slots[b].member;
            result += get_member(mb).hot;
        }
        return result / 2;
    }
    
    bc := score(.B, .C);
    de := score(.D, .E);
    hl := score(.H, .L);
    
    log_verbose("hotness: bc: % de: % hl: %", bc, de, hl);
    if bc <= de && bc <= hl {
        return .B, .C;
    } else if de <= bc && de <= hl {
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
    slots[lo_src].member = "";
    slots[hi_src].member = "";
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
        if it.member == "" then continue;
        if it != other[it_index] then return false;
    }
    return true;
}

reconcile_slots :: (original: Slot_Table) {
    log_verbose("Begin reconciliation");
    using context.current_procedure;
    max_iters := 20;
    while !compare_slots(original) {
        log_verbose("CURRENT");
        print_slot_table(slots);
        log_verbose("ORIGINAL");
        print_slot_table(original);
        for slots {
            if it.member == "" then continue;
            if it != original[it_index] {
                initial := find_equivalent_occupant_in(original, it);
                log_verbose("Reconciling % (% to %)", it.member, it_index.(Slot), initial.(Slot));
                if !is_empty(initial) {
                    temp := alloc_stack();
                    move(initial, temp);
                }
                move(xx it_index, initial);
                log_verbose("Reconciled % to %", it.member, it_index.(Slot));
                break;
            }
        }
        max_iters -= 1;
        assert(max_iters > 0 , "Couldn't completely reconcile_members after % iterations", 20);
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

push :: (hi: Slot, lo: Slot) {
    using context.current_procedure;
    slots[Slot.STACK_00.(int) + stack_size] = slots[hi];
    stack_size += 1;
    slots[Slot.STACK_00.(int) + stack_size] = slots[lo];
    stack_size += 1;
    slots[hi] = Occupant.{};
    slots[lo] = Occupant.{};
}

pop :: (hi: Slot, lo: Slot) {
    using context.current_procedure;
    stack_size -= 1;
    slots[lo] = slots[Slot.STACK_00.(int) + stack_size];
    slots[Slot.STACK_00.(int) + stack_size] = Occupant.{};
    stack_size -= 1;
    slots[hi] = slots[Slot.STACK_00.(int) + stack_size];
    slots[Slot.STACK_00.(int) + stack_size] = Occupant.{};
    assert(stack_size >= 0);
}

push_bc :: () {
    output_bytes(.PUSH_BC);
    push(.B, .C);
}

push_de :: () {
    output_bytes(.PUSH_DE);
    push(.D, .E);
}

push_hl :: () {
    output_bytes(.PUSH_HL);
    push(.H, .L);
}

pop_hl :: () {
    output_bytes(.POP_HL);
    pop(.H, .L);
}

pop_bc :: () {
    output_bytes(.POP_BC);
    pop(.B, .C);
}

pop_de :: () {
    output_bytes(.POP_DE);
    pop(.D, .E);
}


