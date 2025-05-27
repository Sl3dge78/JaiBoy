IO_NR10 :: 0xFF10; // -TTTDNNN 	T=Time,D=direction,N=Numberof shifts
IO_NR11 :: 0xFF11; // DDLLLLLL	D=Wave pattern Duty L=Length 
IO_NR12 :: 0xFF12; // VVVVDNNN	C1 Volume / Direction 0=down / envelope Number (fade speed)
IO_NR13 :: 0xFF13; // LLLLLLLL	pitch L
IO_NR14 :: 0xFF14; // IC---HHH  C1 Initial / Counter 1=stop / pitch 

IO_NR21 :: 0xFF16; // DDLLLLLL	D=Wave pattern Duty L=Length 
IO_NR22 :: 0xFF17; // VVVVDNNN	C1 Volume / Direction 0=down / envelope Number (fade speed)
IO_NR23 :: 0xFF18; // LLLLLLLL	pitch L
IO_NR24 :: 0xFF19; // IC---HHH  C1 Initial / Counter 1=stop / pitch 

IO_NR30 :: 0xFF1A; // P------- 	P = Playback 
IO_NR31 :: 0xFF1B; // LLLLLLLL	L = Length
IO_NR32 :: 0xFF1C; // -VV-----	V = Ouput level
IO_NR33 :: 0xFF1D; // PPPPPPPP  P = Lower 8 bits of Pitch 
IO_NR34 :: 0xFF1E; // IC---PPP  C1 Initial / Counter 1=stop / pitch 

IO_NR41 :: 0xFF20; // ---LLLLL  L=Length
IO_NR42 :: 0xFF21; // VVVVDNNN 	Volume / Direction 0=down / envelope Number (fade speed)
IO_NR43 :: 0xFF22; // SSSSCDDD 	Shift clock frequency (pitch) / Counter Step 0=15bit 1=7bit / Dividing ratio (roughness)
IO_NR44 :: 0xFF23; // IC------ 	C1 Initial / Counter 1=stop

IO_NR50 :: 0xFF24; // -LLL-RRR  Channel volume
IO_NR51 :: 0xFF25; // LLLLRRRR  Mixer
IO_NR52 :: 0xFF26; // T---4321  T Sound toggle / 1-4 Status of channels 1-4

IO_WAV ::  0xFF30;
IO_WAV_END :: 0xFF3F;

AudioEnveloppe :: struct  {
    NRX0: u16;
    volume: s8;
    length: float;
    timer: u8;
};

Channel1 :: struct  {
    duty: u8;
    time: float;
    pitch: u16;
    sweep_timer: float;
    sweep_period: u8;
}; 

Channel2 :: struct  {
    duty: u8;
    time: float;
    pitch: u16;
};

Channel3 :: struct  {
    pitch: u16;
    time: float;
};

Channel4 :: struct  {
    LFSR: u16;
    timer: u16;
};

APU :: struct {
    sample_rate: u32;
    stream: *SDL_AudioStream;
    audio_gain: u32;
    
    carry : u64;
    sample_clock: u64;

    frame_clock: s32;
    frame_sequencer: s32;
    enveloppes: [4]AudioEnveloppe;

    is_playing: [4]bool;
    channel1: Channel1;
    channel2: Channel2;
    channel3: Channel3;
    channel4: Channel4;
};

get_square_duty :: (byte : u8) -> float{
    if byte == {
        case 0; return 0.125;
        case 1; return 0.250;
        case 2; return 0.500;
        case 3; return 0.750;
    }
    return 0.0;
}

tone_channel :: (time : *float, duty : u8, pitch : u16, volume : s8, sample_rate : u32) -> s8 {
    result : s8 = 0;
    if(time.* <= get_square_duty(duty))
        result = 1;
    else
        result = -1;
    time.* += cast(float)pitch * 1.0 / cast(float)sample_rate;
    if time.* > 1.0 {
        time.* = 0.0;
    }
    result *= volume;
    return result;
}

get_wave_value :: (wave: []u8, at: u32) -> s8 {
    value := wave[at / 2];
    if at % 2 == 0 {
        return cast,no_check(s8)value >> 4;
    } else {
        return cast,no_check(s8)value & 0xf;
    }   
}

