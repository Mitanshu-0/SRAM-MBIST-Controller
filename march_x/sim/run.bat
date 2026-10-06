@echo off
iverilog -o tb_mbist.out -I ..\rtl -I ..\sim_models ..\tb\tb_mbist.v
if errorlevel 1 (
    echo Compilation failed.
    exit /b 1
)
vvp tb_mbist.out