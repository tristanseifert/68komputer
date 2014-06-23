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
		debug_bits:			IN std_logic_vector(3 downto 0) := (others => '0');
		
		-- CPU bus
		bus_cs:				IN std_logic; -- when high, outs is Z
		
		bus_clk:				IN std_logic;
		bus_address:		IN std_logic_vector(18 downto 0);
		bus_data:			INOUT std_logic_vector(15 downto 0);
		
		bus_rw:				IN std_logic;
		bus_as:				IN std_logic;
		bus_dtack:			OUT std_logic;
		
		bus_uds:				IN std_logic;
		bus_lds:				IN std_logic
	);
end VideoController;

architecture behavioral of VideoController is
	signal VidClk:				std_logic; -- 25.175 MHz
	signal MemClk:				std_logic; -- 50.35 MHz
	
	signal ActiveDisplay:	std_logic; -- when asserted, colours out
	
	signal col, row:			std_logic_vector(9 downto 0);
	
	-- this will *always* hold the last word read from memory
	signal pxgen_data:		std_logic_vector(15 downto 0) register;
	
	-- CRAM signals
	signal cram_read_data:	std_logic_vector(23 downto 0);
	signal cram_write_data:	std_logic_vector(23 downto 0);
	signal cram_read_addr:	std_logic_vector(7 downto 0) := (others => '0'); 
	signal cram_write_addr:	std_logic_vector(7 downto 0) := (others => '0');
	
	signal cram_write_strobe: std_logic := '0';
	
	-- FIFO stuff
	signal fifo_read_pend:	std_logic register := '0';
	signal fifo_rdempty: 	std_logic := '1';
	signal fifo_wrfull:		std_logic := '0';
	signal fifo_rdreq:		std_logic := '0';
	signal fifo_wrreq:		std_logic := '0';
	signal fifo_read_data:	std_logic_vector(35 downto 0) := (others => '0'); 
	signal fifo_write_data:	std_logic_vector(35 downto 0) := (others => '0');
	
	-- SRAM access state machine
	type ram_state_type is (SysReset, CPUSlot0, CPUSlot1, ReadAddrVideo, ReadDataVideo);
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
-- Each entry is 36 bits: UDS, LDS, 16 bits of data, and 18 bits of VRAM address.
	u_writefifo: entity work.VideoWriteFIFO(SYN)
		port map (
			data => fifo_write_data,
			wrclk => bus_clk,
			wrreq => fifo_wrreq,
			wrfull => fifo_wrfull,
		
			q => fifo_read_data,
			rdclk => MemClk,
			rdreq => fifo_rdreq,
			rdempty => fifo_rdempty,
			
			aclr => reset
		);
		
-- 68k bus interface. Writes go straight into the FIFO, and will process with
-- no wait states, unless the FIFO is filled. In that case, wait states are
-- inserted until the FIFO is no longer full.
process(bus_clk, reset, bus_cs, bus_rw, fifo_wrfull, bus_uds, bus_lds)
begin
	-- in reset state, don't drive the bus
	if reset='0' then
		bus_data <= (others => 'Z');
		bus_dtack <= 'Z';	
	elsif rising_edge(bus_clk) then
		-- is our chip select asserted?
		if bus_cs='0' then
			-- write cycle
			if bus_rw='0' then
				if fifo_wrfull='0' then
					fifo_write_data <= bus_uds & bus_lds & bus_data & bus_address(18 downto 1);
					fifo_wrreq <= '1';
					bus_dtack <= '0';
				else
					-- fifo is full: delay the bus cycle some more
					bus_dtack <= '1';
				end if;
			-- read cycle
			else
				-- unhandled: lock up machine
				bus_dtack <= '1';
			end if;
		-- not selected: don't drive bus
		else
			bus_data <= (others => 'Z');
			bus_dtack <= 'Z';
			
			-- de-assert FIFO write request
			fifo_wrreq <= '0';
		end if;
	end if;
end process;
		
