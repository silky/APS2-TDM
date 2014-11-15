-- AtmTop.vhd
--
-- This is the top level ATM module of the ATM test firmware.
-- It instantiates the Host Logic, the User Logic, 9 trigger outputs, and one trigger input.
-- The UserLogic is the same as for the APS II test software.
-- There are no DACs for the User Logic to control, but the DAC0 amplitude is used as a trigger output enable.
--
-- REVISIONS
--
-- 8/5/2014  CRJ
--   Created based on ApsTop
--
-- 9/03/2013 CRJ
--   Cleaned up for initial release
--
-- END REVISIONS
--


library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity AtmTop is
port
(
  REF_FPGA    : in std_logic;  -- Global 10MHz reference
  FPGA_RESETL : in  STD_LOGIC;  -- Global reset from config FPGA

  -- Temp Diode Pins
  VP_IN : in  STD_LOGIC;
  VN_IN : in  STD_LOGIC;
  
  -- Config Bus Connections
  CFG_CCLK   : in  STD_LOGIC;  -- 100 MHZ clock from the Config CPLD
  CFGD           : inout std_logic_vector(15 downto 0);  -- Config Data bus from CPLD
  FPGA_CMDL      : out  STD_LOGIC;  -- Command strobe from FPGA
  FPGA_RDYL      : out  STD_LOGIC;  -- Ready Strobe from FPGA
  CFG_RDY        : in  STD_LOGIC;  -- Ready to complete current transfer.  Connected to CFG_RDWR_B
  CFG_ERR        : in  STD_LOGIC;  -- Error during current command.  Connecte to CFG_CSI_B
  CFG_ACT        : in  STD_LOGIC;  -- Current transaction is complete
  STAT_OEL       : out std_logic; -- Enable CPLD to drive status onto CFGD

  -- SFP Tranceiver Interface
  gtrefclk_p           : in std_logic;    -- 125 MHz reference
  gtrefclk_n           : in std_logic;
  txp                  : out std_logic;   -- TX out to SFP
  txn                  : out std_logic;
  rxp                  : in std_logic;    -- RX in from SPF
  rxn                  : in std_logic;

  -- SFP Signals
  SFP_ENH    : out std_logic;
  SFP_SCL    : out std_logic;
  SFP_SDA    : in std_logic;
  SFP_FAULT  : in std_logic;
  SFP_LOS    : in std_logic;
  SFP_PRESL  : in std_logic;
  SFP_TXDIS  : out std_logic;

  -- External trigger comparator related signals
  TRG_CMPN : in std_logic_vector(7 downto 0);
  TRG_CMPP : in std_logic_vector(7 downto 0);
  THR      : out std_logic_vector(7 downto 0);

  -- Status LEDs used to display trigger input state
  LED      : out  std_logic_vector(9 downto 0);

  -- Trigger Outputs
  TRGCLK_OUTN : out std_logic_vector(8 downto 0);
  TRGCLK_OUTP : out std_logic_vector(8 downto 0);
  TRGDAT_OUTN : out std_logic_vector(8 downto 0);
  TRGDAT_OUTP : out std_logic_vector(8 downto 0);

  -- Trigger input
  TRIG_CTRLN : in std_logic_vector(1 downto 0);
  TRIG_CTRLP : in std_logic_vector(1 downto 0);

  -- Debug LEDs / configuration jumpers
  DBG            : inout  std_logic_vector(8 downto 0)
);
end AtmTop;


architecture behavior of AtmTop is

component ApsControl
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
  USER_CIF_ADDR  : out std_logic_vector(31 downto 0); -- Address for the current command

  USER_DOF       : in std_logic_vector(31 downto 0);  -- User Data Onput FIFO input
  USER_DOF_WR    : in std_logic;                      -- User Data Onput FIFO Write Enable

  USER_COF_STAT  : in std_logic_vector(7 downto 0);   -- STAT value to return for current User I/O command
  USER_COF_CNT   : in std_logic_vector(15 downto 0);  -- Number of words written to DOF for current User I/O command
  USER_COF_AFULL : out std_logic;                     -- User Control Output FIFO Almost Full
  USER_COF_WR    : in std_logic;                      -- User Control Onput FIFO Write Enable

  -- GPIO for status
  STATUS       : out  std_logic_vector(4 downto 0)
);
end component;

