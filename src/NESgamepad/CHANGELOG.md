# ToDo:
🙂

# Changelog

[29.11.2023]
- Fix first data bit being at latch state
- Fix Verilator FSM
- Remove ClockDivider module
- Get rid of end_state

[26.11.2023]
- Test physical gamepad
    - Use resistor-based LVCMOS3V3 to TTL5V signal converter
    - Use resistor-based TTL5V to LVCMOS3V3 signal converter
    - Latch signal pulled to low before 12uS needed
    - Gamepad not responding with bits
- Wrong timing, change 60Hz clock to 12uS clock
    - Use 60Hz clock to sample @16,6mS
- Add formal verification using SymbiYosis


[14.11.2023]
- Remove log2 helper function
- Latch signal duration ~12uS
- Change how button__state is latched
- Add data_available signal
- Change cycle_stage to be a bit shifter (though it takes more bits)
- Improve Verilator test