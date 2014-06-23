library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

--
-- SDRAM controller. This uses the Altera sdr_sdram component to interface with
-- the SDRAM, and couple it to the 68k bus.
--

entity BusSDRAM is
	PORT(
		-- system signals
		reset:				IN std_logic;
		reset_n:				IN std_logic;
		sdram_clk:			IN std_logic; -- 100 MHz
		
		-- CPU bus
		bus_cs:				IN std_logic; -- when high, outs is Z
		
		bus_clk:				IN std_logic; -- clock for bus
		bus_address:		IN std_logic_vector(22 downto 0);
		bus_data:			INOUT std_logic_vector(15 downto 0);
		
		bus_rw:				IN std_logic;
		bus_as:				IN std_logic;
		bus_dtack:			OUT std_logic;
		
		bus_uds:				IN std_logic;
		bus_lds:				IN std_logic;
	
		-- connect to SDRAM
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
		DRAM_UDQM:			OUT std_logic
	);
end BusSDRAM;

architecture behavioral of BusSDRAM is
	signal sdr_addr: std_logic_vector(22 downto 0);
	
	signal sdr_cmd: std_logic_vector(2 downto 0);
	signal sdr_cmdack: std_logic;
	
	signal sdr_din: std_logic_vector(15 downto 0);
	signal sdr_dout: std_logic_vector(15 downto 0);
	signal sdr_data_mask: std_logic_vector(1 downto 0);
	
	signal dram_bank: std_logic_vector(1 downto 0);
	signal dram_cs:	std_logic_vector(1 downto 0);
	signal dram_dqm:	std_logic_vector(1 downto 0);
begin

-- contat separate bank signals into one
DRAM_BA_0 <= dram_bank(0);
DRAM_BA_1 <= dram_bank(1);

DRAM_CS_N <= dram_cs(0);

DRAM_LDQM <= dram_dqm(0);
DRAM_UDQM <= dram_dqm(1);

-- SDRAM controller
	u_sdram_controller: entity work.sdr_sdram(RTL)
		port map(
			CLK => sdram_clk,
			RESET_N => reset_N,
			
			-- interfacing with controller
			ADDR => sdr_addr,
			
			DATAIN => sdr_din,
			DATAOUT => sdr_dout,
			DM => sdr_data_mask, -- data masks
			
			CMD => sdr_cmd,
			CMDACK => sdr_cmdack,
			
			-- to SDRAM
			SA => DRAM_ADDR,
			BA => dram_bank,
			CS_N => dram_cs,
			CKE => DRAM_CKE,
			RAS_N => DRAM_RAS_N,
			CAS_N => DRAM_CAS_N,
			WE_N => DRAM_WE_N,
			DQ => DRAM_DQ,
			DQM => dram_dqm
		);

-- 68k bus interface
process(bus_clk, reset, bus_cs, bus_rw)
begin
	-- in reset state, don't drive the bus
	if reset='0' then
		bus_data <= (others => 'Z');
		bus_dtack <= 'Z';	
	elsif rising_edge(bus_clk) then
		-- is chip select asserted?
		if bus_cs='0' then
			-- write cycle
			if bus_rw='0' then
				bus_dtack <= '1';
			-- read cycle
			else
				bus_dtack <= '1';
			end if;
		-- not selected: don't drive bus
		else
			bus_data <= (others => 'Z');
			bus_dtack <= 'Z';
		end if;
	end if;
end process;

end behavioral;