wave_channel :: (wave: []u8, channel3: *Channel3, env: *AudioEnveloppe, sample_rate: u32) -> s8 {
    result := get_wave_value(wave, xx channel3.time) * 2;
    result -= 0xF;
    pitch : u16 = cast(u16)((65536) / (2048 - channel3.pitch));
    channel3.time += cast(float)pitch * 32.0 / cast(float)sample_rate;
    if(channel3.time >= 32)
        channel3.time = 0;

    if(env.volume == 0)
        return 0;
    else if(env.volume == 2)
        result /= 2;
    else if(env.volume == 3)
        result /= 4;
    return result;
}

enveloppe_init :: (gb: *Gameboy, env: *AudioEnveloppe, channel: u8) {
    NRX0 : u16 = env.NRX0;
    NRX4 : u8 = gb.mem[NRX0 + 4];
    NRX2 : u8 = gb.mem[NRX0 + 2];

    if(channel != 2) {
        length := gb.mem[NRX0 + 1] & 0b11111;
        env.length = xx (64 - length);
        volume := (NRX2 & 0xF0) >> 4; 
        env.volume = xx volume;
        env_num : u8 = (NRX2 & 0x7);
        if(env_num != 0) { // Is enveloppe sweep on
            env.timer = env_num;
        }
    } else {
        env.length = xx (256 - gb.mem[NRX0 + 1]);
        env.volume = xx ((NRX2 >> 5) & 0b11);
    }
    gb.apu.is_playing[channel] = env.volume > 0; 
}

get_sample :: (apu: *APU, mem: []u8) -> s8 {
    chan1 : s8 = 0;
    chan2 : s8 = 0;
    chan3 : s8 = 0;
    chan4 : s8 = 0;

    if(apu.is_playing[0]){
        pitch : u16 = xx(131072 / (2048 - apu.channel1.pitch));
        chan1 = tone_channel(*apu.channel1.time, apu.channel1.duty, pitch, apu.enveloppes[0].volume, apu.sample_rate);
    }

    if(apu.is_playing[1]) {
        pitch : u16 = xx(131072 / (2048 - apu.channel2.pitch));
        chan2 = tone_channel(*apu.channel2.time, apu.channel2.duty, pitch, apu.enveloppes[1].volume, apu.sample_rate);
    }

    if(apu.is_playing[2]) {
        wave : []u8;
        wave.data = mem.data + IO_WAV;
        wave.count = 16;
        chan3 = wave_channel(wave, *apu.channel3, *apu.enveloppes[2], apu.sample_rate); 
    }

    if(apu.is_playing[3]) {
        chan4 = xx ifx apu.channel4.LFSR & 1 then -1 else 1; 
        chan4 *= apu.enveloppes[3].volume;
    }

    mix : s8 = (chan1 + chan2 + chan3 + chan4) / 4;
    return mix;
}

length_update :: (gb : *Gameboy) {
    for *env: gb.apu.enveloppes {
        if(gb.mem[IO_NR52] & (1 << it_index)) {
            NRX0 := env.NRX0; 
            NRX4 := gb.mem[NRX0 + 4];
            counter := (NRX4 & 0x40) != 0;

            // Length
            if(counter) {
                env.length -= 1;
                if(env.length <= 0) {
                    env.length = 0;
                    gb.apu.is_playing[it_index] = false; 
                }
            }
        }
    }
}

sweep_update :: (gb : *Gameboy) {
    NR10 := gb.mem[IO_NR10];
    time := (NR10 >> 4) & 0b111;
    decrease : u8 = (NR10 >> 3) & 1;
    nb := (NR10) & 0b11;

    gb.apu.channel1.sweep_period -= 1;

    if(gb.apu.channel1.sweep_period == 0) {
        gb.apu.channel1.sweep_period = ifx time == 0 then 8 else time;

        // Calculate new frequency
        new_frequency := gb.apu.channel1.pitch >> nb;
        if(decrease) {
            new_frequency = gb.apu.channel1.pitch - new_frequency;
        } else {
            new_frequency = gb.apu.channel1.pitch + new_frequency;
        }
        if(new_frequency > 0x7FF) {
            //ToggleChannel(gb, 0, 0);
        } else {
            gb.apu.channel1.pitch = new_frequency;
        }
    }
}

