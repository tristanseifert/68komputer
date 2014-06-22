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
		reset:				IN std_logic;
		In_Clk_24:			IN std_logic;
		
		-- video signals
		Out_R:				OUT std_logic_vector(3 downto 0);
		Out_G:				OUT std_logic_vector(3 downto 0);
		Out_B:				OUT std_logic_vector(3 downto 0);
		
		Out_HSync:			OUT std_logic;
		Out_VSync:			OUT std_logic;
		
		-- SRAM (used to store video datas)
		SRAM_Addr:		 	OUT std_logic_vector(17 downto 0);
		SRAM_Data: 			INOUT std_logic_vector(15 downto 0);
		
		SRAM_CE:				OUT std_logic;
		SRAM_OE:				OUT std_logic;
		SRAM_WE:				OUT std_logic;
		
		SRAM_LB:				OUT std_logic;
		SRAM_UB:				OUT std_logic
	);
end VideoController;

architecture behavioral of VideoController is
	signal VidClk: std_logic; -- 25.175 MHz
	signal MemClk: std_logic; -- 50.35 MHz
	
	signal ActiveDisplay: std_logic; -- when asserted, colours out
	
	signal col, row: std_logic_vector(9 downto 0);
	
	-- this will *always* hold the last word read from memory
	signal pxgen_data:	std_logic_vector(15 downto 0);
	-- data currently used for pixel generation
	signal pxgen_cur:		std_logic_vector(15 downto 0);
	
	-- 24 bit rgb value for current pixel
	signal current_rgb:	std_logic_vector(23 downto 0);
	
	type ram_state_type is (CPUSlot0, CPUSlot1, ReadAddrVideo, ReadDataVideo);
	signal ram_current_state, ram_next_state: ram_state_type;
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
		
-- blank output if active display
process(ActiveDisplay, col, row)
begin
	if ActiveDisplay='0'
		then
			Out_R <= (others => '0');
			Out_G <= (others => '0');
			Out_B <= (others => '0');
		else
			Out_R <= current_rgb(23 downto 20);
			Out_G <= current_rgb(15 downto 12);
			Out_B <= current_rgb(7 downto 4);
	end if;
end process;

-- Read/write state machine state advancement
process (MemClk, reset)
begin
	if reset='1'
		then
			ram_current_state <= CPUSlot0;
	elsif rising_edge(MemClk)
		then
			ram_current_state <= ram_next_state;
	end if;
end process;

-- Read/write state machine
process(ram_current_state, SRAM_Data)
begin
	case ram_current_state is
		-- Idle state: deselect the SRAM
		when CPUSlot0 =>
			SRAM_CE <= '1';
			SRAM_OE <= '1';
			SRAM_WE <= '0';
			SRAM_UB <= '1';
			SRAM_LB <= '1';
			
			pxgen_cur <= pxgen_data;
			ram_next_state <= CPUSlot1;
			
		when CPUSlot1 =>
			-- perform colour lookup in CRAM for pixel 1 (15..8)
			current_rgb <= pxgen_cur(15 downto 12) & "0000" & pxgen_cur(11 downto 8) & "0000" & pxgen_cur(15 downto 12) & "0000";
			ram_next_state <= ReadAddrVideo;
		
		-- process of reading data for video
		when ReadAddrVideo =>
			SRAM_CE <= '0';
			SRAM_OE <= '0';
			SRAM_WE <= '1';
			SRAM_UB <= '0';
			SRAM_LB <= '0';
			
			SRAM_Addr <= row(8 downto 0) & col(9 downto 1);
			ram_next_state <= ReadDataVideo;
		
		-- Data is ready on SRAM, read it out and restore to idle state.
		when ReadDataVideo =>
			-- perform colour lookup in CRAM for pixel 2 (7..0)
			current_rgb <= pxgen_cur(7 downto 4) & "0000" & pxgen_cur(3 downto 0) & "0000" & pxgen_cur(7 downto 4) & "0000";
			
			pxgen_data <= SRAM_Data;
			ram_next_state <= CPUSlot0;

	end case;
end process;
	 
end behavioral;