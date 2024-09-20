# Cheat Wizard

## Format

This new module accepts `*.cwz` binary files with the following format:

- 128 bits (16 bytes) per cheat
    - Four bytes correspond to compare enabled/disabled
    - Next 4 bytes correspond to address
    - Next 4 bytes correspond to compare value
    - Next 4 bytes correspond to replace value

Example for `Battletoads.nes`

```
00000001 00000320 00000000 00000004
00000001 000023a2 000000d6 00000024
00000001 000026b5 00000001 00000000
00000001 00004fba 00000008 0000002f
...
```

You'll need to use a hex editor to create the file.

## How to use

# Enable cheats

Navigate to `2)Options->Cheats->Cheats Enabled:` and press `A` to enable or disable.

## Load a cheat file

Navigate to `2)Options->Cheats->Load cheat file` and press `A` to open the file explorer view. Choose the `.cwz` file for your game and press `A`, you'll see the message `Cheats loaded!` if the file was correctly loaded.

After enabling cheats and loading them, you can load a `ROM` and cheats will be applied.