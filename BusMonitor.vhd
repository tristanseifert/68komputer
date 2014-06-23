library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

--
-- This hooks up to the bus, LED display, LEDs, switches and buttons and allows
-- control of the processor. It allows single-stepping of the processor, and
-- when not in debug mode, functions as a memory-mapped peripheral that can
-- control the seven-segments, buttons and LEDs.
--
-- To single-step the CPU, put SW0 into the up position. The LED above it will
-- begin blinking, indicating you are in single-stepping mode. KEY0 can then be
-- used to single-step. Note that all other debugger functions are dependant
-- on this.
--
-- To change what is displayed on the LED display, use SW8 and SW9. With both off,
-- the contents of the data bus is displayed. With SW8 on and SW9 off, the low 16
-- bits of the address bus are displayed. With SW9 on and SW8 off, the IPL and high
-- 8 bits of the address bus are displayed. With both SW8 and SW9 on, the contents
-- of the memory-mapped register is displayed.  
--

entity BusMonitor is
	PORT(
		-- CPU clock
		clk_cpu:				IN std_logic;
		sys_reset:			INOUT std_logic;
		
		-- Blinking clock
		blink_clk:			IN std_logic;
	
		-- 68k bus: system control
		bus_reset:			IN std_logic;
		bus_clk:				INOUT std_logic; -- CPU clock
		bus_halt:			INOUT std_logic;
		bus_error:			IN std_logic;
		
		-- 68k bus: data
		bus_data:			INOUT std_logic_vector(15 downto 0);
		bus_addr:			INOUT std_logic_vector(23 downto 0);

		-- 68k bus: bus control
		bus_as:				INOUT std_logic;
		bus_rw:				INOUT std_logic; -- read = 1, write = 0
		
		bus_uds:				INOUT std_logic; -- upper and lower byte strobes
		bus_lds:				INOUT std_logic;
		
		bus_dtack:			IN std_logic; -- data acknowledge, driven by peripheral
		
		-- 68k bus: bus arbitration
		bus_br:				INOUT std_logic; -- assert to request bus
		bus_bg:				IN std_logic; -- asserted when bus is free
		bus_bgack:			INOUT std_logic; -- assert to acknowledge bus request
		
		-- 68k bus: interrupt control
		bus_irq:				IN std_logic_vector(2 downto 0);
		
		-- peripherals
		HEX0:					OUT std_logic_vector(6 downto 0);
		HEX1:					OUT std_logic_vector(6 downto 0);
		HEX2:					OUT std_logic_vector(6 downto 0);
		HEX3:					OUT std_logic_vector(6 downto 0);
		
		SW:					IN std_logic_vector(9 downto 0);
		KEY:					IN std_logic_vector(3 downto 0);
		LEDR:					OUT std_logic_vector(9 downto 0);
		LEDG:					OUT std_logic_vector(7 downto 0)
	);
end BusMonitor;

architecture behavioral of BusMonitor is
	signal hexValue:	std_logic_vector(15 downto 0);
begin

-- hex displays
	u_hex0: entity work.HexDisplay(behavioral)
		port map(
			clk => clk_cpu,
			reset => sys_reset,
			Display => HEX3,
			InVal => hexValue(15 downto 12)
		);
	u_hex1: entity work.HexDisplay(behavioral)
		port map(
			clk => clk_cpu,
			reset => sys_reset,
			Display => HEX2,
			InVal => hexValue(11 downto 8)
		);
	u_hex2: entity work.HexDisplay(behavioral)
		port map(
			clk => clk_cpu,
			reset => sys_reset,
			Display => HEX1,
			InVal => hexValue(7 downto 4)
		);
	u_hex3: entity work.HexDisplay(behavioral)
		port map(
			clk => clk_cpu,
			reset => sys_reset,
			Display => HEX0,
			InVal => hexValue(3 downto 0)
		);

-- Green LEDs indicate the bus state:
-- BERR | AS | RW | UDS | LDS | DTACK | BR | BG
process(bus_clk, sys_reset, bus_error, bus_as, bus_rw, bus_uds, bus_lds, bus_dtack, bus_br, bus_bg)
begin
	if sys_reset='1' then
	
	elsif rising_edge(bus_clk) then
		LEDG(7) <= bus_error;
		LEDG(6) <= bus_as;
		LEDG(5) <= bus_rw;
		LEDG(4) <= bus_uds;
		LEDG(3) <= bus_lds;
		LEDG(2) <= bus_dtack;
		LEDG(1) <= bus_br;
		LEDG(0) <= bus_bg;
	end if;
end process;

-- reset button
sys_reset <= NOT KEY(3);

-- Single-stepping
process(SW(0), KEY(0), blink_clk)
begin
	if SW(0)='1' then
		bus_clk <= KEY(0);
		LEDR(0) <= blink_clk;
	else
		bus_clk <= clk_cpu;
		LEDR(0) <= '0';
	end if;
end process;

-- Display
process (SW(9 downto 8))
begin
	case SW(9 downto 8) is
		when "00" =>
			hexValue <= bus_data;
		when "01" =>
			hexValue <= bus_addr(15 downto 0);		
		when "10" =>
			hexValue <= "0" & bus_irq & "0000" & bus_addr(23 downto 16);		
		when "11" =>
			hexValue <= x"ABCD";
	end case;
end process;

end behavioral;