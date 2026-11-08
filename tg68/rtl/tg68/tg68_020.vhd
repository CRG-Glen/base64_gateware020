-- tg68_020 : TG68K.C kernel fixed in 68020 mode for Base64.
-- A thin entity so GHDL can emit a flat Verilog netlist with the generics
-- folded.  Port names are lower case so Verilog can instantiate this
-- entity under both GHDL and Synplify.  BARREL generic: 1 = barrel shifter (fast shifts, more LUTs).
-- BITFIELD generic: 0 drops BFxxx (they then take the illegal-instruction
-- trap), saving LUTs and, mainly, routing congestion.
-- MULHW generic: 0 does MULU.L/MULS.L iteratively instead of in the DSP
-- blocks -- slower multiplies, but no wide buses to and from the DSP row.
-- DP32 generic: the kernel's DataPath32 flags (m1nl's TG68K.C fork, commit
-- a8e6f38): bit 0 longword data reads/writes, bit 1 32-bit immediates, bit 2
-- absolute-long address extensions, each as one aligned pair when the bus
-- side answers long_cand with long_ack. With long_ack held at 0 the kernel
-- runs the ordinary 16-bit sequence. Base64 uses 1 (data only): bits 1 and
-- 2 put the kernel's clkena paths 2-5 ns over budget on every seed tried.
-- CLKLW generic: 1 = the kernel takes clkena_lw (its long-word clock enable)
-- from clkena_lw_in, a register in tg68_bus, instead of computing
-- clkena_in AND (NOT longword OR long_ack) itself (Base64 kernel change 2).
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity tg68_020 is
  generic (BARREL : integer := 0; BITFIELD : integer := 1; MULHW : integer := 1;
           DP32 : integer := 1; CLKLW : integer := 1);
  port (
    clk        : in  std_logic;
    nreset     : in  std_logic;
    clkena_in  : in  std_logic;
    clkena_lw_in : in std_logic;                      -- with CLKLW=1, see above
    data_in    : in  std_logic_vector(15 downto 0);
    data_in_hi : in  std_logic_vector(15 downto 0);   -- wide read, word at addr+0
    long_ack   : in  std_logic;                       -- accept this aligned pair
    ipl        : in  std_logic_vector(2 downto 0);
    berr       : in  std_logic;
    addr_out   : out std_logic_vector(31 downto 0);
    data_write : out std_logic_vector(15 downto 0);
    data_write_lo : out std_logic_vector(15 downto 0); -- wide write, word at addr+2
    long_cand  : out std_logic;                       -- this access may be a pair
    longword   : out std_logic;                       -- a longword access (clkena_lw_in)
    nwr        : out std_logic;
    nuds       : out std_logic;
    nlds       : out std_logic;
    busstate   : out std_logic_vector(1 downto 0);
    nresetout  : out std_logic;
    fc         : out std_logic_vector(2 downto 0);
    skipfetch  : out std_logic;
    cacr       : out std_logic_vector(3 downto 0)
  );
end tg68_020;
architecture rtl of tg68_020 is
begin
  cpu: entity work.TG68KdotC_Kernel
    generic map (SR_Read => 1, VBR_Stackframe => 1, extAddr_Mode => 1,
                 MUL_Mode => 1, DIV_Mode => 1, BitField => BITFIELD,
                 BarrelShifter => BARREL, MUL_Hardware => MULHW,
                 DataPath32 => std_logic_vector(to_unsigned(DP32, 3)),
                 ClkenaLW_Ext => CLKLW)
    port map (clk => clk, nReset => nreset, clkena_in => clkena_in,
              clkena_lw_in => clkena_lw_in,
              data_in => data_in, data_in_hi => data_in_hi, long_ack => long_ack,
              IPL => ipl, IPL_autovector => '0',
              berr => berr, CPU => "11",
              addr_out => addr_out, data_write => data_write,
              data_write_lo => data_write_lo, long_cand => long_cand, nWr => nwr,
              nUDS => nuds, nLDS => nlds, busstate => busstate,
              longword => longword, nResetOut => nresetout, FC => fc,
              clr_berr => open, skipFetch => skipfetch,
              regin_out => open, CACR_out => cacr, VBR_out => open);
end rtl;
