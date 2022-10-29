#include <cstdio>
#include <SDL.h>

#include "VNES_Tang20k.h"
#include "VNES_Tang20k_NES_Tang20k.h"
#include "VNES_Tang20k_NES.h"
#include "verilated.h"
#include <verilated_vcd_c.h>
#include "nes_palette.h"

// #define TRACE_ON

// See: https://projectf.io/posts/verilog-sim-verilator-sdl/
const int H_RES = 256;
const int V_RES = 240;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

Pixel screenbuffer[H_RES*V_RES];

// 10 million clock cycles
// #define MAX_SIM_TIME 10000000LL
#define MAX_SIM_TIME 100000000LL
vluint64_t sim_time;
int main(int argc, char** argv, char** env) {
	Verilated::commandArgs(argc, argv);
	VNES_Tang20k* top = new VNES_Tang20k;
	// VNES_Tang20k_NES_Tang20k *nes_tang20k = top->NES_Tang20k;
	VNES_Tang20k_NES *nes = top->NES_Tang20k->nes;
	bool frame_updated = false;
	uint64_t start_ticks = SDL_GetPerformanceCounter();
	int frame_count = 0;

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    sdl_window = SDL_CreateWindow("NESTang", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_RES*2, V_RES*2, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }
    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        printf("Renderer creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET, H_RES, V_RES);
    if (!sdl_texture) {
        printf("Texture creation failed: %s\n", SDL_GetError());
        return 1;
    }

#ifdef TRACE_ON
	Verilated::traceEverOn(true);
	VerilatedVcdC *m_trace = new VerilatedVcdC;
	top->trace(m_trace, 5);
    m_trace->open("waveform.vcd");
#endif

	while (1) {
		top->sys_resetn = 1;
		if(sim_time > 1 && sim_time < 5){
			top->sys_resetn = 0;
		}
		top->sys_clk ^= 1;
		top->eval(); 
#ifdef TRACE_ON
		m_trace->dump(sim_time);
#endif

		if (nes->scanline >= 0 && nes->scanline < 240 && nes->cycle >= 0 && nes->cycle <= 256) {
			Pixel* p = &screenbuffer[nes->scanline*H_RES + nes->cycle];
			int color = nes->color;
			p->a = 0xFF;  // transparency
			p->r = (NES_PALETTE[color] >> 16) & 0xff;
			p->g = (NES_PALETTE[color] >> 8) & 0xff;
			p->b = NES_PALETTE[color] & 0xff;;
		}		

		// update texture once per frame (in blanking)
		if (nes->scanline == V_RES && nes->cycle == 0) {
			if (!frame_updated) {
				// check for quit event
				SDL_Event e;
				if (SDL_PollEvent(&e)) {
					if (e.type == SDL_QUIT) {
						break;
					}
				}
				frame_updated = true;
				SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES*sizeof(Pixel));
				SDL_RenderClear(sdl_renderer);
				SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
				SDL_RenderPresent(sdl_renderer);
				frame_count++;				

				if (frame_count % 10 == 0)
					printf("Frame #%d\n", frame_count);
			}
		} else
			frame_updated = false;

		sim_time++;
	}	
#ifdef TRACE_ON
	m_trace->close();
#endif
	delete top;

    // calculate frame rate
    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f\n", fps);	

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();

	return 0;
}