component ApsDacUserLogic
port
(
  -- User Logic Connections
  USER_CLK       : in std_logic;                       -- Clock for User side of FIFO interface
  USER_RST       : in std_logic;                       -- User Logic global reset, synchronous to USER_CLK
  USER_VERSION   : out std_logic_vector(31 downto 0);  -- User Logic Firmware Version.  Passed back in status packets
  USER_STATUS    : out std_logic_vector(31 downto 0);  -- User Status Word.  Passed back in status packets

  USER_DIF       : in std_logic_vector(31 downto 0);   -- User Data Input FIFO output
  USER_DIF_RD    : out std_logic;                      -- User Data Onput FIFO Read Enable

  USER_CIF_EMPTY : in std_logic;                       -- Low when there is data available
  USER_CIF_RD    : out std_logic;                      -- Command Input FIFO Read Enable
  USER_CIF_RW    : in std_logic;                       -- High for read, low for write
  USER_CIF_MODE  : in std_logic_vector(7 downto 0);   -- MODE field from current User I/O command
  USER_CIF_CNT   : in std_logic_vector(15 downto 0);   -- CNT field from current User I/O command
  USER_CIF_ADDR  : in std_logic_vector(31 downto 0);   -- Address for the current command

  USER_DOF       : out std_logic_vector(31 downto 0);  -- User Data Onput FIFO input
  USER_DOF_WR    : out std_logic;                      -- User Data Onput FIFO Write Enable

  USER_COF_STAT  : out std_logic_vector(7 downto 0);   -- STAT value to return for current User I/O command
  USER_COF_CNT   : out std_logic_vector(15 downto 0);  -- Number of words written to DOF for current User I/O command
  USER_COF_AFULL : in std_logic;                       -- User Control Output FIFO Almost Full
  USER_COF_WR    : out std_logic;                      -- User Control Onput FIFO Write Enable
  
  DAC0_WF_MODE   : out std_logic_vector(1 downto 0);   -- Channel 0 waveform mode select.  00 = DC, 01 = Square, 02 = Ramp, 03 = Exponential
  DAC0_AMPLITUDE : out std_logic_vector(13 downto 0);  -- Channel 0 amplitude for DC and Square modes
  DAC1_WF_MODE   : out std_logic_vector(1 downto 0);   -- Channel 1 waveform mode select.  00 = DC, 01 = Square, 02 = Ramp, 03 = Exponential
  DAC1_AMPLITUDE : out std_logic_vector(13 downto 0)   -- Channel 1 amplitude for DC and Square modes
);
end component;

component TriggerInLogic
port
(
  USER_CLK   : in  std_logic;  -- Clock for the output side of the FIFO
  CLK_200MHZ : in  std_logic;  -- Delay calibration clock
  RESET      : in  std_logic;  -- Asynchronous reset for the trigger logic and FIFO

  TRIG_CLKP  : in  std_logic;  -- 100MHz Serial Clock
  TRIG_CLKN  : in  std_logic;
  TRIG_DATP  : in  std_logic;  -- 800 Mbps Serial Data
  TRIG_DATN  : in  std_logic;

  TRIG_NEXT  : in  std_logic;  -- Advance the FIFO output to the next trigger, must be synchronous to USER_CLK
  
  TRIG_LOCKED : out std_logic; -- Set when locked and aligned to the received trigger clock
  TRIG_ERR   : out std_logic;  -- Set when unaligned clock received when already locked and aligned
  TRIG_RX    : out std_logic_vector(7 downto 0);  -- Current trigger value, synchronous to USER_CLK
  TRIG_OVFL  : out std_logic;  -- Set if trigger FIFO overflows, cleared by RESET, synchronous to USER_CLK
  TRIG_READY : out std_logic   -- FIFO output valid flag, set when TRIG_RX is valid, synchronous to USER_CLK
);
end component;

component TriggerOutLogic
port
(
  USER_CLK   : in  std_logic;  -- Clock for the output side of the FIFO
  
  -- These clocks are usually generated from an MMCM driven by the CFG_CCLK.
  CLK_100MHZ : in std_logic;      -- 100 MHz trigger output serial clock, must be from same MMCM as CLK_400MHZ
  CLK_400MHZ : in std_logic;      -- 400 MHz DDR serial output clock
  RESET      : in  std_logic;  -- Asynchronous reset for the trigger logic and FIFO

  TRIG_TX    : in std_logic_vector(7 downto 0);  -- Current trigger value, synchronous to USER_CLK
  TRIG_WR    : in  std_logic;   -- Write TRIG_TX to FIFO
  TRIG_AFULL : out std_logic;   -- Trigger FIFO almost full.  Asserted durng the last write

  TRIG_CLKP  : out  std_logic;  -- 100MHz Serial Clock
  TRIG_CLKN  : out  std_logic;
  TRIG_DATP  : out  std_logic;  -- 800 Mbps Serial Data
  TRIG_DATN  : out  std_logic
);
end component;

