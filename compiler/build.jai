#run build();

build :: () {
    w := compiler_create_workspace();
    
    options := get_build_options();
    options.output_type = .NO_OUTPUT;
    options.runtime_support_definitions = .OMIT;

    procedures : [..] *Code_Procedure_Header;

    set_build_options(options, w);
    compiler_begin_intercept(w);
    add_build_file("test.jai", w);

    while true {
        msg := compiler_wait_for_message();
        if !msg continue;
        if msg.kind == .TYPECHECKED {
            tc := cast(*Message_Typechecked) msg;
            gather(tc, *procedures);
        }

        if msg.kind == .COMPLETE {
            generate_assembly(procedures);
            break;
        }

    }
    compiler_end_intercept(w);
    set_build_options_dc(.{do_output = false});
}


gather :: (msg: *Message_Typechecked, procedures: *[..]*Code_Procedure_Header) {
    for tc: msg.all {
        expr := tc.expression;
        if expr.enclosing_load {
            if expr.enclosing_load.enclosing_import.module_type != .MAIN_PROGRAM then continue;
        }

        if expr.kind == {
            case .PROCEDURE_HEADER; {
                array_add(procedures, cast(*Code_Procedure_Header) expr);
            }

            case; {
                if expr.enclosing_load == null { 
                    log("Unsupported expression: %. Line %", expr.kind, expr.l0);
                } else { 
                    // compiler_report(expr.enclosing_load.fully_pathed_filename, expr.l0, expr.c0, tprint("Unsupported expr: %", expr.kind));
                }
            }
        }
    }
}

#load "codegen.jai";
#load "../common/opcodes.jai";

#import "Compiler";
#import "Basic";
#import "File";
