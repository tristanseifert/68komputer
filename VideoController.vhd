library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

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
		SRAM_UB:				OUT std_logic;
		
		-- Debug status info
		debug_state:		OUT std_logic_vector(3 downto 0) := (others => '0');
		debug_bits:			IN std_logic_vector(3 downto 0)
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
	
	-- CRAM signals
	signal cram_read_data, cram_write_data:std_logic_vector(23 downto 0);
	signal cram_read_addr, cram_write_addr:std_logic_vector(7 downto 0) := (others => '0');
	
	signal cram_write_strobe: std_logic := '0';
	
	-- FIFO stuff
	signal fifo_rdempty, fifo_wrfull: std_logic;
	signal fifo_rdreq, fifo_wrreq: std_logic := '0';
	signal fifo_read_data, fifo_write_data: std_logic_vector(33 downto 0) := (others => '0');
	
	-- SRAM clearing state machine
	signal sram_clear_addr: std_logic_vector(17 downto 0) := (others => '0');
	signal sram_clear_data: std_logic_vector(15 downto 0) := (others => '0');
	
	-- SRAM access state machine
	type ram_state_type is (Idle, CPUSlot0, CPUSlot1, ReadAddrVideo, ReadDataVideo, ClearAddr, ClearData);
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
		
-- Colour RAM
	u_cram: entity work.VideoCRAM(SYN)
		port map (
			data => cram_write_data,
			wraddress => cram_write_addr,
			wrclock => MemClk,
			wren => cram_write_strobe,
			
			q => cram_read_data,
			rdaddress => cram_read_addr,
			rdclock => MemClk
		);
		
-- CPU Write FIFO
-- Note:
-- Each entry is 34 bits: the high 16 are data, the low 18 the VRAM address.
	u_writefifo: entity work.VideoWriteFIFO(SYN)
		port map (
			data => fifo_write_data,
			wrclk => MemClk,
			wrreq => fifo_wrreq,
			wrfull => fifo_wrfull,
		
			q => fifo_read_data,
			rdclk => MemClk,
			rdreq => fifo_rdreq,
			rdempty => fifo_rdempty
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
			Out_R <= cram_read_data(23 downto 20);
			Out_G <= cram_read_data(15 downto 12);
			Out_B <= cram_read_data(7 downto 4);
	end if;
end process;

-- clearing of SRAM

-- Read/write state machine state advancement
process (MemClk, reset)
begin
	if reset='1'
		then		
		--	if debug_bits(0) = '1'
		--		then ram_current_state <= CPUSlot0;
		--		else ram_current_state <= ClearAddr;
		--	end if;
			ram_current_state <= CPUSlot0;
	elsif rising_edge(MemClk)
		then
			ram_current_state <= ram_next_state;
	end if;
end process;

-- Read/write state machine
process(reset, ram_current_state, SRAM_Data, row, col)
begin
		case ram_current_state is
			-- Idle state: nothing is happening
			when Idle =>
				SRAM_CE <= '1';
			
			-- CPU access slot 0
			when CPUSlot0 => -- pixel 1
				debug_state(0) <= '0';
			
				-- configure SRAM for write, /WE controlled
				SRAM_CE <= '0';
				SRAM_OE <= '1';
				
				SRAM_WE <= '0';
				SRAM_UB <= '0';
				SRAM_LB <= '0';
				
				-- put address for write slot on bus
				SRAM_Addr <= row(8 downto 0) & col(9 downto 1);
				SRAM_Data <= row(8 downto 1) & row(8 downto 1);
			
				-- perform colour lookup in CRAM for pixel 2 (7..0)
				cram_read_addr <= pxgen_cur(7 downto 0);
				ram_next_state <= CPUSlot1;
			
			when CPUSlot1 =>
				-- finish write cycle
				SRAM_WE <= '1';
				SRAM_UB <= '1';
				SRAM_LB <= '1';
				
				SRAM_Data <= (others => 'Z');
			
				-- update pixel data
				pxgen_cur <= pxgen_data;
				ram_next_state <= ReadAddrVideo;
		
			-- process of reading data for video
			when ReadAddrVideo => -- pixel 2
				SRAM_CE <= '0';
				SRAM_OE <= '0';
				SRAM_WE <= '1';
				SRAM_UB <= '0';
				SRAM_LB <= '0';
			
				SRAM_Addr <= row(8 downto 0) & col(9 downto 1);
			
				-- perform colour lookup in CRAM for pixel 1 (15..8)
				cram_read_addr <= pxgen_cur(15 downto 8);
				ram_next_state <= ReadDataVideo;
		
			-- Data is ready on SRAM, read it out and restore to idle state.
			when ReadDataVideo =>			
				pxgen_data <= SRAM_Data;
				ram_next_state <= CPUSlot0;
			
			-- Write address and data to clearAddr
			when ClearAddr =>
				SRAM_CE <= '0';
				SRAM_OE <= '1';
			
				SRAM_WE <= '0';
				SRAM_UB <= '0';
				SRAM_LB <= '0';
			
				debug_state(0) <= '1';
			
				SRAM_Addr <= sram_clear_addr;
				SRAM_Data <= sram_clear_addr(7 downto 0) & sram_clear_addr(7 downto 0);
			
				ram_next_state <= ClearData;
			
			-- Write data to clear with, increment address
			when ClearData =>
				SRAM_OE <= '0';
			
				SRAM_WE <= '1';
				SRAM_UB <= '1';
				SRAM_LB <= '1';
			
				sram_clear_addr <= sram_clear_addr + 1;
			
				if sram_clear_addr>=262144
					then 
						ram_next_state <= CPUSlot0;
						SRAM_Data <= (others => 'Z');
					else ram_next_state <= ClearAddr;				
				end if;
			end case;
end process;

debug_state(1) <= ActiveDisplay;
	 
end behavioral;