component PWMA8
port
(
   CLK : in std_logic;
   RESET : in std_logic;
   DIN : in std_logic_vector (7 downto 0) := "00000000";
   PWM_OUT : out std_logic
);
end component;

component CCLK_MMCM
port
(
  CLK_100MHZ_IN  : in     std_logic;

  -- Clock out ports
  CLK_100MHZ     : out    std_logic;
  CLK_200MHZ     : out    std_logic;
  CLK_400MHZ     : out    std_logic;

  -- Status and control signals
  RESET          : in     std_logic;
  LOCKED         : out    std_logic
);
end component;

component TEST_MMCM
port
(
  CLK_100MHZ_IN  : in     std_logic;

  -- Clock out ports
  CLK_100MHZ     : out    std_logic;
  CLK_125MHZ     : out    std_logic;

  -- Status and control signals
  RESET          : in     std_logic;
  LOCKED         : out    std_logic
);
end component;

COMPONENT TRIG_FIFO
PORT
(
  rst : IN STD_LOGIC;
  wr_clk : IN STD_LOGIC;
  rd_clk : IN STD_LOGIC;
  din : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
  wr_en : IN STD_LOGIC;
  rd_en : IN STD_LOGIC;
  dout : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
  full : OUT STD_LOGIC;
  empty : OUT STD_LOGIC;
  prog_full : OUT STD_LOGIC
);
END COMPONENT;

COMPONENT TIO_FIFO
  PORT (
    rst : IN STD_LOGIC;
    wr_clk : IN STD_LOGIC;
    rd_clk : IN STD_LOGIC;
    din : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    wr_en : IN STD_LOGIC;
    rd_en : IN STD_LOGIC;
    dout : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    full : OUT STD_LOGIC;
    empty : OUT STD_LOGIC;
    prog_full : OUT STD_LOGIC
  );
END COMPONENT;

COMPONENT XADC_TEMPERATURE
PORT
(
  di_in : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
  daddr_in : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
  den_in : IN STD_LOGIC;
  dwe_in : IN STD_LOGIC;
  drdy_out : OUT STD_LOGIC;
  do_out : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
  dclk_in : IN STD_LOGIC;
  reset_in : IN STD_LOGIC;
  vp_in : IN STD_LOGIC;
  vn_in : IN STD_LOGIC;
  channel_out : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
  eoc_out : OUT STD_LOGIC;
  alarm_out : OUT STD_LOGIC;
  eos_out : OUT STD_LOGIC;
  busy_out : OUT STD_LOGIC
);
END COMPONENT;


ATTRIBUTE SYN_BLACK_BOX : BOOLEAN;
ATTRIBUTE SYN_BLACK_BOX OF CCLK_MMCM : COMPONENT IS TRUE;
ATTRIBUTE SYN_BLACK_BOX OF TRIG_FIFO : COMPONENT IS TRUE;
ATTRIBUTE SYN_BLACK_BOX OF TIO_FIFO : COMPONENT IS TRUE;
ATTRIBUTE SYN_BLACK_BOX OF XADC_TEMPERATURE : COMPONENT IS TRUE;

ATTRIBUTE BLACK_BOX_PAD_PIN : STRING;
ATTRIBUTE BLACK_BOX_PAD_PIN OF CCLK_MMCM : COMPONENT IS "CLK_100MHZ_IN,CLK_100MHZ,CLK_200MHZ,CLK_400MHZ,RESET,LOCKED";
ATTRIBUTE BLACK_BOX_PAD_PIN OF TRIG_FIFO : COMPONENT IS "rst,wr_clk,rd_clk,din[7:0],wr_en,rd_en,dout[7:0],full,empty,prog_full";
ATTRIBUTE BLACK_BOX_PAD_PIN OF TIO_FIFO : COMPONENT IS "rst,wr_clk,rd_clk,din[7:0],wr_en,rd_en,dout[7:0],full,empty,prog_full";
ATTRIBUTE BLACK_BOX_PAD_PIN OF XADC_TEMPERATURE : COMPONENT IS "di_in[15:0],daddr_in[6:0],den_in,dwe_in,drdy_out,do_out[15:0],dclk_in,reset_in,vp_in,vn_in,channel_out[4:0],eoc_out,alarm_out,eos_out,busy_out";

