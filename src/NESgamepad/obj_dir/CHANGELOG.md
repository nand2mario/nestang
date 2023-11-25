ToDo:
- Test physical gamepad
- Not sure if DIVIDER_EXPONENT is accurate
    - Where does it come from?
- Simplify logic

[14.11.2023]
- Remove log2 helper function
- Latch signal duration ~12uS
- Change how button__state is latched
- Add data_available signal
- Change cycle_stage to be a bit shifter (though it takes more bits)
- Improve Verilator test