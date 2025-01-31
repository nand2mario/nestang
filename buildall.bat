
@echo off
set GWSH=..\..\Gowin_V1.9.9_x64\IDE\bin\gw_sh
set GWSH_NEW=..\..\Gowin_V1.9.10.03_x64\IDE\bin\gw_sh

echo. 
echo ============ Building nano20k ===============
echo.
%GWSH% build.tcl nano20k

echo.
echo ============ Building primer25k with snes/nes controller ===============
echo.
%GWSH% build.tcl primer25k snes

echo.
echo ============ Building primer25k with ds2 controller ===============
echo.
%GWSH% build.tcl primer25k ds2

echo.
echo ============ Building mega60k with ds2 controller ===============
echo.
%GWSH_NEW% build.tcl mega60k ds2

echo.
echo ============ Building console60k with ds2 controller ===============
echo.
%GWSH_NEW% build.tcl console60k ds2

dir impl\pnr\*.fs

echo "All done."

