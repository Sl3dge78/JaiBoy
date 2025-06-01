Compiler :: #import "Compiler";
#import "File_Utilities";
#import "Basic";
#run build();

build :: () {
    w := Compiler.compiler_create_workspace();
    
    options := Compiler.get_build_options();
    options.output_path = "bin";
    options.output_executable_name = "JaiBoy";
    options.additional_linker_arguments = .["/lib/libm.so"];
    Compiler.set_optimization(*options, .DEBUG);
    // Compiler.set_optimization(*options, .VERY_OPTIMIZED);
    paths : [..] string;
    array_add(*paths, ..options.import_path);
    array_add(*paths, "../modules");
    options.import_path = paths;

    Compiler.set_build_options(options, w);
    Compiler.add_build_file("main.jai", w);

    Compiler.set_build_options_dc(.{do_output = false});
}


