Basic :: #import "Basic";
#import "SDL";
#import "Math";
Simp :: #import "simp_sdl"(use_sdl = true);
File :: #import "File";


#load "../modules/imgui_sdl_gl.jai";

#import "GL";

#load "gb.jai";
#load "debug.jai";
#load "opcodes.jai";

Vector2i :: struct {
    x : s32;
    y : s32;
}



main :: () {

    if __command_line_arguments.count != 2 {
        Basic.log("Usage : gb_jai [path/to/rom.gb]");
        return;
    }

    SDL_Init(SDL_INIT_EVERYTHING);
    defer SDL_Quit();

    window := SDL_CreateWindow("JaiBoy", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, SCREEN_WIDTH, SCREEN_HEIGHT, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE);
    defer SDL_DestroyWindow(window);

    Simp.set_render_target(window);

    // ImGui
    ImGui.CreateContext();
    ImGui_ImplSdl_Init(window);
    defer ImGui_ImplSdl_Shutdown();

    // Gameboy
    gb := Basic.New(Gameboy);
    defer Basic.free(gb);
 
    gb_texture := Basic.New(Simp.Texture);
    gb_texture.width = SCREEN_WIDTH;
    gb_texture.height = SCREEN_HEIGHT;
    gb_texture.format = .RGB8;
    Simp.backend_realloc_texture(gb_texture, null);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    display_size := 1;

    show_debug := false;
    init_debug();

    init(gb);
    defer destroy(gb);
    
    if !load_rom(gb, Basic.to_string(__command_line_arguments[1])) {
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
            ImGui_ImplSdl_ProcessEvent(*event);
            if event.type == { 
                case SDL_QUIT;
                    break main_loop;
                case SDL_KEYDOWN; {
                    if event.key.keysym.scancode == {
                        case SDL_SCANCODE_1; display_size = 1; 
                        case SDL_SCANCODE_2; display_size = 2;
                        case SDL_SCANCODE_3; display_size = 3;

                        case SDL_SCANCODE_F5; show_debug = !show_debug;

                        // Break
                        case SDL_SCANCODE_SPACE; #through; 
                        case SDL_SCANCODE_F9; 
                            gb.step_through = !gb.step_through; 

                        // Trace
                        case SDL_SCANCODE_F7; #through;
                        case SDL_SCANCODE_N; gb.cycles_left = ifx gb.cpu_clock <= 0 then 1 else gb.cpu_clock;

                        case SDL_SCANCODE_R; reset(gb);
                        case SDL_SCANCODE_KP_PLUS; gb.clock_mul *= 10.0;
                        case SDL_SCANCODE_KP_MINUS; gb.clock_mul /= 10.0;
                        
                        case; input(gb, *event.key, 0);
                    }
                }
                case SDL_KEYUP; {
                    input(gb, *event.key, 1);
                }   
                case SDL_WINDOWEVENT; {
                    if event.window.event == SDL_WINDOWEVENT_RESIZED {
                        Simp.update_window(window);
                    }
                }
            }
        }

        loop(gb, delta_time);
        Simp.clear_render_target(0.2, 0.2, 0.2, 1);

        copy_lcd_to_texture(gb, gb_texture);
        Simp.set_shader_for_images(gb_texture);
        Simp.immediate_begin();
        p0, p1 := get_display_pos(window, display_size);
        Simp.immediate_quad(p0.x, p0.y, p1.x, p1.y, make_vector4(1, 1, 1, 1));
        Simp.immediate_flush();

        ImGui_ImplSdl_NewFrame(window);
        ImGui.NewFrame();

        if show_debug then draw_debug(gb);

        ImGui.Render();
        ImGui_ImplSdl_RenderDrawLists(ImGui.GetDrawData());

        reset_temporary_storage();
        Simp.swap_buffers(window);
        frame_time := SDL_GetPerformanceCounter() - frame_start;
        while frame_time < SDL_GetPerformanceFrequency() / 60 {
            frame_time = SDL_GetPerformanceCounter() - frame_start;
        }        
    }
}

get_display_pos :: (window: *SDL_Window, size: int) -> Vector2, Vector2{
    w: s32;
    h: s32;
    SDL_GetWindowSize(window, *w, *h);

    p0 : Vector2;
    p0.x = 0;
    p0.y = xx (h - (SCREEN_HEIGHT * size));
    p1 : Vector2;
    p1.x = xx (SCREEN_WIDTH * size);
    p1.y = xx h;

    // Resize window if smaller or the same size as the gb screen
    if w < SCREEN_WIDTH * size || h < SCREEN_HEIGHT * size || (w % SCREEN_WIDTH == 0 && h % SCREEN_HEIGHT == 0) {
        SDL_SetWindowSize(window, xx (SCREEN_WIDTH * size), xx(SCREEN_HEIGHT * size));
        Simp.update_window(window);
    }
    return p0, p1;
}

copy_lcd_to_texture :: (gb: *Gameboy, texture: Simp.Texture) {
    glBindTexture(GL_TEXTURE_2D, texture.gl_handle);
    data : [SCREEN_HEIGHT * SCREEN_WIDTH]Color = ---;
    for y: 0..SCREEN_HEIGHT - 1 {
        for x: 0..SCREEN_WIDTH - 1 {
            pixel := gb.lcd_screen[y][x];
            color := palette[pixel];
            data[x + y * SCREEN_WIDTH] = color;
        }
    }
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, SCREEN_WIDTH, SCREEN_HEIGHT, 0, GL_RGB, GL_UNSIGNED_BYTE, data.data);
}
