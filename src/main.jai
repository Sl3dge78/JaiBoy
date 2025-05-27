#import "Basic";
#import "jai-sdl3";
#import "Math";
File :: #import "File";

#load "gb.jai";
#load "debug.jai";
#load "opcodes.jai";

Vector2i :: struct {
    x : s32;
    y : s32;
}



main :: () {

    if __command_line_arguments.count != 2 {
        log("Usage : gb_jai [path/to/rom.gb]");
        return;
    }

    SDL_Init(SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_EVENTS);
    defer SDL_Quit();

    window := SDL_CreateWindow("JaiBoy", SCREEN_WIDTH, SCREEN_HEIGHT, SDL_WINDOW_VULKAN);
    defer SDL_DestroyWindow(window);

    renderer := SDL_CreateRenderer(window, null);
    defer SDL_DestroyRenderer(renderer);

    // ImGui
    // ImGui.CreateContext();
    // ImplSDL3_InitForSDLRenderer(window, renderer);
    // defer ImplSDL3_Shutdown();

    // Gameboy
    gb := New(Gameboy);
    defer free(gb);
 
    gb_texture := SDL_CreateTexture(renderer, .ABGR8888, .STREAMING, SCREEN_WIDTH, SCREEN_HEIGHT);
    SDL_SetTextureBlendMode(gb_texture, 0);
    display_size := 1;

    show_debug := false;
    init_debug();

    init(gb);
    defer destroy(gb);
    
    if !load_rom(gb, to_string(__command_line_arguments[1])) {
        return;
    }
    reset(gb);
        
    delta_time : float = 0;
    frame_start := SDL_GetPerformanceCounter();
    while main_loop := true {
        
        time := SDL_GetPerformanceCounter();
        delta_time = cast(float)(time - frame_start) / SDL_GetPerformanceFrequency();
        frame_start = time;

        event: SDL_Event;
        while SDL_PollEvent(*event) {
            // ImplSDL3_ProcessEvent(*event);
            if event.type == { 
                case .QUIT;
                    break main_loop;
                case .KEY_DOWN; {
                    if event.key.scancode == {
                        case ._1; display_size = 1; 
                        case ._2; display_size = 2;
                        case ._3; display_size = 3;

                        case .F5; show_debug = !show_debug;

                        // Break
                        case .SPACE; #through; 
                        case .F9; 
                            gb.step_through = !gb.step_through; 

                        // Trace
                        case .F7; #through;
                        case .N; gb.cycles_left = ifx gb.cpu_clock <= 0 then 1 else gb.cpu_clock;

                        case .R; reset(gb);
                        case .KP_PLUS; gb.clock_mul *= 10.0;
                        case .KP_MINUS; gb.clock_mul /= 10.0;
                        
                        case; input(gb, *event.key, 0);
                    }
                }
                case .KEY_UP; {
                    input(gb, *event.key, 1);
                }   
            }
        }

        loop(gb, delta_time);
        SDL_SetRenderDrawColorFloat(renderer, 0.2, 0.2, 0.2, 1);
        SDL_RenderClear(renderer);

        copy_lcd_to_texture(gb, gb_texture);
        SDL_RenderTexture(renderer, gb_texture, null, null);

        // ImplSDL3_NewFrame();
        // ImGui.NewFrame();

        if show_debug then draw_debug(gb);

        // ImGui.Render();
        // ImplSDL3_RenderDrawData(ImGui.GetDrawData());

        reset_temporary_storage();
        SDL_RenderPresent(renderer);
        frame_time := SDL_GetPerformanceCounter() - frame_start;
        while frame_time < SDL_GetPerformanceFrequency() / 60 {
            frame_time = SDL_GetPerformanceCounter() - frame_start;
        }        
    }
}

copy_lcd_to_texture :: (gb: *Gameboy, texture: *SDL_Texture) {
    data : [SCREEN_HEIGHT * SCREEN_WIDTH]Color = ---;
    for y: 0..SCREEN_HEIGHT - 1 {
        for x: 0..SCREEN_WIDTH - 1 {
            pixel := gb.lcd_screen[y][x];
            color := palette[pixel];
            // data[x + y * SCREEN_WIDTH] = .{ color.a, color.b, color.g, color.r };
            data[x + y * SCREEN_WIDTH] = color;
        }
    }
    SDL_UpdateTexture(texture, null, data.data, 4 * size_of(u8) * SCREEN_WIDTH);
    
}
