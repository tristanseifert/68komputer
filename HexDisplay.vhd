library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

--
-- This is a simple seven-segment hexadecimal display driver. Connect up
-- InVal to a nybble, Display to a display, and values 0-F will be displayed
-- in glorious characters.
--
-- When reset, the display will show three vertical bars.
--

entity HexDisplay is
	PORT (
		clk:			IN std_logic;
		reset:		IN std_logic;
		
		Display: 	OUT std_logic_vector(6 downto 0) := (others => '1');
		InVal:		IN	 std_logic_vector(3 downto 0)
	);
end HexDisplay;

architecture behavioral of HexDisplay is
begin

process (reset, clk, InVal)
begin
	if reset='1'
	then
		Display <= "0110110";
	elsif rising_edge(clk) then
		case InVal is
			when x"0" =>
				Display <= "1000000";
				
			when x"1" =>
				Display <= "1001111";
				
			when x"2" =>
				Display <= "0100100";
				
			when x"3" =>
				Display <= "0110000";
				
			when x"4" =>
				Display <= "0011001";
				
			when x"5" =>
				Display <= "0010010";
				
			when x"6" =>
				Display <= "0000010";
				
			when x"7" =>
				Display <= "1111000";
				
			when x"8" =>
				Display <= "0000000";
				
			when x"9" =>
				Display <= "0011000";
				
			when x"A" =>
				Display <= "0001000";
				
			when x"B" =>
				Display <= "0000011";
				
			when x"C" =>
				Display <= "1000110";
				
			when x"D" =>
				Display <= "0100001";
				
			when x"E" =>
				Display <= "0000110";	
				
			when x"F" =>
				Display <= "0001110";
			
			when "ZZZZ" =>
				Display <= (others => '1');
		end case;
	end if;
end process;
end behavioral;