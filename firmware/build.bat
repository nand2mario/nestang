
@REM This compiles the firmware into firmware.bin in RV32I format.
@REM It is to be loaded at address 0.

@REM Download RISC-V gcc toolchain for x64 from https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/
set CROSS=D:\opt\xpack-riscv-none-elf-gcc-13.2.0-2\bin\riscv-none-elf-
set CFLAGS=-O -mabi=ilp32 -march=rv32i -ffreestanding

%CROSS%as -mabi=ilp32 -march=rv32i -c -o start.o start.S
%CROSS%gcc %CFLAGS% -c -o firmware.o firmware.c
%CROSS%gcc %CFLAGS% -c -o picorv32.o picorv32.c
%CROSS%gcc %CFLAGS% -c -o spi_sd.o spi_sd.c

@REM fatfs
%CROSS%gcc %CFLAGS% -c -o fatfs\diskio.o fatfs\diskio.c
%CROSS%gcc %CFLAGS% -c -o fatfs\ff.o fatfs\ff.c
%CROSS%gcc %CFLAGS% -c -o fatfs\ffunicode.o fatfs\ffunicode.c

%CROSS%gcc %CFLAGS% -Wl,--build-id=none,-Bstatic,-T,baremetal.ld,--strip-debug ^
   -nostdlib -o firmware.elf start.o firmware.o picorv32.o spi_sd.o ^
   fatfs\diskio.o fatfs\ff.o fatfs\ffunicode.o -lgcc

%CROSS%objcopy firmware.elf firmware.bin -O binary
@REM python bin2hexwords.py firmware.bin firmware.hex

%CROSS%objdump -Mnumeric -D firmware.elf > firmware.elf.list
