
get_intrinsic :: (name: string) -> []u8 {
    if name == {
        case "di"; {
            return .[ xx Instruction_Kind.DI ];
        }
        case "ei"; {
            return .[ xx Instruction_Kind.EI ];
        }
        case "halt"; {
            return .[ xx Instruction_Kind.HALT ];
        }
        case "reti"; {
            return .[ xx Instruction_Kind.RETI ];
        }
        case; {
            assert(false, "Intrinsic % not found", name);
            return .[];
        }
    };
}