-- blank output if active display
process(ActiveDisplay, col, row, cram_read_data, pxgen_data)
begin
	if ActiveDisplay='0'
		then -- inactivedisplay; render colour 0
			cram_read_addr <= (others => '0');
		else -- active display; process read pixel data
			if col(0)='0'
				then cram_read_addr <= pxgen_data(7 downto 0); -- display odd pixel next
				else cram_read_addr <= pxgen_data(15 downto 8); -- display even pixel next
			end if;
	end if;
	
	-- get colour from CRAM
	Out_R <= cram_read_data(23 downto 20);
	Out_G <= cram_read_data(15 downto 12);
	Out_B <= cram_read_data(7 downto 4);
end process;

-- Read/write state machine state advancement
process (MemClk, reset)
begin
	if reset='1'
		then ram_current_state <= SysReset;
	elsif rising_edge(MemClk)
		then
			ram_current_state <= ram_next_state;
	end if;
end process;

-- Read/write state machine
process(reset, ram_current_state, SRAM_Data, row, col, fifo_rdempty)
begin
	-- default CRAM and FIFO values
	--cram_read_addr <= (others => '0');
	fifo_rdreq <= '0';
	
	-- default sram state
	SRAM_CE <= '0';
	SRAM_OE <= '0';
	SRAM_WE <= '1';
	SRAM_UB <= '1';
	SRAM_LB <= '1';
			
	SRAM_Addr <= (others => '0');
	SRAM_Data <= (others => 'Z');

	-- state machine
	case ram_current_state is
		-- Reset state: the mem system is cleared out
		when SysReset =>
			SRAM_CE <= '1';
			SRAM_OE <= '1';
			
			ram_next_state <= CPUSlot0;
			
		-- CPU access slot 0
		when CPUSlot0 => -- pixel 1		
			-- configure SRAM for write, /WE controlled
			SRAM_OE <= '1';
			SRAM_WE <= '0';
			SRAM_UB <= '0';
			SRAM_LB <= '0';
			
			-- put address for write slot on bus
			SRAM_Addr <= row(8 downto 0) & col(9 downto 1);
			SRAM_Data <= col(8 downto 1) & col(8 downto 1);
				
			-- Was a word read out of the FIFO?
			if fifo_read_pend='1'
				then
					SRAM_Addr <= fifo_read_data(17 downto 0);
					SRAM_Data <= fifo_read_data(33 downto 18);
					
					SRAM_UB <= fifo_read_data(35);
					SRAM_LB <= fifo_read_data(34);
					
					fifo_read_pend <= '0';
				--else
			end if;
			
			ram_next_state <= CPUSlot1;
			
		when CPUSlot1 =>
			ram_next_state <= ReadAddrVideo;
		
		-- process of reading data for video
		when ReadAddrVideo => -- pixel 2
			SRAM_UB <= '0';
			SRAM_LB <= '0';
			
			--if debug_bits(1 downto 0) = "00" then SRAM_Addr <= (row(8 downto 0) & col(9 downto 1)) + 0;
			--elsif debug_bits(1 downto 0) = "01" then SRAM_Addr <= (row(8 downto 0) & col(9 downto 1)) + 1;
			--elsif debug_bits(1 downto 0) = "10" then SRAM_Addr <= (row(8 downto 0) & col(9 downto 1)) - 1;
			--end if;
			
			SRAM_Addr <= (row(8 downto 0) & col(9 downto 1));
			
			-- Request a readout of the FIFO, if it is not empty. There is a 2-cycle
			-- delay between asserting rdreq and getting valid output data.
			if fifo_rdempty='0'
				then
				fifo_rdreq <= '1';
				fifo_read_pend <= '1';
			end if;
			
			ram_next_state <= ReadDataVideo;
		
		-- Data is ready on SRAM, read it out and restore to idle state.
		when ReadDataVideo =>				
			pxgen_data <= SRAM_Data;
			ram_next_state <= CPUSlot0;
		end case;
end process;

debug_state(1) <= ActiveDisplay;
	 
end behavioral;