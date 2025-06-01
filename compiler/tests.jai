#load "codegen.jai";
#import "Compiler";
#import "Basic";
#import "File";

#run test_load_gen();

test_load_gen :: () {
    r := load_instruction(.A, .IMM_8);
    log("%", formatInt(r, base = 16));
    assert(load_instruction(.A, .IMM_8) == 0x3E);


}