type TEMP_STATE is (TS_INIT, TS_READ, TS_WAIT);
signal TempState : TEMP_STATE;

signal CLK_100MHZ    : std_logic;
signal CLK_125MHZ    : std_logic;
signal CLK_200MHZ    : std_logic;
signal CLK_400MHZ    : std_logic;

signal ExtTrig : std_logic_vector(7 downto 0);
signal GlobalReset   : std_logic;
signal GPIO_LED : std_logic_vector(3 downto 0);

  -- User Logic Connections
signal USER_RST       : std_logic;
signal USER_VERSION   : std_logic_vector(31 downto 0);
signal USER_STATUS    : std_logic_vector(31 downto 0);

signal USER_DIF       : std_logic_vector(31 downto 0);
signal USER_DIF_RD    : std_logic;

signal USER_CIF_EMPTY : std_logic;
signal USER_CIF_RD    : std_logic;
signal USER_CIF_RW    : std_logic;
signal USER_CIF_MODE  : std_logic_vector(7 downto 0);
signal USER_CIF_CNT   : std_logic_vector(15 downto 0);
signal USER_CIF_ADDR  : std_logic_vector(31 downto 0);

signal USER_DOF       : std_logic_vector(31 downto 0);
signal USER_DOF_WR    : std_logic;

signal USER_COF_STAT  : std_logic_vector(7 downto 0);
signal USER_COF_CNT   : std_logic_vector(15 downto 0);
signal USER_COF_AFULL : std_logic;
signal USER_COF_WR    : std_logic;

signal UseInputs    : std_logic;
signal CfgLocked    : std_logic;
signal SfpTimer     : std_logic_vector(24 downto 0);

signal DDR3_CompareError : std_logic;
signal DDR3_CalibComplete : std_logic;
signal LedToggle : std_logic_vector(27 downto 0);
signal LedRed : std_logic;

type BYTE_ARRAY is array (0 to 8) of std_logic_vector(7 downto 0); 
signal TrigOutDat     : BYTE_ARRAY;
signal TrigWr         : std_logic_vector(8 downto 0);
signal TrigOutFull    : std_logic_vector(8 downto 0);

signal TrigInDat      : std_logic_vector(7 downto 0);
signal TrigInChk      : std_logic_vector(7 downto 0);
signal TrigErrToggle  : std_logic;
signal TrigClkErr     : std_logic;
signal TrigOvflErr    : std_logic;
signal TrigLocked     : std_logic;
signal TrigInReady    : std_logic;
signal TrigInRd       : std_logic;
signal TrigFull       : std_logic;
signal TrigInvert     : std_logic_vector(8 downto 0);
signal TrigTestEn     : std_logic_vector(8 downto 0);
signal TrigActive     : std_logic_vector(8 downto 0);
signal RefCnt         : std_logic_vector(22 downto 0);
signal ChannelOn      : std_logic;
signal TrigEn         : std_logic_vector(3 downto 0);
signal TrigOutEn      : std_logic_vector(13 downto 0);

signal CMP : std_logic_vector(7 downto 0);

signal TestFull   : std_logic;
signal TestEmpty  : std_logic;
signal TestDat    : std_logic_vector(7 downto 0);
signal TestDin    : std_logic_vector(7 downto 0);
signal TestRd     : std_logic;
signal TestRdEn   : std_logic;
signal TestWr     : std_logic;
signal TestActive   : std_logic;
signal FifoReset   : std_logic;

signal DrpData : std_logic_vector(15 downto 0);
signal CurTemp : std_logic_vector(15 downto 0);
signal DrpEn : std_logic;
signal DrpRdy : std_logic;
signal DrpBusy : std_logic;

