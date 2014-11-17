--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:    15:59:15 11/01/06
-- Design Name:    
-- Module Name:    videomem_master - Behavioral
-- Project Name:   
-- Target Device:  
-- Tool versions:  
-- Description:
-- This module is a Wishbone master which takes interrupts from the keyboard,
-- processes the scancodes and converts them to ascii and then uses the ascii
-- code to index into a lookup table to get pixels to write to display memory
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

---- Uncomment the following library declaration if instantiating
---- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity rock_master is
	Port ( clk_i : in std_logic;
          rst_i : in std_logic;
		    adr_o : out std_logic_vector(31 downto 0);
          dat_i : in std_logic_vector(31 downto 0);
          dat_o : out std_logic_vector(31 downto 0);
          ack_i : in std_logic;
          cyc_o : out std_logic;
          stb_o : out std_logic;
          we_o  : out std_logic;
			 location : inout std_logic_vector(31 downto 0);
			 res :inout std_logic);
end rock_master;

architecture Behavioral of rock_master is
	signal code, ascii, volume : std_logic_vector(7 downto 0);
	signal shift, ctrl, alt : std_logic;
	signal req : std_logic;


	signal current_addr : std_logic_vector(31 downto 0);
	type state_type is (FIRST,INIT, GETPIXELS1, GETPIXELS2, WAIT4MEMACK,ROCKS1,ROCKS2,ROCKS3,ROCKS4,ROCKS5,ROCKS6,ROCKS7);
	signal state : state_type;

	constant CHARS_PER_LINE : integer := 80;
	constant LINES_PER_PAGE : integer := 40;
	constant CHARS_PER_PAGE : integer := CHARS_PER_LINE * LINES_PER_PAGE;
	constant CHAR_WIDTH : integer := 8;
	constant CHAR_HEIGHT : integer := 12;
	constant PIXELS_PER_WORD : integer := 8;
	constant BITS_PER_PIXEL : integer := 4;

	signal txtcolor, bgcolor : std_logic_vector(BITS_PER_PIXEL-1 downto 0);
	signal pixels : std_logic_vector(CHAR_WIDTH-1 downto 0);
	signal reg_pixels : std_logic_vector(CHAR_WIDTH-1 downto 0);
	signal color_pixels : std_logic_vector(31 downto 0);
	signal current_char : integer range 0 to CHARS_PER_LINE-1;
	signal current_line,current_line1,current_line2,current_line3,current_line4
	,current_line5,current_line6,current_line7 : integer range 0 to LINES_PER_PAGE-1;
	signal scan_line : integer range 0 to CHAR_HEIGHT;
	signal pixelnum : integer range 0 to CHAR_WIDTH-1;
	signal fall_counter1,fall_counter2,fall_counter3,fall_counter4,fall_counter5,
		fall_counter6,fall_counter7 : integer;
	signal s1,s2,s3,s4,s5,s6,s7 : integer;
	
	signal fall_speed : integer := 10000;
	signal temp : integer;
	signal temp2 : integer;
	signal line_count : integer;
	signal rock_count : integer;
	signal seed1 : integer range 0 to 4634;
	signal seed2 : integer range 0 to 4634;
	signal newrock : integer;
	signal done1,done2,done3,done4,done5,done6,done7: std_logic;
	signal rock1,rock2,rock3,rock4,rock5,rock6,rock7 : integer range 0 to CHARS_PER_LINE-1;
	
	type rock_array is array (0 to CHARS_PER_LINE -1 ) of std_logic;
	signal rockA : rock_array;
	
	type line_array is array (0 to CHARS_PER_LINE -1) of integer;
	signal lineA : line_array;
	
	signal buffer_base : std_logic_vector(31 downto 0);
