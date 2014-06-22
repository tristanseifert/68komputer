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
		reset:				IN std_logic;
		clk:					IN std_logic;	
	
		-- interface to SRAM
		SRAM_Addr: 			OUT std_logic_vector(17 downto 0) := (others => '0');
		SRAM_Data: 			INOUT std_logic_vector(15 downto 0) := (others => 'Z');
		SRAM_CE:				OUT std_logic := '1';
		SRAM_OE:				OUT std_logic := '1';
		SRAM_WE:				OUT std_logic := '1';
		SRAM_LB:				OUT std_logic := '1';
		SRAM_UB:				OUT std_logic := '1';
		
		-- video read interface
		Vid_AS_N:			IN std_logic; -- active 0
		Vid_Addr:			IN	std_logic_vector(17 downto 0);
		Vid_Data:			OUT std_logic_vector(15 downto 0) := (others => '0');
		Vid_Data_Ready:	OUT std_logic
	);
end VideoSRAMController;


architecture behavioral of VideoSRAMController is

type rw_state_type is (Idle, ReadAddrVideo, ReadDataVideo);
signal current_state, next_state: rw_state_type;

begin

-- Read/write state machine
process(current_state, Vid_Addr, SRAM_Data)
begin
	case current_state is
		-- Idle state: deselect the SRAM
		when Idle =>
			SRAM_CE <= '1';
			SRAM_OE <= '1';
			SRAM_WE <= '0';
			SRAM_UB <= '1';
			SRAM_LB <= '1';
			
			Vid_Data_Ready <= '0';
			
			next_state <= Idle;
		
		-- process of reading data for video
		when ReadAddrVideo =>
			SRAM_CE <= '0';
			SRAM_OE <= '0';
			SRAM_WE <= '1';
			SRAM_UB <= '0';
			SRAM_LB <= '0';
			
			SRAM_Addr <= Vid_Addr;
			next_state <= ReadDataVideo;
		
		-- Data is ready on SRAM, read it out and restore to idle state.
		when ReadDataVideo =>
			Vid_Data <= SRAM_Data;
			Vid_Data_Ready <= '1';
			
			next_state <= Idle;
	end case;
end process;

end behavioral;