signal silly : std_logic;
begin
  -- Avoid Xilinx errors for unused pins in the XDC file
  UseInputs <= SFP_SDA and SFP_FAULT and SFP_LOS and SFP_PRESL;

  -- Force use of UserInputs
  SFP_SCL <= '1' when (FPGA_RESETL = '0' and UseInputs = '1') else '0';

  process(REF_FPGA, ChannelOn, GlobalReset)
  begin
    if ChannelOn = '1' or GlobalReset = '1' then
      RefCnt <= (others => '0');
    elsif rising_edge(REF_FPGA) then
      RefCnt <= RefCnt + 1;
    end if;
  end process;


  -- Reset SFP module for at least 100ms when GlobalReset is deasserted
  process(CLK_100MHZ, GlobalReset)
  begin
    if Globalreset = '1' then
      SfpTimer <= (others => '0');
      SFP_ENH <= '0';
      SFP_TXDIS <= '1';
      LedToggle <= (others => '0');
      LedRed <= '1';
      TempState <= TS_INIT;
      DrpEn <= '0';
      CurTemp <= (others => '0');
    elsif rising_edge(CLK_100MHZ) then
      LedToggle <= LedToggle + 1;

      if SFP_PRESL = '0' then
        -- Enable 250ms after the module is present and GlobalReset deasserted.  Longer so that you can seed RED LED at start for testing LEDs
        if SfpTimer(24) = '0'then
          SfpTimer <= SfpTimer + 1;
        else
          SFP_ENH <= '1';
          SFP_TXDIS <= '0';
          LedRed <= '0';
        end if;
      else
        -- Disable things when the module is not present
        SFP_ENH <= '0';
        SFP_TXDIS <= '1';
        SfpTimer <= (others => '0');
        LedRed <= '1';
      end if;

      -- Run a read of the temperature every time that LedToggle rolls over the 1M boundary
      case TempState is
  
        when TS_INIT =>
          -- Wait for start of a conversion so that you can read when it completes
          if LedToggle(20) = '1' and DrpBusy = '1' then
            TempState <= TS_READ;
          end if;
            
        when TS_READ =>
          -- Wait for end of conversion
          if DrpBusy = '0' then
            DrpEn <= '1';
            TempState <= TS_WAIT;
          end if;
          
        when TS_WAIT =>
          DrpEn <= '0';
          -- Wait for a bit until reading again
          -- Store data when DrpRdy asserted
          if LedToggle(20) = '0' then
            TempState <= TS_INIT;
          end if;
  
        when others =>
          null;
          
      end case;
      
      -- Record the temperature when it is ready after the read
      if DrpRdy = '1' then
        CurTemp <= DrpData;
      end if;
        
    end if;
  end process;

  XADC1 : XADC_TEMPERATURE
  PORT MAP
  (
    di_in         => x"0000",
    daddr_in      => "0000000", -- Temperature sensor
    den_in        => DrpEn,
    dwe_in        => '0',
    drdy_out      => DrpRdy,
    do_out        => DrpData,
    dclk_in       => CLK_100MHZ,
    reset_in      => GlobalReset,
    vp_in         => VP_IN ,
    vn_in         => VN_IN ,
    channel_out   => open ,
    eoc_out       => open ,
    alarm_out     => open ,
    eos_out       => open ,
    busy_out      => DrpBusy
  );

  -- All DGB(x) LEDs are active low
  -- DBG(0) Matching Ethernet Packet Toggle
  -- DBG(1) Non-Matching Ethernet Packet Toggle
  -- DBG(2) Ehernet Link Stauts, lit when link to SFP is active
  -- DBG(3) Lights during SFP link initialization and when External Trigger input is high
  -- DBG(4/DBG(5)) GRN = MIG Test Pass, RED = test fail, off = waiting for calibration to complete
  -- DBG(5) Turns off when MIG Calibration successfully completes
  -- DBG(6) PLL Lock for DAC Channel 0
  -- DBG(7) PLL Lock for DAC Channel 1
   
  -- Pass GPIO_LED to Debug LEDs
  DBG(2 downto 0) <= GPIO_LED(2 downto 0);

  -- Combine Link LED with external Trigger inputs.  Link only active during initial syncing
  DBG(3) <= '0' when (GPIO_LED(3) = '0'
                      or (TrigErrToggle = '1' and LedToggle(23) = '1')  -- Fast blink if locked and failing
                      or (TrigErrToggle = '0' and TrigLocked = '1' and LedToggle(25) = '1'))  -- Slow bink if locked w/o errors, off if not locked
                      else '1';

  -- Black wire = pin 1 = RED cathode.  Red = pin 2 = GRN cathode.
  -- Assume Black to 6 and Red to 7.  Then 7H/6L = RED, 7L/6H = GRN

  -- Display Trigger test status.  Blink green if locked and running.  Blink red if it is locked and failing.  Off if not locked
  -- Host can enable individual channels for send to verify front panel connectivity
  -- Also red when SFP_ENH is low for testing red
  DBG(6) <= '0' when LedRed = '1' else '1' when TrigLocked = '1' and TrigErrToggle = '0' and LedToggle(25) = '0' else 'Z' when TrigLocked = '0' or LedToggle(25) = '1' else '0';
  DBG(7) <= '1' when LedRed = '1' else '0' when TrigLocked = '1' and TrigErrToggle = '0' and LedToggle(25) = '0' else 'Z' when TrigLocked = '0' or LedToggle(25) = '1' else '1';

  -- Black wire = pin 1 = RED cathode.  Red = pin 2 = GRN cathode.
  -- Assume Black to 4 and Red to 5.  Then 5H/4L = RED, 5L/4H = GRN
  -- Display Trigger input status
  -- Off = No trigger received
  -- Green blinks indicate which single trigger input is active
  DBG(4) <= '0' when LedRed = '1' else '1' when ChannelOn = '1' or RefCnt(22) = '1' else 'Z';
  DBG(5) <= '1' when LedRed = '1' else '0' when ChannelOn = '1' or RefCnt(22) = '1' else 'Z';

  -- Blink N+1 times when trigger N is high
  ChannelOn <= '1' when (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "00000001" and LedToggle(26 downto 24)  = "000")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "00000010" and LedToggle(26 downto 24) <= "001")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "00000100" and LedToggle(26 downto 24) <= "010")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "00001000" and LedToggle(26 downto 24) <= "011")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "00010000" and LedToggle(26 downto 24) <= "100")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "00100000" and LedToggle(26 downto 24) <= "101")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "01000000" and LedToggle(26 downto 24) <= "110")
                     or (LedToggle(27) = '1' and LedToggle(23 downto 22) = "11" and CMP = "10000000")
               else '0';

  -- Enable Trigger Output when jumper installed and enabled by the host software
  -- TrigOutEn is zero by default and gets set by the host software
  -- Bit 13 must be set to enable anything, so that it is disabled by default

  -- sync trigger output enables  
  process(CLK_125MHZ)
    begin
      if rising_edge(CLK_125MHZ) then
        TrigTestEn(0) <= not USER_RST and TrigOutEn(0);
        TrigTestEn(1) <= not USER_RST and TrigOutEn(1);
        TrigTestEn(2) <= not USER_RST and TrigOutEn(2);
        TrigTestEn(3) <= not USER_RST and TrigOutEn(3);
        TrigTestEn(4) <= not USER_RST and TrigOutEn(4);
        TrigTestEn(5) <= not USER_RST and TrigOutEn(5);
        TrigTestEn(6) <= not USER_RST and TrigOutEn(6);
        TrigTestEn(7) <= not USER_RST and TrigOutEn(7);
        TrigTestEn(8) <= not USER_RST and TrigOutEn(8);
        TrigInvert    <= (others => TrigOutEn(13));  -- Invert output trigger sequence when set
      end if;
    end process;

  -- Convert CFG Clock to 200 MHz for the delay calibratrion clock and serial data input and 400 MHz for the data output clock
  CK0 : CCLK_MMCM
  port map
  (
    CLK_100MHZ_IN  => CFG_CCLK,
  
    -- Clock out ports
    CLK_100MHZ     => CLK_100MHZ ,  -- Replaces previous CFG_CCLK
    CLK_200MHZ     => CLK_200MHZ,
    CLK_400MHZ     => CLK_400MHZ,
  
    -- Status and control signals
    RESET          => not FPGA_RESETL,
    LOCKED         => CfgLocked
  );

  GlobalReset <= not CfgLocked;  -- Use lock status of the PLL driven by CFG_CCLK and reset by FPGA_RESETL as the global reset

  -- All of the APS Host Logic is contained within this component
  AC1 : ApsControl
  port map
  (
    -- asynchronous reset
    RESET                => GlobalReset,

    -- Clocks
    CLK_200MHZ           => CLK_200MHZ,
    CLK_125MHZ           => CLK_125MHZ ,

    -- MGTP Connections
    gtrefclk_p           => gtrefclk_p,
    gtrefclk_n           => gtrefclk_n,
    txp                  => txp       ,
    txn                  => txn       ,
    rxp                  => rxp       ,
    rxn                  => rxn       ,

    -- Config Bus Connections
    CFG_CLK        => CLK_100MHZ,   -- CLK_100MHZ is driven by CFG_CCLK
    CFGD           => CFGD,
    FPGA_CMDL      => FPGA_CMDL,
    FPGA_RDYL      => FPGA_RDYL,
    CFG_RDY        => CFG_RDY,
    CFG_ERR        => CFG_ERR,
    CFG_ACT        => CFG_ACT,
    STAT_OEL       => STAT_OEL,

    -- User Logic Connections
    USER_CLK       => CLK_100MHZ,
    USER_RST       => USER_RST,
    USER_VERSION   => x"00000A29",  -- Non Ethernet Firmware version to show changes to code other than ApsMsgProc.
    USER_STATUS    => x"0000" & CurTemp,

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

    -- GPIO for status and control
    STATUS(4)                => silly,
    STATUS(3 downto 0)       => GPIO_LED
  );

  -- All of the APS User Logic is contained within this component
  AUL1 : ApsDacUserLogic
  port map
  (
    USER_CLK       => CLK_100MHZ,
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

    DAC0_WF_MODE   => open ,
    DAC0_AMPLITUDE => TrigOutEn ,
    DAC1_WF_MODE   => open ,
    DAC1_AMPLITUDE => open
  );

    
  CBF1 : for i in 0 to 7 generate
    -- External trigger input from LVDS comparator.  Must be differentially termianted
    IBX : IBUFDS
    generic map
    (
      DIFF_TERM => TRUE, -- Differential Termination
      IBUF_LOW_PWR => FALSE -- Low power (TRUE) vs. performance (FALSE) setting for refernced I/O standards
    )
    port map
    (
      O  => CMP(i),        -- Drive the LED output
      I  => TRG_CMPP(i), -- Diff_p buffer input (connect directly to top-level port)
      IB => TRG_CMPN(i)  -- Diff_n buffer input (connect directly to top-level port)
    );
  end generate;

 -- Send output status to LEDs for checking
 LED(4 downto 0) <= (others => 'Z');
 LED(7 downto 5) <=      "000" when CMP = "00000001"
                    else "001" when CMP = "00000010" 
                    else "010" when CMP = "00000100" 
                    else "011" when CMP = "00001000" 
                    else "100" when CMP = "00010000" 
                    else "101" when CMP = "00100000" 
                    else "110" when CMP = "01000000" 
                    else "111" when CMP = "10000000" 
                    else "000";

