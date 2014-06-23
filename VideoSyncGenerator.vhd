library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- This is responsible for outputting the proper video sync signals for VGA at
-- 640x480 with a 60 Hz refresh rate.
--
-- The actual video dimensions are 800x525:
-- HORIZONTAL:
-- 	640 clocks: Displayable	(000)
--		016 clocks: Front porch	(640)
--		096 clocks: Sync pulse	(656)
--		048 clocks: Back porch	(752)
--
-- VERTICAL:
--		480 lines: Displayable	(000)
--		010 lines: Front porch	(480)
--		002 lines: Sync pulse	(490)
--		033 lines: Back porch	(492)
--
--	In our case, the sync pulse will pulse the proper sync signal low: it is
--	usually high during displayed frames.

entity VideoSyncGenerator is
	PORT(
		reset: 				IN std_logic;
		PixelClock:			IN std_logic;
		HSync:				OUT std_logic;
		VSync:				OUT std_logic;
		
		VideoOn:				OUT std_logic; -- indicates whether colourshall be outputted
		
		CurCol:				OUT std_logic_vector(9 downto 0);
		CurRow:				OUT std_logic_vector(9 downto 0)
	);
end VideoSyncGenerator;

architecture behavioral of VideoSyncGenerator is
	signal vcount: std_logic_vector(9 downto 0); -- count scanlines
	signal hcount: std_logic_vector(9 downto 0); -- count pixels
	
	signal hblank, vblank: std_logic;
begin

-- Horizontal line counter
hcounter: process(PixelClock, reset)
begin
	-- if reset is asserted
	if reset = '1'
		then hcount <= (others => '0');
	elsif rising_edge(PixelClock)
		then 
			if hcount=799
				then hcount <= (others => '0');
				else hcount <= hcount + 1;
			end if;
	end if;
end process;

-- HSync generator
process(hcount)
begin
	hblank <= '1';
	CurCol <= hcount;

	if hcount>=640
		then 
			hblank <= '0';
			CurCol <= (others => '0');
	end if;

	if (hcount<=755 and hcount>=659)
		then HSync <= '0';
		else HSync <= '1';
	end if;
end process;

-- Vertical line counter
vcounter: process(PixelClock, reset)
begin
	if reset = '1'
		then vcount <= (others => '0');
	elsif rising_edge(PixelClock)
		then
			if hcount=799
				then
					if vcount=524
						then vcount <= (others => '0');
						else vcount <= vcount + 1;
					end if;
			end if;
	end if;
end process;

-- VSync generator
process(vcount)
begin
	vblank <= '1';
	CurRow <= vcount;

	if vcount>=480
		then 
			vblank <= '0';
			CurRow <= (others => '0');
	end if;

	if (vcount<=494 and vcount>=493)
		then VSync <= '0';
		else VSync <= '1';
	end if;
end process;

VideoOn <= VBlank and HBlank;

end behavioral;