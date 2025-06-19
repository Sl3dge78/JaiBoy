#run build_and_output_rom();

build_and_output_rom :: () {
    // cart := build_cart("test_bed.jai",, log_level = .VERBOSE);
    cart := build_cart("tests/less_or_equal_002.jai",, log_level = .VERBOSE);

    filename := "output_rom.gb";
    write_entire_file(filename, cart.contents.data, cart.contents.count);
    log("Wrote %", filename);
}


#load "codegen.jai";

#import "Compiler";
#import "Basic";
#import "File";
#import "Program_Print";
