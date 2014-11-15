-- ApsControl.vhd
--
-- This instantiates the Xilinx MAC and PCS/PMA logic and connects it to the Host Logic
--
--
-- REVISIONS
--
-- 7/9/2013  CRJ
--   Created
--
-- 8/13/2013 CRJ
--   Initial release
--
-- 1/8/2014 CRJ
--   Changed to active low LEDs
--
-- 1/30/2014 CRJ
--   Added debug record
--
-- END REVISIONS
--

library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ApsControl is
port
(
  -- asynchronous reset
  RESET          : in  std_logic;

  -- Clocks
  CLK_200MHZ     : in   std_logic;  -- Free Running Control Clock.  Required for MGTP initialization
  CLK_125MHZ     : out  std_logic;  -- 125 MHz MGTP synchronous clock available for user code

  -- MGTP Connections
  gtrefclk_p     : in std_logic;    -- 125 MHz reference
  gtrefclk_n     : in std_logic;
  txp            : out std_logic;   -- TX out to SFP
  txn            : out std_logic;
  rxp            : in std_logic;    -- RX in from SPF
  rxn            : in std_logic;

  -- Config Bus Connections
  CFG_CLK        : in  STD_LOGIC;  -- 100 MHZ clock from the Config CPLD
  CFGD           : inout std_logic_vector(15 downto 0);  -- Config Data bus from CPLD
  FPGA_CMDL      : out  STD_LOGIC;  -- Command strobe from FPGA
  FPGA_RDYL      : out  STD_LOGIC;  -- Ready Strobe from FPGA
  CFG_RDY        : in  STD_LOGIC;  -- Ready to complete current transfer
  CFG_ERR        : in  STD_LOGIC;  -- Error during current command
  CFG_ACT        : in  STD_LOGIC;  -- Current transaction is complete
  STAT_OEL       : out std_logic; -- Enable CPLD to drive status onto CFGD

  -- User Logic Connections
  USER_CLK       : in std_logic;                      -- Clock for User side of FIFO interface
  USER_RST       : out std_logic;                     -- User Logic global reset, synchronous to USER_CLK
  USER_VERSION   : in std_logic_vector(31 downto 0);  -- User Logic Firmware Version.  Passed back in status packets
  USER_STATUS    : in std_logic_vector(31 downto 0);  -- User Status Word.  Passed back in status packets

  USER_CIF_EMPTY : out std_logic;                     -- Low when there is data available
  USER_DIF       : out std_logic_vector(31 downto 0); -- User Data Input FIFO output
  USER_DIF_RD    : in std_logic;                      -- User Data Onput FIFO Read Enable

  USER_CIF_RD    : in std_logic;                      -- Command Input FIFO Read Enable
  USER_CIF_RW    : out std_logic;                     -- High for read, low for write
  USER_CIF_MODE  : out std_logic_vector(7 downto 0);  -- MODE field from current User I/O command
  USER_CIF_CNT   : out std_logic_vector(15 downto 0); -- CNT field from current User I/O command
  USER_CIF_ADDR  : out std_logic_vector(31 downto 0);   -- Address for the current command

  USER_DOF       : in std_logic_vector(31 downto 0);  -- User Data Onput FIFO input
  USER_DOF_WR    : in std_logic;                      -- User Data Onput FIFO Write Enable

  USER_COF_STAT  : in std_logic_vector(7 downto 0);   -- STAT value to return for current User I/O command
  USER_COF_CNT   : in std_logic_vector(15 downto 0);  -- Number of words written to DOF for current User I/O command
  USER_COF_AFULL : out std_logic;                     -- User Control Output FIFO Almost Full
  USER_COF_WR    : in std_logic;                      -- User Control Onput FIFO Write Enable

  STATUS         : out std_logic_vector(4 downto 0)
);
end ApsControl;


architecture behavior of ApsControl is