LED(8) <=      LedToggle(25) when CMP = "00000001"
          else LedToggle(25) when CMP = "00000010" 
          else LedToggle(25) when CMP = "00000100" 
          else LedToggle(25) when CMP = "00001000" 
          else LedToggle(25) when CMP = "00010000" 
          else LedToggle(25) when CMP = "00100000" 
          else LedToggle(25) when CMP = "01000000" 
          else LedToggle(25) when CMP = "10000000" 
          else '0';


 LED(9) <= TrigClkErr or TrigOvflErr;

  -- Code to verify the operation of the trigger logic.
  -- Waits for the receiver to lock onto the clock from the transmitter and then sends an incremental stream of triggers.
  -- The receiver verifies that it receives incremental triggers.
  --
  process(CLK_125MHZ, USER_RST)
  begin
    if USER_RST = '1' then
      TrigInChk <=  x"00";
      TrigErrToggle <= '0';
    elsif rising_edge(CLK_125MHZ) then

      -- There are two operating modes.
      -- If TrigLocked is asserted, it is assumed that it is looping back within the board.
      -- If TrigLocked is not asserted, it assumes that it is testing external triggers

      if TrigLocked = '0' then
        -- Reset input verification when not locked
        TrigInChk <= x"00";
        TrigErrToggle <= '0';
      else
        -- Once you lock onto a looped back stream, verify the incremental data
        if TrigInReady = '1' then
          -- Read the receive FIFO until all of the triggers are received
          -- TrigInReady tied to TRIG_NEXT to advance FIFO when a trigger is available

          if TrigInChk = x"00" then
            -- Set the check value from the first trigger
            if TrigInDat = x"FF" then
              TrigInChk <= x"01";
            else
              TrigInChk <= TrigInDat + 1;
            end if;
          else
            -- Advance the check value when you have your first non-zero trigger
            if TrigInChk /= x"FF" then
              TrigInChk <= TrigInChk + 1;
            else
              TrigInChk <= x"01";
            end if;
  
            if TrigInDat /= TrigInChk then
              TrigErrToggle <= '1';
            end if;
          end if;
        end if; -- TrigInRdy
      end if; -- TrigLocked
    end if; -- rising_edge
  end process;

  -- Advance the FIFO when you have finished sending the current data
  TrigInRd <= TrigInReady;

  -- Use the extra STA connector as a test input
  TIL1 : TriggerInLogic
  port map
  (
    USER_CLK   => CLK_125MHZ,
    CLK_200MHZ => CLK_200MHZ,
    RESET      => USER_RST,
  
    TRIG_CLKP  => TRIG_CTRLP(0),
    TRIG_CLKN  => TRIG_CTRLN(0),
    TRIG_DATP  => TRIG_CTRLP(1),
    TRIG_DATN  => TRIG_CTRLN(1),
  
    TRIG_NEXT  => TrigInRd,  -- Always read data when it is available
    
    TRIG_LOCKED => TrigLocked,
    TRIG_ERR   => TrigClkErr ,
    TRIG_RX    => TrigInDat,
    TRIG_OVFL  => TrigOvflErr ,
    TRIG_READY => TrigInReady
  );
  

  -- Modified to allow use of I/O buffer
  TO1 : for i in 0 to 8 generate
    TOLX : TriggerOutLogic
    port map
    (
      USER_CLK   => CLK_125MHZ,
      
      -- These clocks are usually generated from an MMCM driven by the CFG_CCLK.
      CLK_100MHZ => CLK_100MHZ,
      CLK_400MHZ => CLK_400MHZ,
      RESET      => not TrigTestEn(i),
    
      TRIG_TX    => TrigOutDat(i),
      TRIG_WR    => TrigWr(i),
      TRIG_AFULL => TrigOutFull(i),
    
      TRIG_CLKP  => TRGCLK_OUTP(i),
      TRIG_CLKN  => TRGCLK_OUTN(i),
      TRIG_DATP  => TRGDAT_OUTP(i),
      TRIG_DATN  => TRGDAT_OUTN(i)
    );
    
    -- Externally, cable routing requires a non sequential JTx to TOx routing.
    -- The cables are routed from the PCB connectors to the front panel as shown below.
    -- The mapping is performed by changing the pin definitions in the XDC file.
    --
    -- TO1 = JT0
    -- TO2 = JT2
    -- TO3 = JT4
    -- TO4 = JT6
    -- TO5 = JC01
    -- TO6 = JT3
    -- TO7 = JT1
    -- TO8 = JT5
    -- TO9 = JT7
    -- TAUX = JT8
    --
    
    process(CLK_125MHZ, TrigTestEn(i))
    begin
      if TrigTestEn(i) = '0' then
        TrigWr(i) <= '0';
        TrigOutDat(i) <= x"00";
        TrigActive(i) <= '0';
      elsif rising_edge(CLK_125MHZ) then
        -- Default deassert FIFO write
        TrigWr(i) <= '0';

        -- Hold off start to give reset time for FIFO
        if TrigOutDat(i) = x"80" then
          TrigActive(i) <= '1';
        end if;
        
        -- There are two operating modes.
        -- If TrigLocked is asserted, it is assumed that it is looping back within the board.
        -- If TrigLocked is not asserted, it assumes that it is testing external triggers
  
        if TrigOutFull(i) = '0' then
          -- Write an incrementing or decrementing trigger pattern for trigger testing
          if TrigInvert(i) = '0' then
            TrigOutDat(i) <= TrigOutDat(i) + 1;
          else
            TrigOutDat(i) <= TrigOutDat(i) - 1;
          end if;

          -- Write TrigOutDat on next clock.  Zero value triggers are ignored by the receiver
          -- Delay writing the Trigger Output FIFO until 128 clocks after reset deasserted
          TrigWr(i) <= TrigActive(i);
        end if;

      end if;
    end process;
    
  end generate;

  -- 8 channels of PWM 
  PWM1 : for i in 0 to 7 generate
    PWMX : PWMA8
    port map
    (
      CLK => CLK_100MHZ,
      RESET => USER_RST,
      DIN => x"52",  -- Fix at 0.8V for now.  Eventually drive from a status register
      PWM_OUT => THR(i)
    );
  end generate;
 
end behavior;
