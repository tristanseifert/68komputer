library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--
-- Video controller, providing bitmapped display to the system. It uses the SRAM
-- as a video memory, with each pixel occupying 8 bits. This is then taken as an
-- offset into the colour look-up table, or CRAM, and outputted.
--
-- SRAM is organised with each line taking up 1024 bytes, for simpler logic. The
-- addresses are built as row(8..0) | col(9..1). Since the SRAM is 16 bits wide,
--	we only request a read every other pixel.
--

entity VideoController is
	PORT (
		-- clocks and friends
		reset:		IN std_logic;
		In_Clk_24:	IN std_logic;
		
		-- video signals
		Out_R:		OUT std_logic_vector(3 downto 0);
		Out_G:		OUT std_logic_vector(3 downto 0);
		Out_B:		OUT std_logic_vector(3 downto 0);
		
		Out_HSync:	OUT std_logic;
		Out_VSync:	OUT std_logic;
		
		-- SRAM (used to store video datas)
		SRAM_Addr: 	OUT std_logic_vector(17 downto 0);
		SRAM_Data: 	INOUT std_logic_vector(15 downto 0);
		
		SRAM_CE:		OUT std_logic;
		SRAM_OE:		OUT std_logic;
		SRAM_WE:		OUT std_logic;
		
		SRAM_LB:		OUT std_logic;
		SRAM_UB:		OUT std_logic
	);
end VideoController;

architecture behavioral of VideoController is
	signal VidClk: std_logic; -- 25.175 MHz
	signal MemClk: std_logic; -- 50.35 MHz
	
	signal ActiveDisplay: std_logic; -- when asserted, colours out
	
	signal col, row: std_logic_vector(9 downto 0);

	-- pixel generation signals
	signal pxgen_as_n:	std_logic;
	signal pxgen_addr:	std_logic_vector(17 downto 0);
	
	-- this will *always* hold the last word read from memory
	signal pxgen_data:	std_logic_vector(15 downto 0);
begin
-- video clock generator
	u_VideoPLL: entity work.VideoPLL(SYN)
		port map(
			inclk0 => In_Clk_24,
			c0 => VidClk,
			c1 => MemClk,
			areset => reset
		);

-- video sync state machine
	u_videoSyncer: entity work.VideoSyncGenerator(behavioral)
		port map(
			reset => reset,
			PixelClock => VidClk,
			HSync => Out_HSync,
			VSync => Out_VSync,
			
			VideoOn => ActiveDisplay,
			CurCol => col,
			CurRow => row
		);
		
-- memory controller
	u_videoSRAMController: entity work.VideoSRAMController(behavioral)
		port map (
			reset => reset,
			clk => MemClk,
			
			SRAM_Addr => SRAM_Addr,
			SRAM_Data => SRAM_Data,
			SRAM_CE => SRAM_CE,
			SRAM_OE => SRAM_OE,
			SRAM_WE => SRAM_WE,
			SRAM_LB => SRAM_LB,
			SRAM_UB => SRAM_UB,
			
			Vid_AS_N => pxgen_as_n,
			Vid_Addr => pxgen_addr,
			Vid_Data => pxgen_data
		);
		
-- blank output if active display
process(ActiveDisplay, col, row)
begin
	if ActiveDisplay='0'
		then
			Out_R <= (others => '0');
			Out_G <= (others => '0');
			Out_B <= (others => '0');
		else
			Out_R <= col(3 downto 0);
			Out_G <= col(7 downto 4);
			Out_B <= row(4 downto 1);
	end if;
end process;
	 
end behavioral;