component ApsMsgProc
port
(
  -- Interface to MAC to get Ethernet packets
  MAC_CLK       : in std_logic;                             -- Clock for command FIFO interface
  RESET         : in std_logic;                             -- Reset for Command Interface

  MAC_RXD       : in std_logic_vector(7 downto 0);  -- Data read from input FIFO
  MAC_RX_VALID  : in std_logic;                     -- Set when input fifo empty
  MAC_RX_EOP    : in std_logic;                     -- Marks the end of a receive packet in Ethernet RX FIFO
  MAC_BAD_FCS   : in std_logic;                     -- Set during EOP/VALID received packet had CRC error

  MAC_TXD       : out std_logic_vector(7 downto 0); -- Data to write to output FIFO
  MAC_TX_RDY    : in std_logic;                     -- Set when MAC can accept data
  MAC_TX_VALID  : out std_logic;                    -- Set to write the Ethernet TX FIFO
  MAC_TX_EOP    : out std_logic;                    -- Marks the end of a transmit packet to the Ethernet TX FIFO

  -- Non-volatile Data
  NV_DATA       : out std_logic_vector(63 downto 0);  -- NV Data from Multicast Address Words
  MAC_ADDRESS   : out std_logic_vector(47 downto 0);  -- MAC Address from EPROM

  -- Board Type
  BOARD_TYPE    : in std_logic_vector(7 downto 0) := x"00";    -- Board type returned in D<31:24> of Host firmware version, default to APS.  0x01 = Trigger
  
  -- User Logic Connections
  USER_CLK       : in std_logic;                      -- Clock for User side of FIFO interface
  USER_RST       : out std_logic;                     -- User Logic global reset, synchronous to USER_CLK
  USER_VERSION   : in std_logic_vector(31 downto 0);  -- User Logic Firmware Version.  Passed back in status packets
  USER_STATUS    : in std_logic_vector(31 downto 0);  -- User Status Word.  Passed back in status packets

  USER_DIF       : out std_logic_vector(31 downto 0); -- User Data Input FIFO output
  USER_DIF_RD    : in std_logic;                      -- User Data Onput FIFO Read Enable

  USER_CIF_EMPTY : out std_logic;                     -- Low when there is data available
  USER_CIF_RD    : in std_logic;                      -- Command Input FIFO Read Enable
  USER_CIF_RW    : out std_logic;                     -- High for read, low for write
  USER_CIF_MODE  : out std_logic_vector(7 downto 0);  -- MODE field from current User I/O command
  USER_CIF_CNT   : out std_logic_vector(15 downto 0); -- CNT field from current User I/O command
  USER_CIF_ADDR  : out std_logic_vector(31 downto 0); -- Address for the current command

  USER_DOF       : in std_logic_vector(31 downto 0);  -- User Data Onput FIFO input
  USER_DOF_WR    : in std_logic;                      -- User Data Onput FIFO Write Enable

  USER_COF_STAT  : in std_logic_vector(7 downto 0);   -- STAT value to return for current User I/O command
  USER_COF_CNT   : in std_logic_vector(15 downto 0);  -- Number of words written to DOF for current User I/O command
  USER_COF_AFULL : out std_logic;                     -- User Control Output FIFO Almost Full
  USER_COF_WR    : in std_logic;                       -- User Control Onput FIFO Write Enable

  -- Config CPLD Data Bus for reading status when STAT_OE is asserted
  CFG_CLK    : in  STD_LOGIC;  -- 100 MHZ clock from the Config CPLD
  CFGD       : inout std_logic_vector(15 downto 0);  -- Config Data bus from CPLD
  FPGA_CMDL  : out  STD_LOGIC;  -- Command strobe from FPGA
  FPGA_RDYL  : out  STD_LOGIC;  -- Ready Strobe from FPGA
  CFG_RDY    : in  STD_LOGIC;  -- Ready to complete current transfer
  CFG_ERR    : in  STD_LOGIC;  -- Error during current command
  CFG_ACT    : in  STD_LOGIC;  -- Current transaction is complete
  STAT_OEL   : out std_logic; -- Enable CPLD to drive status onto CFGD

  -- Status to top level
  GOOD_TOGGLE   : out std_logic;
  BAD_TOGGLE    : out std_logic
);
end component;

ATTRIBUTE SYN_BLACK_BOX : BOOLEAN;
ATTRIBUTE BLACK_BOX_PAD_PIN : STRING;

