onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/reset_n
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/ck
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/ck_en
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/cs_n
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/ras_n
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/cas_n
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/odt
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/address
add wave -noupdate -radix hexadecimal /test_ddr3_memory_controller/ddr3_control/bank_address
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/we_n
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/dqs_counter
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/dqs_n_phase_shifted
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/ldqs
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/udqs
add wave -noupdate -radix hexadecimal /test_ddr3_memory_controller/ddr3_control/dq
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/ldm
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/udm
add wave -noupdate -radix unsigned /test_ddr3_memory_controller/ddr3_control/main_state
add wave -noupdate -radix hexadecimal /test_ddr3_memory_controller/data_from_ram
add wave -noupdate /test_ddr3_memory_controller/read_enable
add wave -noupdate /test_ddr3_memory_controller/done_reading
add wave -noupdate /test_ddr3_memory_controller/ddr3_control/MPR_ENABLE
add wave -noupdate -radix unsigned /test_ddr3_memory_controller/ddr3_control/previous_main_state
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {702147057 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 345
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {701996273 ps} {702154993 ps}
