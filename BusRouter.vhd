library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity BusRouter is 
	PORT(
		SW:					IN std_logic_vector(9 downto 0);
		KEY:					IN std_logic_vector(3 downto 0);
		LEDR:					OUT std_logic_vector(9 downto 0) := (others => '0');
		LEDG:					OUT std_logic_vector(7 downto 0) := (others => '0');
		
		CLOCK_24:			IN std_logic_vector(1 downto 0);
		CLOCK_27:			IN std_logic_vector(1 downto 0);
		CLOCK_50:			IN std_logic;
		
		-- video
		VGA_R:				OUT std_logic_vector(3 downto 0);
		VGA_G:				OUT std_logic_vector(3 downto 0);
		VGA_B:				OUT std_logic_vector(3 downto 0);
		VGA_VS:				OUT std_logic := '0';
		VGA_HS:				OUT std_logic := '0';
		
		-- SRAM
		SRAM_ADDR: 			OUT std_logic_vector(17 downto 0);
		SRAM_DQ: 			INOUT std_logic_vector(15 downto 0);
		
		SRAM_CE_N:			OUT std_logic;
		SRAM_OE_N:			OUT std_logic;
		SRAM_WE_N:			OUT std_logic;
		
		SRAM_LB_N:			OUT std_logic;
		SRAM_UB_N:			OUT std_logic;
		
		-- SDRAM
		DRAM_CS_N:			OUT std_logic;
		DRAM_WE_N:			OUT std_logic;
		
		DRAM_CAS_N:			OUT std_logic;
		DRAM_RAS_N:			OUT std_logic;
		DRAM_ADDR:			OUT std_logic_vector(11 downto 0);
		DRAM_BA_0:			OUT std_logic;
		DRAM_BA_1:			OUT std_logic;
		
		DRAM_CKE:			OUT std_logic;
		DRAM_CLK:			OUT std_logic;
		
		DRAM_DQ:				INOUT std_logic_vector(15 downto 0);
		DRAM_LDQM:			OUT std_logic;
		DRAM_UDQM:			OUT std_logic;
		
		-- Flash memory
		FL_ADDR:				OUT std_logic_vector(21 downto 0);
		FL_DQ:				INOUT std_logic_vector(7 downto 0);
		FL_OE_N:				OUT std_logic := '1';
		FL_RST_N:			OUT std_logic := '1';
		FL_WE_N:				OUT std_logic := '1';
		
		-- PS2
		PS2_CLK:				INOUT std_logic;
		PS2_DAT:				INOUT std_logic;
		
		-- SD card
		SD_MISO:				IN std_logic;
		SD_MOSI:				OUT std_logic;
		SD_SCLK:				OUT std_logic;
		SD_CS:				OUT std_logic;
		
		-- UART
		UART_RXD:			IN std_logic;
		UART_TXD:			OUT std_logic;
		
		-- audio codec
		I2C_SCLK:			INOUT std_logic;
		I2C_SDAT:			INOUT std_logic;
		
		AUD_ADCDAT:			IN std_logic;
		AUD_ADCLRCK:		OUT std_logic;
		
		AUD_BCLK:			OUT std_logic;
		AUD_XCK:				OUT std_logic;
		
		AUD_DACDAT:			OUT std_logic;
		AUD_DACLRCK:		OUT std_logic;
		
		-- seven segment displays
		HEX0:					OUT std_logic_vector(6 downto 0);
		HEX1:					OUT std_logic_vector(6 downto 0);
		HEX2:					OUT std_logic_vector(6 downto 0);
		HEX3:					OUT std_logic_vector(6 downto 0)
	);
end BusRouter;

architecture behavioral of BusRouter is
	signal clk_cpu:		std_logic;
	signal clk_sdram:		std_logic;

	signal sys_reset:		std_logic := '1';

	-- 68k bus: system control
	signal bus_reset:		std_logic := '1';
	signal bus_clk:		std_logic; -- CPU clock
	signal bus_halt:		std_logic := '1';
	signal bus_error:		std_logic := '1';
	
	-- 68k bus: data
	signal bus_data:		std_logic_vector(15 downto 0) := (others => 'Z');
	signal bus_addr:		std_logic_vector(23 downto 0) := (others => '0');

	-- 68k bus: bus control
	signal bus_as:			std_logic := '1';
	signal bus_rw:			std_logic := '1'; -- read = 1, write = 0
	
	signal bus_uds:		std_logic := '1'; -- upper and lower byte strobes
	signal bus_lds:		std_logic := '1';
	
	signal bus_dtack:		std_logic := '1'; -- data acknowledge, driven by peripheral
	
	-- 68k bus: bus arbitration
	signal bus_br:			std_logic := '1'; -- assert to request bus
	signal bus_bg:			std_logic := '1'; -- asserted when bus is free
	signal bus_bgack:		std_logic := '1'; -- assert to acknowledge bus request
	
	-- 68k bus: interrupt control
	signal bus_irq:		std_logic_vector(2 downto 0) := (others => '1');
	
	-- 68k bus: processor status
	signal bus_fc:			std_logic_vector(3 downto 0);
	
	-- 5Hz blink clock generator
	signal blink_clk:		std_logic;
	
	-- chip selects for various HW (low active)
	signal cs_rom:			std_logic := '1';
	signal cs_ram:			std_logic := '1';
	signal cs_video:		std_logic := '1';