COMPONENT SFP_GIGE
    PORT (
      gtrefclk_p : IN STD_LOGIC;
      gtrefclk_n : IN STD_LOGIC;
      gtrefclk_out : OUT STD_LOGIC;
      txn : OUT STD_LOGIC;
      txp : OUT STD_LOGIC;
      rxn : IN STD_LOGIC;
      rxp : IN STD_LOGIC;
      independent_clock_bufg : IN STD_LOGIC;
      userclk_out : OUT STD_LOGIC;
      userclk2_out : OUT STD_LOGIC;
      rxuserclk_out : OUT STD_LOGIC;
      rxuserclk2_out : OUT STD_LOGIC;
      resetdone : OUT STD_LOGIC;
      pma_reset_out : OUT STD_LOGIC;
      mmcm_locked_out : OUT STD_LOGIC;
      gmii_txd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      gmii_tx_en : IN STD_LOGIC;
      gmii_tx_er : IN STD_LOGIC;
      gmii_rxd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      gmii_rx_dv : OUT STD_LOGIC;
      gmii_rx_er : OUT STD_LOGIC;
      gmii_isolate : OUT STD_LOGIC;
      configuration_vector : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
      an_interrupt : OUT STD_LOGIC;
      an_adv_config_vector : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      an_restart_config : IN STD_LOGIC;
      status_vector : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
      reset : IN STD_LOGIC;
      signal_detect : IN STD_LOGIC;
      gt0_pll0outclk_out : OUT STD_LOGIC;
      gt0_pll0outrefclk_out : OUT STD_LOGIC;
      gt0_pll1outclk_out : OUT STD_LOGIC;
      gt0_pll1outrefclk_out : OUT STD_LOGIC;
      gt0_pll0lock_out : OUT STD_LOGIC;
      gt0_pll0refclklost_out : OUT STD_LOGIC
    );
  END COMPONENT;
  ATTRIBUTE SYN_BLACK_BOX OF SFP_GIGE : COMPONENT IS TRUE;
  ATTRIBUTE BLACK_BOX_PAD_PIN OF SFP_GIGE : COMPONENT IS "gtrefclk_p,gtrefclk_n,gtrefclk_out,txn,txp,rxn,rxp,independent_clock_bufg,userclk_out,userclk2_out,rxuserclk_out,rxuserclk2_out,resetdone,pma_reset_out,mmcm_locked_out,gmii_txd[7:0],gmii_tx_en,gmii_tx_er,gmii_rxd[7:0],gmii_rx_dv,gmii_rx_er,gmii_isolate,configuration_vector[4:0],an_interrupt,an_adv_config_vector[15:0],an_restart_config,status_vector[15:0],reset,signal_detect,gt0_pll0outclk_out,gt0_pll0outrefclk_out,gt0_pll1outclk_out,gt0_pll1outrefclk_out,gt0_pll0lock_out,gt0_pll0refclklost_out";


  COMPONENT GIGE_MAC
    PORT (
      gtx_clk : IN STD_LOGIC;
      glbl_rstn : IN STD_LOGIC;
      rx_axi_rstn : IN STD_LOGIC;
      tx_axi_rstn : IN STD_LOGIC;
      rx_statistics_vector : OUT STD_LOGIC_VECTOR(27 DOWNTO 0);
      rx_statistics_valid : OUT STD_LOGIC;
      rx_mac_aclk : OUT STD_LOGIC;
      rx_reset : OUT STD_LOGIC;
      rx_axis_mac_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      rx_axis_mac_tvalid : OUT STD_LOGIC;
      rx_axis_mac_tlast : OUT STD_LOGIC;
      rx_axis_mac_tuser : OUT STD_LOGIC;
      tx_ifg_delay : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      tx_statistics_vector : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      tx_statistics_valid : OUT STD_LOGIC;
      tx_mac_aclk : OUT STD_LOGIC;
      tx_reset : OUT STD_LOGIC;
      tx_axis_mac_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      tx_axis_mac_tvalid : IN STD_LOGIC;
      tx_axis_mac_tlast : IN STD_LOGIC;
      tx_axis_mac_tuser : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      tx_axis_mac_tready : OUT STD_LOGIC;
      pause_req : IN STD_LOGIC;
      pause_val : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      speedis100 : OUT STD_LOGIC;
      speedis10100 : OUT STD_LOGIC;
      gmii_txd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      gmii_tx_en : OUT STD_LOGIC;
      gmii_tx_er : OUT STD_LOGIC;
      gmii_rxd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      gmii_rx_dv : IN STD_LOGIC;
      gmii_rx_er : IN STD_LOGIC;
      rx_configuration_vector : IN STD_LOGIC_VECTOR(79 DOWNTO 0);
      tx_configuration_vector : IN STD_LOGIC_VECTOR(79 DOWNTO 0)
    );
  END COMPONENT;
  ATTRIBUTE SYN_BLACK_BOX OF GIGE_MAC : COMPONENT IS TRUE;
  ATTRIBUTE BLACK_BOX_PAD_PIN OF GIGE_MAC : COMPONENT IS "gtx_clk,glbl_rstn,rx_axi_rstn,tx_axi_rstn,rx_statistics_vector[27:0],rx_statistics_valid,rx_mac_aclk,rx_reset,rx_axis_mac_tdata[7:0],rx_axis_mac_tvalid,rx_axis_mac_tlast,rx_axis_mac_tuser,tx_ifg_delay[7:0],tx_statistics_vector[31:0],tx_statistics_valid,tx_mac_aclk,tx_reset,tx_axis_mac_tdata[7:0],tx_axis_mac_tvalid,tx_axis_mac_tlast,tx_axis_mac_tuser[0:0],tx_axis_mac_tready,pause_req,pause_val[15:0],speedis100,speedis10100,gmii_txd[7:0],gmii_tx_en,gmii_tx_er,gmii_rxd[7:0],gmii_rx_dv,gmii_rx_er,rx_configuration_vector[79:0],tx_configuration_vector[79:0]";


