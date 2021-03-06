# Config Bus Input Timing Constraints
set_input_delay -clock cfg_clk -max 8.000 [get_ports {cfgd[*]}]
set_input_delay -clock cfg_clk -min 2.000 [get_ports {cfgd[*]}]
set_input_delay -clock cfg_clk -max 8.000 [get_ports cfg_rdy]
set_input_delay -clock cfg_clk -min 2.000 [get_ports cfg_rdy]
set_input_delay -clock cfg_clk -max 8.000 [get_ports cfg_act]
set_input_delay -clock cfg_clk -min 2.000 [get_ports cfg_act]
set_input_delay -clock cfg_clk -max 8.000 [get_ports cfg_err]
set_input_delay -clock cfg_clk -min 2.000 [get_ports cfg_err]

# Config Bus Output Timing Constraints
# -max values are used for setup time.  2ns output_delay sets a Tco max of 8ns, since it is a 10ns cycle
# -min values are used for hold timing.  -1ns indicates that the actual output hold time requirement is 1ns
set_output_delay -clock cfg_clk -max 2.000 [get_ports {cfgd[*]}]
set_output_delay -clock cfg_clk -max 2.000 [get_ports fpga_cmdl]
set_output_delay -clock cfg_clk -max 2.000 [get_ports fpga_rdyl]
set_output_delay -clock cfg_clk -max 2.000 [get_ports stat_oel]
set_output_delay -clock cfg_clk -min -1.000 [get_ports {cfgd[*]}]
set_output_delay -clock cfg_clk -min -1.000 [get_ports fpga_cmdl]
set_output_delay -clock cfg_clk -min -1.000 [get_ports fpga_rdyl]
set_output_delay -clock cfg_clk -min -1.000 [get_ports stat_oel]

#MGT reference clock
create_clock -period 8.000 -name sfp_mgt_clkp -waveform {0.000 4.000} [get_ports {sfp_mgt_clkp}]

# Define 100 MHz clock on Aux SATA input
create_clock -period 10.000 -name TAUX_CLK -waveform {0.000 5.000} [get_pins TIL1/SIN1/O]

# We skew cfg_clk for the ApsMsgProc (clk_100MHz_skewed_cfg_clk_mmcm) by 2ns, so we need to add a multicycle path
# constraint so that Vivado will examine the clock edge at 11ns
set_multicycle_path 2 -setup -from [get_clocks cfg_clk] -to [get_clocks clk_100MHz_skewed_CCLK_MMCM]

# Disable checking on OE timing since it is enabled more than one clock ahead of using the data
set_false_path -from [get_cells main_bd_inst/CPLD_bridge_0/U0/apsmsgproc_wrapper_inst/msgproc_impl.AMP1/ACP1/CFG1/ExtOE] -to [get_ports {cfgd[*]}]
set_false_path -to [get_ports stat_oel]

# Becuase we have no visibility into ApsMsgProc clock-crossing just assume set_max_delay is enough
set clk_axi [get_clocks -of_objects [get_pins cfg_clk_mmcm_inst/clk_100MHz]]
set clk_cfg_skewed [get_clocks -of_objects [get_pins cfg_clk_mmcm_inst/clk_100MHz_skewed]]
set_max_delay -datapath_only -from $clk_axi -to $clk_cfg_skewed [get_property -min PERIOD $clk_axi]
set_max_delay -datapath_only -from $clk_cfg_skewed -to $clk_axi [get_property -min PERIOD $clk_cfg_skewed]

# can only have one input clock to SYS_MMCM at a time
set_clock_groups -physically_exclusive -group [get_clocks -include_generated_clocks -of_objects [get_pins sys_mmcm_inst/REF_125MHZ_IN]] -group [get_clocks -include_generated_clocks -of_objects [get_pins sys_mmcm_inst/CLK_125MHZ_IN]]

# only look at one possible timing for the 125 MHz clock mux into the sys_clk_mmcm
# see https://www.xilinx.com/support/answers/56271.html
# and https://forums.xilinx.com/t5/Timing-Analysis/Vivado-Timing-Issue-When-Using-MMCM-With-2-Input-Clocks/td-p/422597
set_case_analysis 1 [get_pins sys_mmcm_inst/CLK_IN_SEL]

# dedicated clock routing for 10MHz reference clock
# because it feeds another one
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets ref_mmmc_inst/inst/CLK_REF_REF_MMCM]

# Don't care about output timing on these signals
set_false_path -to [get_ports {dbg[*]}]
set_false_path -to [get_ports {led[*]}]

# MAC and IPv4 address are updated once so don't worry about CDC
set_false_path -through [get_pins main_bd_inst/com5402_wrapper_0/mac_addr[*]]
set_false_path -through [get_pins main_bd_inst/com5402_wrapper_0/IPv4_addr[*]]

# CSR registers are slow
set csr_regs [get_cells main_bd_inst/TDM_CSR_0/U0/regs_reg[*][*]]
set csr_reg_clk [get_clocks -of_objects $csr_regs]
set_max_delay -datapath_only -from $csr_regs [get_property PERIOD $csr_reg_clk]
set_false_path -from [get_clocks -filter "NAME != $csr_reg_clk"] -to $csr_regs