begin

	-- the lookup table maps the ascii code to the pixels for that particular character.  
	-- The line input determines which of the 12 lines of the character we want.  The
	-- lookup table is implemented with the builtin registered BRAM, so the output is
	-- available only at the next clock cycle
	lut : entity work.char8x12_lookup_table
		port map( clk => clk_i, reset => rst_i, ascii => ascii, line => scan_line, pixels => pixels );
	
	-- convert the scancode signal given the shift, ctrl, and alt flags into
	-- an eight bit ASCII signal.
	
	s2a : entity work.scancode2ascii
		port map ( scancode => code,
						ascii => ascii,
						shift => shift,
						ctrl => ctrl,
						alt => alt );

	-- txtcolor is the color of the text and bgcolor is the color of the background
--	txtcolor <= "11111111"; -- white
--	bgcolor <= "00000011";  -- blue
	txtcolor <= "1111"; -- white
	bgcolor <= "0001"; -- blue

	-- the following code sets the color_pixels word based on the reg_pixels byte which is a registered
	-- version of the pixels byte that comes from the lookup table.  When reg_pixels is '1', we use the
	-- text color, otherwise we use the background color
	gen1 : for i in 0 to PIXELS_PER_WORD-1 generate
--		color_pixels(4*i+3 downto 4*i) <= "0" & txtcolor when reg_pixels(i)='1' else "0" & bgcolor;
		color_pixels(BITS_PER_PIXEL*i+BITS_PER_PIXEL-1 downto BITS_PER_PIXEL*i) <= txtcolor when reg_pixels(i)='1' else bgcolor;
	end generate;
	
	-- the following process is a 6 state FSM
	-- INITMEM	 go through all of memory and intialize to the bgcolor
	-- WAIT4IRQ  wait for the interrupt from the wb_ps2_kb module
	-- WAIT4CODE wait for the ack from wb_ps2_kb module indicating that the
	--           scancode is on the dat_i lines.  Once we get the scancode,
	--           check if it is a special scancode that sets one of the ctrl,
	--           shift, or alt flags or an F0 scancode that indicates a key up
	--           event.   When we get a shift, ctrl, or alt key down we keep track
	--           that the key is held down by setting the shift/ctrl/alt_down flag.
	--           The flag is cleared when we get the appropriate F0 key up scancode.
	--           If the key pressed was a normal key, go to WAIT4MEMACK, otherwise
	--           go back to START and wait for a new scancode
	-- GETPIXELS1 wait for the pixels byte to be ready from the lookup table
	-- GETPIXELS2 save the pixels in reg_pixels and check for special characters
	-- WAIT4MEMACK wait for the color_pixels word to be written to memory and then 
	--             increment the line, column and row as appropriate
	
	process( clk_i, rst_i ) -- process that controls the ship
		variable next_state : state_type;
		variable scancode : std_logic_vector(7 downto 0);
	begin
		if ( rst_i = '1' ) then
			current_char <= 0;
			current_line <= 0;
			scan_line <= 0;
			rock_count <= 1;
			res <= '0';
			--done <= '0';
			--fall_counter <= 0;
			reg_pixels <= X"00";
			state <= FIRST;
			
		
			
		elsif ( clk_i'event and clk_i='1' ) then
			case state is
			
			when FIRST =>
			res <= '0';
			temp2 <= 0;
			current_line <= 0;
			scan_line <= 0;
--			fall_counter <= 0;
			temp <= 0;
			rock_count <= 1;
			reg_pixels <= X"00";
			code <= X"44";
			
			s1 <= 10000;
			s2<= 8000;
			s3 <= 20000;
			s4 <= 15000;
			s5 <= 5000;
			s6 <= 6000;
			s7 <= 3000;
			
			
			rock1 <= 1;
			rock2 <= 3;
			rock3 <= 6;
			rock4 <= 11;
			rock5 <= 37;
			rock6 <= 54;
			rock7 <= 65;
			--this will eventually be replaced with randoms
--			rockA(4) <= '1';
--			rockA(7) <= '1';
--			rockA(8) <= '1';
--			rockA(12) <= '1';
--			rockA(29) <= '1';
--			rockA(33) <= '1';
--			rockA(41) <= '1';
--			rockA(59) <= '1';
--			rockA(65) <= '1';
--			rockA(77) <= '1';
			state <= INIT;
			when INIT =>
			seed1 <= seed1 + 1;

			if conv_std_logic_vector(current_line*current_char,32) = location then res <= '1'; state <= FIRST; end if;
			
			if done1 = '1' then
				rock1 <= ((seed1*seed2) mod 64) + 1; 
				done1 <= '0';
			end if;
			
			if done2 = '1' then
				rock2 <= ((seed1*seed2) mod 64) + 1; 
				done2 <= '0';
			end if;
			
			if done3 = '1' then
				rock3 <= ((seed1*seed2) mod 64) + 1; 
				done3 <= '0';
			end if;
			
			if done4 = '1' then
				rock4 <= ((seed1*seed2) mod 64) + 1; 
				done4 <= '0';
			end if;
			
			if done5 = '1' then
				rock5 <= ((seed1*seed2) mod 64) + 1; 
				done5 <= '0';
			end if;
			
			if done6 = '1' then
				rock6 <= ((seed1*seed2) mod 64) + 1; 
				done6 <= '0';
			end if;
			
			if done7 = '1' then
				rock7 <= ((seed1*seed2) mod 64) + 1; 
				done7 <= '0';
			end if;
			state <= GETPIXELS1;		

			when GETPIXELS1 =>
				-- wait for pixels to be ready from lookup table
				state <= GETPIXELS2;

			when GETPIXELS2 =>
				pixelnum <= 0;
				
				-- if the character is a back space, backup a character
					case rock_count is
						when 1 =>
							state <= ROCKS1;
						when 2 =>
							state <= ROCKS2;
						when 3 =>
							state <= ROCKS3;
						when 4 =>
							state <= ROCKS4;
						when 5 =>
							state <= ROCKS5;
						when 6 =>
							state <= ROCKS6;
						when 7 =>
							state <= ROCKS7;
						when others => state <= WAIT4MEMACK;
						end case;
					
			when ROCKS1 =>
			current_line <= current_line1;
			current_char <= rock1;
				if fall_counter1 = s1 then 
					fall_counter1 <= 0;
					current_line1 <= current_line1 + 1;
					if current_line1 = LINES_PER_PAGE-1 then current_line1 <= 0; done1 <= '1'; end if;
				elsif fall_counter1 > s1 - 500 then
					reg_pixels <= X"00";
					fall_counter1 <= fall_counter1 + 1;
				else
				fall_counter1 <= fall_counter1 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when ROCKS2 =>
			current_line <= current_line2;
			current_char <= rock2;
				if fall_counter2 = s2 then 
					fall_counter2 <= 0;
					current_line2 <= current_line2 + 1;
					if current_line2 = LINES_PER_PAGE-1 then current_line2 <= 0; done2 <= '1'; end if;
				elsif fall_counter2 > s2 - 500 then
					reg_pixels <= X"00";
					fall_counter2 <= fall_counter2 + 1;
				else
				fall_counter2 <= fall_counter2 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when ROCKS3 =>
			current_line <= current_line3;
			current_char <= rock3;
				if fall_counter3 = s3 then 
					fall_counter3 <= 0;
					current_line3 <= current_line3 + 1;
					if current_line3 = LINES_PER_PAGE-1 then current_line3 <= 0; done3 <= '1'; end if;
				elsif fall_counter3 > s3 - 500 then
					reg_pixels <= X"00";
					fall_counter3 <= fall_counter3 + 1;
				else
				fall_counter3 <= fall_counter3 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when ROCKS4 =>
			current_line <= current_line4;
			current_char <= rock4;
				if fall_counter4 = s4 then 
					fall_counter4 <= 0;
					current_line4 <= current_line4 + 1;
					if current_line4 = LINES_PER_PAGE-1 then current_line4 <= 0; done4 <= '1'; end if;
				elsif fall_counter4 > s4 - 500 then
					reg_pixels <= X"00";
					fall_counter4 <= fall_counter4 + 1;
				else
				fall_counter4 <= fall_counter4 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when ROCKS5 =>
			current_line <= current_line5;
			current_char <= rock5;
				if fall_counter5 = s5 then 
					fall_counter5 <= 0;
					current_line5 <= current_line5 + 1;
					if current_line5 = LINES_PER_PAGE-1 then current_line5 <= 0; done5 <= '1'; end if;
				elsif fall_counter5 > s5 - 500 then
					reg_pixels <= X"00";
					fall_counter5 <= fall_counter5 + 1;
				else
				fall_counter5 <= fall_counter5 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when ROCKS6 =>
			current_line <= current_line6;
			current_char <= rock6;
				if fall_counter6 = s6 then 
					fall_counter6 <= 0;
					current_line6 <= current_line6 + 1;
					if current_line6 = LINES_PER_PAGE-1 then current_line6 <= 0; done6 <= '1'; end if;
				elsif fall_counter6 > s6 - 500 then
					reg_pixels <= X"00";
					fall_counter6 <= fall_counter6 + 1;
				else
				fall_counter6 <= fall_counter6 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when ROCKS7 => 
			current_line <= current_line7;
			current_char <= rock7;
				if fall_counter7 = s7 then 
					fall_counter7 <= 0;
					current_line7 <= current_line7 + 1;
					if current_line7 = LINES_PER_PAGE-1 then current_line7 <= 0; done7 <= '1'; end if;
				elsif fall_counter7 > s7 - 500 then
					reg_pixels <= X"00";
					fall_counter7 <= fall_counter7 + 1;
				else
				fall_counter7 <= fall_counter7 + 1;
				reg_pixels <= pixels;
				end if;
			state <= WAIT4MEMACK;
			
			when WAIT4MEMACK =>
			if conv_std_logic_vector(current_line*current_char,32) = location then res <= '1'; state <= FIRST; end if;
			if current_line = 0 then reg_pixels <= x"00"; end if;
			seed2 <= seed2+1;
				if ( ack_i = '1' ) then
					if ( scan_line = CHAR_HEIGHT-1 ) then
						state <= INIT;
						rock_count <= rock_count + 1;
						if rock_count = 8 then rock_count <= 1; end if;
	--					cyc_o <= '0';
						scan_line <= 0;
					else
						-- check if we have written all the pixels for this scanline character
						if (pixelnum < CHAR_WIDTH-PIXELS_PER_WORD) then
							state <= WAIT4MEMACK;
							pixelnum <= pixelnum + PIXELS_PER_WORD;
						else
							scan_line <= scan_line + 1;
							state <= GETPIXELS1;
						end if;
					end if;
				end if;

			when others => state <= INIT;
			end case;
		end if;
	end process;

	-- set dat_o to the color pixels output
	dat_o <= color_pixels;

	-- we_o to '1' when we are in WAIT4MEMACK where we do writes
	we_o <= '1' when state = WAIT4MEMACK or state=INIT else '0';

	-- set the adr_o appropriately depending on which state we're in.  
	-- base address 
	-- 0x4 when reading from the keyboard,
	-- 0x0 when writing to memory
	adr_o <= current_addr;


	buffer_base <= X"00000000";
	current_addr <= buffer_base + (current_line*CHARS_PER_LINE*CHAR_HEIGHT + current_char + scan_line*CHARS_PER_LINE + 0)*CHAR_WIDTH/PIXELS_PER_WORD*4;
--	current_addr <= buffer_base + (current_line*CHARS_PER_LINE*CHAR_HEIGHT + current_char + scan_line*CHARS_PER_LINE)*CHAR_WIDTH/PIXELS_PER_WORD*4;
	--adr_o <=  current_addr;
	-- grab the bus when we are in a state that is reading or writing from a slave module
	req <= '1' when state =INIT or state=WAIT4MEMACK else '0';
	
	stb_o <= req;
	cyc_o <= req;

end Behavioral;
