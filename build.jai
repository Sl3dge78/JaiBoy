Compiler :: #import "Compiler";
#import "File_Utilities";
#import "Basic";
#run build();

build :: () {
    w := Compiler.compiler_create_workspace();
    
    options := Compiler.get_build_options();
    options.output_path = "bin";
    options.output_executable_name = "JaiBoy";
    options.optimization_level = .RELEASE;

    file_path := parse_path(#filepath);
    array_add(*file_path.words, "modules");
    path_string := path_to_string(file_path, file_path.words.count);
    defer free(path_string);

    import_path : [..] string;
    array_add(*import_path, ..options.import_path);
    array_add(*import_path, path_string);
    options.import_path = import_path;
    
    lsp_message : (message : *Compiler.Message);
    is_lsp := false;
    if options.user_data_u64 {
        lsp_message = << cast(*(*Compiler.Message)) options.user_data_u64;  
        is_lsp = true;
    }

    Compiler.set_build_options(options, w);
    Compiler.compiler_begin_intercept(w);
    Compiler.add_build_file("src/main.jai", w);

    while true {
        msg := Compiler.compiler_wait_for_message();
        if !msg continue;
        if msg.kind == .COMPLETE break;
        
        if is_lsp {
            lsp_message(msg);
        }
    }
    Compiler.compiler_end_intercept(w);
    Compiler.set_build_options_dc(.{do_output = false});
}