-- RX MAC Configuration Vector
signal rx_configuration_vector : std_logic_vector(79 downto 0)
       := x"0605040302DA" -- RX Pause Addr
        & x"0000"         -- Max Frame Length (zero since Max Frame is disabled)
        & '0'             -- Resv
        & '0'             -- RX Max Frame Enable
        & "10"            -- MAC Receive Speed = 1Gb
        & '1'             -- Promiscous Mode Enable
        & '0'             -- Resv
        & '0'             -- Control Frame Length Check Disable
        & '0'             -- Length/Check Check Disable
        & '0'             -- Resv
        & '0'             -- Half Duplex Enable
        & '1'             -- Inhibit Transmitter when flow control frame received
        & '0'             -- Jumbo Frame Enable
        & '0'             -- FCS In Band Enable
        & '0'             -- VLAN Receive Enable
        & '1'             -- RX Enable
        & '0';            -- RX Reset

-- TX MAC Configuration Vector
signal tx_configuration_vector : std_logic_vector(79 downto 0)
       := x"0605040302DA" -- TX Pause Addr
        & x"0000"         -- TX Max Frame Length (zero since Max Frame is disabled)
        & '0'             -- Resv
        & '0'             -- TX Max Frame Enable
        & "10"            -- MAC Transmit Speed = 1Gb
        & '0'             -- Resv
        & '0'             -- Resv
        & '0'             -- Resv
        & '0'             -- TX Interframe Gap Adjust Enable
        & '0'             -- Resv
        & '0'             -- Half Duplex Enable
        & '1'             -- Enable sending Pause Frames when Pause asserted
        & '0'             -- Jumbo Frame Enable
        & '0'             -- FCS In Band Enable
        & '0'             -- VLAN Frame Transmit Enable
        & '1'             -- TX Enable
        & '0';            -- TX Reset

-- clock generation signals for tranceiver
signal gtrefclk              : std_logic;                    -- Route gtrefclk through an IBUFG.
signal resetdone             : std_logic;                    -- To indicate that the GT transceiver has completed its reset cycle
signal mmcm_locked           : std_logic;                    -- MMCM locked signal.
signal mmcm_reset            : std_logic;                    -- MMCM reset signal.
signal clkfbout              : std_logic;                    -- MMCM feedback clock
signal clkout0               : std_logic;                    -- MMCM clock0 output (62.5MHz).
signal clkout1               : std_logic;                    -- MMCM clock1 output (125MHz).
signal userclk               : std_logic;                    -- 62.5MHz clock for GT transceiver Tx/Rx user clocks
signal userclk2              : std_logic;                    -- 125MHz clock for core reference clock.

