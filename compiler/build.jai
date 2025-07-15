#run build_and_output_rom();

build_and_output_rom :: () {
    log("%", load_gb_image("test.png"));
    #if 0 {
        cart := build_cart("test_bed.jai",, log_level = .VERBOSE);
    } else {
        file := "tests/array_002.jai";
        f := read_entire_file(file);
        log("%", f);
        cart := build_cart(file,, log_level = .VERBOSE);
    }

    filename := "output_rom.gb";
    write_entire_file(filename, cart.contents.data, cart.contents.count);
    log("Wrote %", filename);
}


#load "codegen.jai";

#import "Compiler";
#import "Basic";
#import "File";
#import "Program_Print";
#import "Math";
#load "../common/utils.jai";