volume_update :: (gb: *Gameboy) {
    for *env: gb.apu.enveloppes {
        if(!gb.apu.is_playing[it_index]) continue;
        NRX2 : u8 = gb.mem[env.NRX0 + 2];
        env_num : u8 = (NRX2 & 0x07);      
        if (env_num) { 
            env.timer -= 1;
            if(env.timer <= 0) {
                env.timer = env_num;
                direction := (NRX2 & 0x08) >> 3; 
                if direction && env.volume < 0xF {
                    env.volume += 1;
                } else if env.volume > 0 {
                    env.volume -= 1;
                }
            }
        }
        if(env.volume == 0)
            gb.apu.is_playing[it_index] = false;
    }
}

divisors_table :: u16.[4, 8, 16, 24, 32, 40, 48, 56];

noise_update :: (gb: *Gameboy, chan4 : *Channel4) {
    chan4.timer -= 1;
    if chan4.timer <= 0 {
        // Calculate noise timer
        NR43 := gb.mem[IO_NR43];
        shift := ((NR43 & 0b11110000) >> 4) & 0xF;
        ratio := NR43 & 0b11;
        width_mode := NR43 & 0b100 != 0;
        timer := divisors_table[ratio]; 
        chan4.timer = timer << shift;
        
        xor_result := ((chan4.LFSR & 2) >> 1) ^ (chan4.LFSR & 1);
        chan4.LFSR >>= 1;
        chan4.LFSR |= xor_result << 14;
        if(width_mode)
            chan4.LFSR = xx (chan4.LFSR & ~(1 << 6)) | (xor_result << 6);
    }
}

audio :: (gb : *Gameboy) {
    apu := *gb.apu;

    while(apu.frame_clock <= 0) {          
        if apu.frame_sequencer == {
            case 0; length_update(gb); 
            case 2; length_update(gb); sweep_update(gb); 
            case 4; length_update(gb); 
            case 6; length_update(gb); sweep_update(gb); 
            case 7; volume_update(gb); 
        }

        NR52 : u8 = (cast(u8)apu.is_playing[3]) << 3 | (cast(u8)apu.is_playing[2]) << 2 | (cast(u8)apu.is_playing[1]) << 1 | (cast(u8)apu.is_playing[0]);
        gb.mem[IO_NR52] = (gb.mem[IO_NR52] & 0xF0) | NR52;

        apu.frame_sequencer += 1;
        apu.frame_sequencer %= 8;
        apu.frame_clock += 8192;
    }
    noise_update(gb, *gb.apu.channel4);

    // Queue audio
    if apu.sample_clock < 0 {
        SDL_ClearAudioStream(apu.stream);
    }
    // @Todo this gets out of sync if we're slower than 60fps
    while apu.sample_clock <= 0 {
        sample : u8 = xx(cast(s16)get_sample(apu, gb.mem) + 127);
        SDL_PutAudioStreamData(apu.stream, *sample, 1);
        apu.sample_clock += (gb.clock_speed + apu.carry) / apu.sample_rate;
        apu.carry = (gb.clock_speed + apu.carry) % apu.sample_rate;
    }
    apu.sample_clock -= 1;
    apu.frame_clock -= 1;
}

init_audio :: (gb : *Gameboy, apu: *APU) {
    apu.sample_rate = 44100;
    apu.audio_gain = 2000;

    audio_spec : SDL_AudioSpec;
    audio_spec.format = .U8;
    audio_spec.channels = 1; // @TODO: Stereo
    audio_spec.freq = xx apu.sample_rate;

    got : SDL_AudioSpec;
    apu.stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, *audio_spec, null, null);
    
    gb.mem[IO_NR50] = 0x77;
    gb.mem[IO_NR51] = 0xF3;
    gb.mem[IO_NR52] = 0x80;
    
    apu.enveloppes[0].NRX0 = 0xFF10;
    apu.enveloppes[1].NRX0 = 0xFF15;
    apu.enveloppes[2].NRX0 = 0xFF1A;
    apu.enveloppes[3].NRX0 = 0xFF1F;

    apu.channel4.LFSR = 0xFFFF;

    wave := u8.[
        0xC1,
        0xE6,
        0x86,
        0x5D,
        0x67,
        0xBE,
        0xB1,
        0xE9,
        0x00,
        0x7F,
        0x19,
        0xD5,
        0x04,
        0xDE,
        0x8D,
        0x3F
    ];

    for wave {
        gb.mem[IO_WAV + it_index] = it;
    }
}
