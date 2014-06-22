library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity BusRouter is 
	PORT(
		SW:			IN std_logic_vector(9 downto 0);
		KEY:			IN std_logic_vector(3 downto 0);
		LEDR:			OUT std_logic_vector(9 downto 0);
		LEDG:			OUT std_logic_vector(7 downto 0);
		
		Clock_24:	IN std_logic_vector(1 downto 0);
		
		-- video
		VGA_R:		OUT std_logic_vector(3 downto 0);
		VGA_G:		OUT std_logic_vector(3 downto 0);
		VGA_B:		OUT std_logic_vector(3 downto 0);
		VGA_VS:		OUT std_logic := '0';
		VGA_HS:		OUT std_logic := '0';
		
		-- SRAM
		SRAM_ADDR: 	OUT std_logic_vector(17 downto 0);
		SRAM_DQ: 	INOUT std_logic_vector(15 downto 0);
		
		SRAM_CE_N:	OUT std_logic;
		SRAM_OE_N:	OUT std_logic;
		SRAM_WE_N:	OUT std_logic;
		
		SRAM_LB_N:	OUT std_logic;
		SRAM_UB_N:	OUT std_logic
	);
end BusRouter;

architecture behavioral of BusRouter is
signal sys_reset: STD_LOGIC := '0';
begin
	u_VideoController: entity work.VideoController(behavioral)
		port map(
			reset => sys_reset,
	 
			In_Clk_24 => Clock_24(0),
			Out_R => VGA_R,
			Out_G => VGA_G,
			Out_B => VGA_B,
			Out_HSync => VGA_HS,
			Out_VSync => VGA_VS,
			
			SRAM_Addr => SRAM_ADDR,
			SRAM_Data => SRAM_DQ,
			SRAM_CE => SRAM_CE_N,
			SRAM_OE => SRAM_OE_N,
			SRAM_WE => SRAM_WE_N,
			SRAM_LB => SRAM_LB_N,
			SRAM_UB => SRAM_UB_N
		);
	 
	-- button and LED interfacing
	sys_reset <= NOT KEY(0);
	LEDG(0) <= NOT sys_reset;
end behavioral;