library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

--
-- This controller provides a simple interface to access the on-board SRAM for
-- video hardware. It exposes two ports: a read-only port for the pixel generator,
--	and a read/write port for the CPU. The latter utilises a FIFO, whereas the
--	read-only port guarantees data output one cycle after /Vid_AS is asserted.
--

entity VideoSRAMController is
	PORT(
		-- management signals
		reset:		IN std_logic;
		clk:			IN std_logic;	
	
		-- interface to SRAM
		SRAM_Addr: 	OUT std_logic_vector(17 downto 0) := (others => '0');
		SRAM_Data: 	INOUT std_logic_vector(15 downto 0) := (others => 'Z');
		SRAM_CE:		OUT std_logic := '1';
		SRAM_OE:		OUT std_logic := '1';
		SRAM_WE:		OUT std_logic := '1';
		SRAM_LB:		OUT std_logic := '1';
		SRAM_UB:		OUT std_logic := '1';
		
		-- video read interface
		Vid_AS_N:	IN std_logic; -- active 0
		Vid_Addr:	IN	std_logic_vector(17 downto 0);
		Vid_Data:	OUT std_logic_vector(15 downto 0) := (others => '0')
	);
end VideoSRAMController;


architecture behavioral of VideoSRAMController is
begin

-- ensure the SRAM is selected, unless reset is active
process (reset)
begin
	if reset='1'
		then
			SRAM_CE <= '1';
		else
			SRAM_CE <= '0';		
	end if;
end process;

end behavioral;