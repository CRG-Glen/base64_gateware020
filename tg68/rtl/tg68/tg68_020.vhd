-- tg68_020 : TG68K.C kernel fixed in 68020 mode for Base64.
-- A thin entity so GHDL can emit a flat Verilog netlist with the generics
-- folded.  Port names are lower case so Verilog can instantiate this
-- entity under both GHDL and Synplify.  BARREL generic: 1 = barrel shifter (fast shifts, more LUTs).
-- BITFIELD generic: 0 drops BFxxx (they then take the illegal-instruction
-- trap), saving LUTs and, mainly, routing congestion.
-- MULHW generic: 0 does MULU.L/MULS.L iteratively instead of in the DSP
-- blocks -- slower multiplies, but no wide buses to and from the DSP row.
library ieee; use ieee.std_logic_1164.all;
entity tg68_020 is
  generic (BARREL : integer := 0; BITFIELD : integer := 1; MULHW : integer := 1);
  port (
    clk        : in  std_logic;
    nreset     : in  std_logic;
    clkena_in  : in  std_logic;
    data_in    : in  std_logic_vector(15 downto 0);
    ipl        : in  std_logic_vector(2 downto 0);
    berr       : in  std_logic;
    addr_out   : out std_logic_vector(31 downto 0);
    data_write : out std_logic_vector(15 downto 0);
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
                 BarrelShifter => BARREL, MUL_Hardware => MULHW)
    port map (clk => clk, nReset => nreset, clkena_in => clkena_in,
              data_in => data_in, IPL => ipl, IPL_autovector => '0',
              berr => berr, CPU => "11",
              addr_out => addr_out, data_write => data_write, nWr => nwr,
              nUDS => nuds, nLDS => nlds, busstate => busstate,
              longword => open, nResetOut => nresetout, FC => fc,
              clr_berr => open, skipFetch => skipfetch,
              regin_out => open, CACR_out => cacr, VBR_out => open);
end rtl;
