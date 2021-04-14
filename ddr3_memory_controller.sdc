# Credit : 
# https://www.cnblogs.com/lelin/p/12652460.html
# https://zhuanlan.zhihu.com/p/339353879

################################ For READ operation #########################################

## operating frequency 50MHz

create_clock -period 20 -name DQS [get_ports dqs]

## positive-edge sampling delay

set_input_delay 0.4 -max -clock DQS [get_ports dq]
set_input_delay -0.4 -min -clock DQS [get_ports dq]

## negative-edge sampling delay

set_input_delay 0.35 -max -clock DQS -clock_fall [get_ports dq]
set_input_delay -0.35 -min -clock DQS -clock_fall [get_ports dq]

## launch and capture flops are of the same edge type

set_multicycle_path 0 -setup -to UFF0/D
set_multicycle_path 0 -setup -to UFF5/D


################################ For WRITE operation #########################################

## the verilog code is now using clock divider mechanism to achieve DLL 90-degree phase-shifting purpose
## As for why -edge {0 2 4} , try to imagine divide clk by 4 and count the number of positive-edges
## As for why -edge_shift {5 5 5} , it is due to (20ns / (360 degree/90 degree)) = 5ns

create_clock -period 20 [get_ports clk]
## create_generated_clock -name pre_DQS \-source clk \-divide_by 4 \[get_pins UFF1/Q]
create_generated_clock -name DQS \-source clk \-edge {0 2 4} \-edge_shift {5 5 5} \[get_ports dqs]

set_output_delay -clock DQS -max 0.25 -rise [get_ports dq]
set_output_delay -clock DQS -max 0.4 -fall [get_ports dq]
set_output_delay -clock DQS -min -0.15 -rise [get_ports dq]
set_output_delay -clock DQS -min -0.12 -fall [get_ports dq]
