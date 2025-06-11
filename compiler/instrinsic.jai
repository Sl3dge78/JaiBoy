
get_intrinsic :: (name: string, call: *Code_Procedure_Call) -> bool, []u8 {
    if name == {
        case "di"; {
            return true, .[ xx Instruction_Kind.DI ];
        }
        case "ei"; {
            return true, .[ xx Instruction_Kind.EI ];
        }
        case "halt"; {
            return true, .[ xx Instruction_Kind.HALT ];
        }
        case "reti"; {
            return true, .[ xx Instruction_Kind.RETI ];
        }
        case "sp"; {
            arg := call.arguments_sorted[0];
            log("%", arg.kind);
            if arg.kind != .LITERAL {
                error("Expected a literal to call to intrinsic sp");
                return false, .[];
            }
            lit := arg.(*Code_Literal);
            if lit.value_type != .NUMBER {
                error("Expected a number literal to call to intrinsic sp");
                return false, .[];
            }
            val := lit._u64;
            if lit._u64 > 0xFFFF {
                error("Values can't exceed 0xFFFF");
                return false, .[];
            }
            return true, .[ xx Instruction_Kind.LD_SP_IMM_16, (val & 0xFF).(u8), ((val >> 8) & 0xFF).(u8)];
        }
        case; {
            error(tprint("Intrinsic % not found", name));
            return false, .[];
        }
    };
}