begin
	-- VDP
	u_VideoController: entity work.VideoController(behavioral)
		port map(
			reset => sys_reset,
	 
			In_Clk_24 => CLOCK_24(0),
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
			SRAM_UB => SRAM_UB_N,
			
			-- bus interface
			bus_clk => bus_clk,
			bus_data => bus_data,
			bus_address => bus_addr(18 downto 0),
			
			bus_rw => bus_rw,
			bus_as => bus_as,
			bus_dtack => bus_dtack,
			
			bus_uds => bus_uds,
			bus_lds => bus_lds,
			
			bus_cs => cs_video
		);
	
	-- SDRAM controller
	u_sdram: entity work.BusSDRAM(behavioral)
		port map(
			reset => sys_reset,
			reset_n => bus_reset,
			sdram_clk => clk_sdram,
			
			bus_cs => cs_ram,
			bus_clk => clk_cpu,
			bus_address => bus_addr (22 downto 0),
			bus_data => bus_data,
			
			bus_rw => bus_rw,
			bus_as => bus_as,
			bus_dtack => bus_dtack,
			
			bus_uds => bus_uds,
			bus_lds => bus_lds,
			
			DRAM_CS_N => DRAM_CS_N,
			DRAM_WE_N => DRAM_WE_N,
			
			DRAM_CAS_N => DRAM_CAS_N,
			DRAM_RAS_N => DRAM_RAS_N,
			
			DRAM_ADDR => DRAM_ADDR,
			DRAM_BA_0 => DRAM_BA_0,
			DRAM_BA_1 => DRAM_BA_1,
			
			DRAM_CKE => DRAM_CKE,
			DRAM_CLK => DRAM_CLK,
			
			DRAM_DQ => DRAM_DQ,
			DRAM_LDQM => DRAM_LDQM,
			DRAM_UDQM => DRAM_UDQM
		);
	
	-- bus PLL
	u_buspll: entity work.BusPLL(SYN)
		port map(
			areset => sys_reset,
			inclk0 => CLOCK_50,
			c0 => clk_cpu,
			c1 => clk_sdram
		);
		
	-- debug monitor
	u_monitor: entity work.BusMonitor(behavioral)
		port map(
			clk_cpu => clk_cpu,
			blink_clk => blink_clk,
			sys_reset => sys_reset,
		
			bus_reset => bus_reset,
			bus_clk => bus_clk,
			bus_halt => bus_halt,
			bus_error => bus_error,
			
			bus_data => bus_data,
			bus_addr => bus_addr,
			
			bus_as => bus_as,
			bus_rw => bus_rw,
			bus_uds => bus_uds,
			bus_lds => bus_lds,
			bus_dtack => bus_dtack,

			bus_br => bus_br,
			bus_bg => bus_bg,
			bus_bgack => bus_bgack,
			bus_irq => bus_irq,
			
			HEX0 => HEX0,
			HEX1 => HEX1,
			HEX2 => HEX2,
			HEX3 => HEX3,
			
			SW => SW,
			KEY => KEY,
			LEDR => LEDR,
			LEDG => LEDG
		);
		
-- Address decoder: tied to the FALLING edge of bus_clk
process (bus_clk, sys_reset, bus_as)
begin
	-- if reset, make sure everything is deselected
	if sys_reset='1' then
	
	-- decode address
	elsif falling_edge(bus_clk) then
		-- is the address on the bus valid?
		if bus_as='0' then
			-- decode high nybble
			case bus_addr(23 downto 20) is
				when x"0" =>
					cs_rom <= '0';
				when x"1" =>
					cs_ram <= '0';
				when x"2" =>
					cs_ram <= '0';
				when x"3" =>
					cs_ram <= '0';
				when x"4" =>
					cs_ram <= '0';
				when x"5" =>
					cs_ram <= '0';
				when x"6" =>
					cs_ram <= '0';
				when x"7" =>
					cs_ram <= '0';
				when x"8" =>
					cs_ram <= '0';
				when x"9" => -- video controller
					cs_video <= '0';
				when x"A" =>
				when x"B" =>
				when x"C" =>
				when x"D" =>
				when x"E" =>
				when x"F" =>
			end case;
		else
			-- address invalid
			cs_rom <= '1';
			cs_ram <= '1';
			cs_video <= '1';
		end if;
	end if;
end process;
	
-- LED blink clock generator
process (clk_cpu, sys_reset)
	variable cnt: integer := 0;
begin
	if sys_reset='1'
		then
			cnt := 0;
	elsif rising_edge(clk_cpu) then
		if cnt = 741337 
			then
				blink_clk <= NOT blink_clk;
				cnt := 0;
			else
				cnt := cnt + 1;
		end if;
	end if;
end process;
	
	-- reset logic
	bus_reset <= NOT sys_reset;
end behavioral;