-- GMII signals
signal gmii_isolate          : std_logic;                    -- Internal gmii_isolate signal.
signal gmii_txd_int          : std_logic_vector(7 downto 0); -- Internal gmii_txd signal.
signal gmii_tx_en_int        : std_logic;                    -- Internal gmii_tx_en signal.
signal gmii_tx_er_int        : std_logic;                    -- Internal gmii_tx_er signal.
signal gmii_rxd_int          : std_logic_vector(7 downto 0); -- Internal gmii_rxd signal.
signal gmii_rx_dv_int        : std_logic;                    -- Internal gmii_rx_dv signal.
signal gmii_rx_er_int        : std_logic;                    -- Internal gmii_rx_er signal.

-- Extra registers to ease IOB placement
signal status_vector_int : std_logic_vector(15 downto 0);

signal configuration_vector : std_logic_vector(4 downto 0) := "10000";  -- Enable Auto Negotiation See table 12-37 of UG155.
signal an_interrupt         : std_logic;                    -- Interrupt to processor to signal that Auto-Negotiation has completed
signal an_adv_config_vector : std_logic_vector(15 downto 0) := x"0020"; -- Alternate interface to program REG4 (AN ADV)
signal an_restart_config    : std_logic := '0';                     -- Alternate signal to modify AN restart bit in REG0
signal link_timer_value     : std_logic_vector(8 downto 0) := "100000000";  -- Programmable Auto-Negotiation Link Timer Control

--Fake MAC signals for injected UDP interface
signal MAC_RXD_trimac       : std_logic_vector(7 downto 0) := (others => '0');
signal MAC_RX_VALID_trimac  : std_logic := '0';
signal MAC_RX_EOP_trimac    : std_logic := '0';
signal MAC_BAD_FCS_trimac   : std_logic := '0';

signal MAC_TXD_trimac       : std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_RDY_trimac    : std_logic := '0';
signal MAC_TX_VALID_trimac  : std_logic := '0';
signal MAC_TX_EOP_trimac    : std_logic := '0';

signal MAC_RXD_msgproc : std_logic_vector(7 downto 0) := (others => '0');
signal MAC_RX_VALID_msgproc  : std_logic := '0';
signal MAC_RX_EOP_msgproc    : std_logic := '0';
signal MAC_BAD_FCS_msgproc   : std_logic := '0';

signal MAC_TXD_msgproc : std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_RDY_msgproc : std_logic := '0';
signal MAC_TX_VALID_msgproc : std_logic := '0';
signal MAC_TX_EOP_msgproc : std_logic := '0';


 ------------------------------------------------------------------------------
 -- internal signals used in this top level wrapper.
 ------------------------------------------------------------------------------

-- example design clocks
signal gtx_clk_bufg                       : std_logic;
signal rx_mac_aclk                        : std_logic;
signal tx_mac_aclk                        : std_logic;

-- RX Statistics serialisation signals
signal rx_statistics_valid                : std_logic;
signal rx_statistics_valid_reg            : std_logic;
signal rx_statistics_vector               : std_logic_vector(27 downto 0);

-- TX Statistics serialisation signals
signal tx_statistics_valid                : std_logic;
signal tx_statistics_valid_reg            : std_logic;
signal tx_statistics_vector               : std_logic_vector(31 downto 0);

-- MAC receiver client I/F
signal rx_axis_mac_tdata    : std_logic_vector(7 downto 0);
signal rx_axis_mac_tvalid   : std_logic;
signal rx_axis_mac_tlast    : std_logic;
signal rx_axis_mac_tuser    : std_logic;

-- MAC transmitter client I/F
signal tx_axis_mac_tdata    : std_logic_vector(7 downto 0);
signal tx_axis_mac_tvalid   : std_logic;
signal tx_axis_mac_tready   : std_logic;
signal tx_axis_mac_tlast    : std_logic;
signal tx_axis_mac_tuser    : std_logic_vector(0 downto 0);

signal GoodToggle : std_logic;
signal BadToggle : std_logic;

signal NV_DATA : std_logic_vector(63 downto 0);
signal ip_addr : std_logic_vector(31 downto 0) := x"c0a80102"; -- 192.168.1.2 default address
signal mac_addr : std_logic_vector(47 downto 0) := x"4651DB112233"; -- BBN OUI is 44-51-DB -> 46-51-DB for locally administered

