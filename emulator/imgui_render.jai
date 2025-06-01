Immediate_State :: struct {
    renderer: *SDL_Renderer;
    font: *SDL_Texture;

    char_w: u8;
    char_h: u8;

    cx: int;
    cy: int;

    camera_x : s32;
    camera_y : s32;

    NB_CHARS_W :: 16;
    NB_CHARS_H :: 8;
}

init_immediate :: (window: *SDL_Window) -> Immediate_State {
    state: Immediate_State;
    state.renderer = SDL_CreateRenderer(window, null);
    state.font = texture_from_file("font.png", state.renderer);
    state.char_w = xx (state.font.w / Immediate_State.NB_CHARS_W);
    state.char_h = xx (state.font.h / Immediate_State.NB_CHARS_H);
    state.cx = 0;
    state.cy = 0;
    return state;
}

deinit_immediate :: (state : *Immediate_State) {
    SDL_DestroyTexture(state.font);
    SDL_DestroyRenderer(state.renderer);
}

get_char_rect :: (char: u8) -> SDL_FRect {
    id := get_char_id(char);
    x := id % state.NB_CHARS_W;
    y := id / state.NB_CHARS_W;
    return SDL_FRect.{xx (x * state.char_w), xx (y * state.char_h), xx state.char_w, xx state.char_h};
}

get_char_id :: (char : u8) -> u8 {
    if char < 0x20 return 0;
    if char > 0xFF return 0;
    return char - 0x20;
}

texture_from_file :: (path: string, renderer: *SDL_Renderer) -> *SDL_Texture {
    channels: s32;
    w: s32;
    h: s32;
    img := stbi_load(temp_c_string(path), *w, *h, *channels, 4);
    defer stbi_image_free(img);
    assert(img != null, "Unable to load texture %", path);
    
    // @Note: Somehow when converting to palette if the format specified isn't abgr 
    // it swizzles the colors weirdly. Like this it works fine.
    temp_surface := SDL_CreateSurfaceFrom(w, h, .ABGR8888, img, w * 4);
    defer SDL_DestroySurface(temp_surface);
    texture := SDL_CreateTextureFromSurface(renderer, temp_surface);
    assert(texture != null, "Error creating surface");

    return texture;
}

text :: (s: string) {
    cx := state.cx;
    for c: s {
        src := get_char_rect(c);
        dst := SDL_FRect.{
            xx (state.cx + state.camera_x), xx (state.cy + state.camera_y), 6, 12
        };
        SDL_RenderTexture(state.renderer, state.font, *src, *dst);
        state.cx += 6;
    }
    state.cy += 8;
    state.cx = cx;
}

camera :: (x: s32 = 0, y : s32 = 0) {
    rect : SDL_Rect = ---;
    SDL_GetRenderViewport(state.renderer, *rect);
    rect.x = x;
    rect.y = y;
    state.camera_x = x;
    state.camera_y = y;
    SDL_SetRenderViewport(state.renderer, *rect);
}

cursor :: (x: s32 = 0, y : s32 = 0) {
    state.cx = x;
    state.cy = y;
}

line :: (x0: float, y0: float, x1: float, y1: float) {
    SDL_RenderLine(state.renderer, x0, y0, x1, y1);
    SDL_FlushRenderer(state.renderer);
}
