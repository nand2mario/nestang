#include "VNES_Tang20k.h"
#include "verilated.h"
#include <verilated_vcd_c.h>

// 10 million clock cycles
// #define MAX_SIM_TIME 10000000LL
#define MAX_SIM_TIME 100000000LL
vluint64_t sim_time;
int main(int argc, char** argv, char** env) {
	Verilated::commandArgs(argc, argv);
	VNES_Tang20k* top = new VNES_Tang20k;

	Verilated::traceEverOn(true);
	VerilatedVcdC *m_trace = new VerilatedVcdC;
	top->trace(m_trace, 5);
    m_trace->open("waveform.vcd");

	while (sim_time < MAX_SIM_TIME) {
		top->sys_resetn = 1;
		if(sim_time > 1 && sim_time < 5){
			top->sys_resetn = 0;
		}
		top->sys_clk ^= 1;
		top->eval(); 
		m_trace->dump(sim_time);
		sim_time++;
	}	
	m_trace->close();
	delete top;
	return 0;
}