begin

  -- Send 125 MHz GTP clock up for user code to potentialy use
  CLK_125MHZ <= userclk2;

  -- Status signals
  STATUS(0) <= GoodToggle;
  STATUS(1) <= BadToggle;
  STATUS(2) <= status_vector_int(0);  -- High when link is established
  STATUS(3) <= (MAC_RX_VALID_trimac or MAC_TX_VALID_trimac);
  STATUS(4) <= (MAC_RX_VALID_msgproc or MAC_TX_VALID_msgproc);

  ip_addr <= NV_DATA(63 downto 32);
  -- ip_addr <= x"c0a80505";

  -----------------------------------------------------------------------------
  -- Transceiver PMA reset circuitry
  -----------------------------------------------------------------------------

  -- GIGE PCS/PMA attached to the AC701 SFP Port
  core_wrapper : SFP_GIGE
  port map
  (
    gtrefclk_p          => gtrefclk_p,
    gtrefclk_n          => gtrefclk_n,
    txp                  => txp,
    txn                  => txn,
    rxp                  => rxp,
    rxn                  => rxn,
    independent_clock_bufg => CLK_200MHZ,
    userclk_out          => userclk,
    userclk2_out         => userclk2,

    -- Connect to the GMII on the MAC
    gmii_txd             => gmii_txd_int,
    gmii_tx_en           => gmii_tx_en_int,
    gmii_tx_er           => gmii_tx_er_int,
    gmii_rxd             => gmii_rxd_int,
    gmii_rx_dv           => gmii_rx_dv_int,
    gmii_rx_er           => gmii_rx_er_int,
    gmii_isolate         => gmii_isolate,

    configuration_vector => configuration_vector,
    an_interrupt         => an_interrupt,
    an_adv_config_vector => an_adv_config_vector,
    an_restart_config    => an_restart_config,
    status_vector        => status_vector_int,
    reset                => RESET,
    signal_detect        => '1'  -- SFP SERDES port is always active
  );

  ------------------------------------------------------------------------------
  -- Instantiate the Tri-Mode EMAC Block wrapper
  ------------------------------------------------------------------------------
  trimac_block : GIGE_MAC
  port map
  (
    gtx_clk               => userclk2,

    -- asynchronous reset
    glbl_rstn             => "not"(RESET),
    rx_axi_rstn           => '1',  -- separate RX reset
    tx_axi_rstn           => '1',  -- separate TX reset

    -- Client Receiver Interface
    rx_statistics_vector  => open ,
    rx_statistics_valid   => open ,
    tx_statistics_vector  => open ,
    tx_statistics_valid   => open ,

    -- AXI Stream Receive Data from MAC
    rx_mac_aclk           => open ,  -- driven by gtx_clk internal to the logic
    rx_reset              => open,  -- Output
    rx_axis_mac_tdata     => MAC_RXD_trimac,
    rx_axis_mac_tvalid    => MAC_RX_VALID_trimac,
    rx_axis_mac_tlast     => MAC_RX_EOP_trimac,
    rx_axis_mac_tuser     => MAC_BAD_FCS_trimac,  -- Carries FCS status

    -- AXI Stream Transmit Data into MAC
    tx_mac_aclk           => open ,  -- driven by gtx_clk internal to the logic
    tx_reset              => open,  -- Output
    tx_axis_mac_tdata     => MAC_TXD_trimac ,
    tx_axis_mac_tvalid    => MAC_TX_VALID_trimac,
    tx_axis_mac_tlast     => MAC_TX_EOP_trimac,
    tx_axis_mac_tuser     => "0",  -- User to force an error in the packet
    tx_axis_mac_tready    => MAC_TX_RDY_trimac,

    -- Programmable Interframe gap.  Disabled by config vector
    tx_ifg_delay          => x"00",

    -- Flow Control
    pause_req             => '0' ,
    pause_val             => x"0000" ,

    speedis100            => open ,
    speedis10100          => open ,

    -- GMII Interface
    gmii_txd              => gmii_txd_int,
    gmii_tx_en            => gmii_tx_en_int,
    gmii_tx_er            => gmii_tx_er_int,
    gmii_rxd              => gmii_rxd_int,
    gmii_rx_dv            => gmii_rx_dv_int,
    gmii_rx_er            => gmii_rx_er_int,

    -- Hard Coded Configuration Vector
    rx_configuration_vector  => rx_configuration_vector,
    tx_configuration_vector  => tx_configuration_vector
  );


