#run build_and_output_rom();

build_and_output_rom :: () {
    cart := build_cart("tests/call_005.jai", verbose = true);

    filename := "output_rom.gb";
    write_entire_file(filename, cart.contents.data, cart.contents.count);
    log("Wrote %", filename);
}


#load "codegen.jai";

#import "Compiler";
#import "Basic";
#import "File";
#import "Program_Print";
