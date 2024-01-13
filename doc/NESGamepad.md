
# Original NES Gamepad Setup

NESTang since 0.9(check with @nand2mario) supports Original NES Gamepads (only player 1 right now), also supporting 8BitDo gamepads.

## Requirements

- An original NES Gamepad
- Wires
- [4 Channels IIC I2C Logic Level Shifter Bi-Directional Module](https://www.aliexpress.com/item/1005004225321778.html?spm=a2g0o.order_list.order_list_main.27.22111802nFvcM9)
    - This is needed because NESTang has Low Voltage CMOS 3.3V signals and NES Gamepad uses 5V TTL logic.

## Wiring diagram

<img src="images/NESGamepad_wiring.png" width=400>

