# DDR
A simple DDR3 memory controller for [Micron DDR3 RAM](https://www.micron.com/products/dram/ddr3-sdram/part-catalog/mt41j128m16jt-125)

TODO:
1. Debug the low-speed waveform when the DDR3 FPGA board arrives.
2. Implement more functionalities since the current verilog code does not yet support Additive Latency (AL), write-leveling mode, self-refresh mode, issuing of multiple consecutive `ACT` commands, standalone precharge (non-`AP`) command
3. Implement [Type-III digital PLL described in Floyd Gardner book: Phaselock Techniques, 3rd Edition](https://www.reddit.com/r/AskElectronics/comments/9i7g9j/loop_stability_of_type_3_digital_pll/) for high-speed application and `DQS` phase-shift purpose
4. Investigate high-speed DDR PHY IO as described in reference \[1\], [2], [3], [4], [5]
5. Design my own DDR3 FPGA board

Notes on Modelsim simulation for Micron DDR3 memory simulation model:
1. Creates a working directory named as `ddr3` and copies `ddr3.v`, `ddr3_memory_controller.v`, `test_ddr3_memory_controller.v`, `2048Mb_ddr3_parameters.vh`
2. `vsim -gui work._2048Mb_ddr3_parameters_vh_unit work.ddr3 work.ddr3_memory_controller work.ddr3_memory_controller_v_unit work.test_ddr3_memory_controller`
3. Inside Modelsim, open `vsim.wlf` file and then `add wave -r *`

Credit: [@Morin](https://github.com/MartinGeisse) and [@Greg](https://github.com/gregdavill/) for their helpful technical help and explanation

Reference:

\[1]: [Preamble detection and postamble closure for a memory interface controller](https://patents.google.com/patent/US8023342)

\[2]: [Circuit design technique for DQS enable/disable calibration](https://patents.google.com/patent/US9158873)

\[3]: [Dqs generating circuit in a ddr memory device and method of generating the dqs](https://patents.google.com/patent/KR20050101864A/en)

\[4]: [DQS strobe centering (data eye training) method](https://patents.google.com/patent/US7443741B2/en)

\[5]: [Data strobe enable circuitry ](https://patents.google.com/patent/US9001595)
