#!/bin/sh
set -e
yosys run_yosys.ys
edif2ngd ddr3_memory_controller.edif
ngdbuild ddr3_memory_controller -uc ddr3_memory_controller.ucf -p xc6slx9csg324-3
map -w ddr3_memory_controller
par -w ddr3_memory_controller.ncd ddr3_memory_controller_par.ncd
bitgen -w ddr3_memory_controller_par.ncd -g StartupClk:JTAGClk