--Instantiate UDP interface
  udp: entity work.UDP_Interface
  port map (
    MAC_CLK => userclk2,
    RST =>RESET,
    --real MAC signals to/from the TRIMAC
    MAC_RXD_trimac => MAC_RXD_trimac,
    MAC_RX_VALID_trimac => MAC_RX_VALID_trimac,
    MAC_RX_EOP_trimac => MAC_RX_EOP_trimac,
    MAC_BAD_FCS_trimac => MAC_BAD_FCS_trimac,
    MAC_TXD_trimac => MAC_TXD_trimac,
    MAC_TX_RDY_trimac => MAC_TX_RDY_trimac,
    MAC_TX_VALID_trimac => MAC_TX_VALID_trimac,
    MAC_TX_EOP_trimac => MAC_TX_EOP_trimac,

  --fake MAC signals to/from the APSMsgProc
    MAC_RXD_msgproc => MAC_RXD_msgproc,
    MAC_RX_VALID_msgproc => MAC_RX_VALID_msgproc,
    MAC_RX_EOP_msgproc => MAC_RX_EOP_msgproc,
    MAC_BAD_FCS_msgproc => MAC_BAD_FCS_msgproc,
    MAC_TXD_msgproc => MAC_TXD_msgproc,
    MAC_TX_RDY_msgproc => MAC_TX_RDY_msgproc,
    MAC_TX_VALID_msgproc => MAC_TX_VALID_msgproc,
    MAC_TX_EOP_msgproc => MAC_TX_EOP_msgproc,

    --MAC and IP address
    mac_addr => mac_addr,
    ip_addr => ip_addr
  );

  -- This encapsulates all of the packet and message processing
  AMP1 : ApsMsgProc
  port map
  (
  -- Interface to MAC to get Ethernet packets
    MAC_CLK       => userclk2,
    RESET         => RESET,

    MAC_RXD       => MAC_RXD_msgproc,
    MAC_RX_VALID  => MAC_RX_VALID_msgproc,
    MAC_RX_EOP    => MAC_RX_EOP_msgproc,
    MAC_BAD_FCS   => MAC_BAD_FCS_msgproc,

    MAC_TXD       => MAC_TXD_msgproc,
    MAC_TX_RDY    => MAC_TX_RDY_msgproc,
    MAC_TX_VALID  => MAC_TX_VALID_msgproc,
    MAC_TX_EOP    => MAC_TX_EOP_msgproc,

    NV_DATA       => NV_DATA,
    MAC_ADDRESS   => mac_addr,

    -- User Logic Connections
    USER_CLK       => USER_CLK,
    USER_RST       => USER_RST,
    USER_VERSION   => USER_VERSION,
    USER_STATUS    => USER_STATUS,

    USER_DIF       => USER_DIF,
    USER_DIF_RD    => USER_DIF_RD,

    USER_CIF_EMPTY => USER_CIF_EMPTY,
    USER_CIF_RD    => USER_CIF_RD,
    USER_CIF_RW    => USER_CIF_RW,
    USER_CIF_MODE  => USER_CIF_MODE,
    USER_CIF_CNT   => USER_CIF_CNT,
    USER_CIF_ADDR  => USER_CIF_ADDR,

    USER_DOF       => USER_DOF,
    USER_DOF_WR    => USER_DOF_WR,

    USER_COF_STAT  => USER_COF_STAT,
    USER_COF_CNT   => USER_COF_CNT,
    USER_COF_AFULL => USER_COF_AFULL,
    USER_COF_WR    => USER_COF_WR,

    -- Config Bus Connections
    CFG_CLK        => CFG_CLK,
    CFGD           => CFGD,
    FPGA_CMDL      => FPGA_CMDL,
    FPGA_RDYL      => FPGA_RDYL,
    CFG_RDY        => CFG_RDY,
    CFG_ERR        => CFG_ERR,
    CFG_ACT        => CFG_ACT,
    STAT_OEL       => STAT_OEL,

    -- Status to top level
    GOOD_TOGGLE   => GoodToggle,
    BAD_TOGGLE    => BadToggle
  );

end behavior;
