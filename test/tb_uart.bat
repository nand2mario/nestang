@echo off
echo Compiling UART testbench...
iverilog -g2012 -o tb_uart -I ../src/sys ../src/sys/uart_tx.v ../src/sys/uart_rx.v tb_uart.v
if errorlevel 1 (
    echo Error: Compilation failed
    exit /b 1
)

echo Running simulation...
vvp tb_uart

if errorlevel 1 (
    echo Error: Simulation failed
    exit /b 1
)

echo Testbench completed successfully 