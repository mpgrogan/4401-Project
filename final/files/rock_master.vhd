
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
			 xlocation : inout std_logic_vector(7 downto 0);
			 ylocation : inout std_logic_vector(7 downto 0);
			 res :inout std_logic;
			 st : in std_logic;
			 test : in std_logic);
end rock_master;

architecture Behavioral of rock_master is
	signal code, ascii, volume : std_logic_vector(7 downto 0);
	signal shift, ctrl, alt : std_logic;
	signal req,tick,tock : std_logic;


	signal current_addr : std_logic_vector(31 downto 0);
	type state_type is (FIRST,INIT, GETPIXELS1, GETPIXELS2, WAIT4MEMACK,ROCKS1,ROCKS2,ROCKS3,ROCKS4,ROCKS5,ROCKS6,ROCKS7,
	ROCKS8,ROCKS9,ROCKS10,ROCKS11,ROCKS12,ROCKS13,ROCKS14,ROCKS15,ROCKS16,ROCKS17,ROCKS18,ROCKS19,ROCKS20,ROCKS21,ROCKS22,
	ROCKS23,ROCKS24,ROCKS25,ROCKS26,ROCKS27,ROCKS28,ROCKS29,ROCKS30,CLOCK,HOME,CLEARSCREEN);
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
	,current_line5,current_line6,current_line7,current_line8,current_line9,current_line10,current_line11,current_line12
	,current_line13,current_line14,current_line15,current_line16,current_line17
	,current_line18,current_line19,current_line20,current_line21,current_line22
	,current_line23,current_line24,current_line25,current_line26,current_line27
	,current_line28,current_line29,current_line30 : integer range 0 to LINES_PER_PAGE-1;
	signal scan_line : integer range 0 to CHAR_HEIGHT;
	signal pixelnum : integer range 0 to CHAR_WIDTH-1;
	signal fall_counter1,fall_counter2,fall_counter3,fall_counter4,fall_counter5,
		fall_counter6,fall_counter7,fall_counter8,fall_counter9,fall_counter10,fall_counter11,fall_counter12,
		fall_counter13,fall_counter14,fall_counter15,fall_counter16,fall_counter17,fall_counter18,fall_counter19,
		fall_counter20,fall_counter21,fall_counter22,
		fall_counter23,fall_counter24,fall_counter25,fall_counter26,fall_counter27,fall_counter28,fall_counter29,
		fall_counter30 : integer;
	signal s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20,s21,s22,s23,s24,s25,s26,s27,s28,s29,s30 : integer;
	
	signal fall_speed : integer := 10000;
	signal temp : integer;
	signal temp2 : integer;
	signal line_count : integer;
	signal rock_count : integer;
	signal seed1 : integer range 0 to 4634;
	signal seed2 : integer range 0 to 4634;
	signal seed3 : integer range 0 to 15;
	signal newrock : integer;
	signal max_rocks: integer := 31;
	signal timer: integer RANGE 0 to 500001000;
	signal current_time : std_logic_vector(7 downto 0);
	
			signal start,restart,from_rock : std_logic;
	signal done1,done2,done3,done4,done5,done6,done7,done8,done9,done10,done11,done12,done13,done14,done15,done16,
	done17,done18,done19,done20,done21,done22,done23,done24,done25,done26,
	done27,done28,done29,done30: std_logic;
	signal rock1,rock2,rock3,rock4,rock5,rock6,rock7,rock8,rock9,rock10,rock11,rock12,rock13,rock14,rock15
,rock16,rock17,rock18,rock19,rock20,rock21,rock22,rock23,rock24,rock25
,rock26,rock27,rock28,rock29,rock30	: integer range 0 to CHARS_PER_LINE-1;
	
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
			
			current_line <= 0;
			current_line1 <= 0;
			current_line2<= 0;
			current_line3<= 0;
			current_line4<= 0;
			current_line5<= 0;
			current_line6<= 0;
			current_line7<= 0;
			current_line8<= 0;
			current_line9<= 0;
			current_line10<= 0;
			current_line11<= 0;
			current_line12<= 0;
			current_line13<= 0;
			current_line14<= 0;
			current_line15<= 0;
			current_line16<= 0;
			current_line17<= 0;
			current_line18<= 0;
			current_line19<= 0;
			current_line20<= 0;
			current_line21<= 0;
			current_line22<= 0;
			current_line23<= 0;
			current_line24<= 0;
			current_line25<= 0;
			current_line26<= 0;
			current_line27<= 0;
			current_line28<= 0;
			current_line29<= 0;
			current_line30<= 0;
			 fall_counter1<= 0;
			 fall_counter2<= 0;
			 fall_counter3<= 0;
			 fall_counter4<= 0;
			 fall_counter5<= 0;
			 fall_counter6<= 0;
			 fall_counter7<= 0;
			 fall_counter8<= 0;
			 fall_counter9<= 0;
			 fall_counter10<= 0;
			 fall_counter11<= 0;
			 fall_counter12<= 0;
			fall_counter13<= 0;
			fall_counter14<= 0;
			fall_counter15<= 0;
			fall_counter16<= 0;
			fall_counter17<= 0;
			fall_counter18<= 0;
			fall_counter19<= 0;
			fall_counter20 <= 0;
			
			 fall_counter21<= 0;
			 fall_counter22<= 0;
			fall_counter23<= 0;
			fall_counter24<= 0;
			fall_counter25<= 0;
			fall_counter26<= 0;
			fall_counter27<= 0;
			fall_counter28<= 0;
			fall_counter29<= 0;
			fall_counter30 <= 0;
			--done <= '0';
			--fall_counter <= 0;
			reg_pixels <= X"00";
			state <= FIRST;
			
		
			
		elsif ( clk_i'event and clk_i='1' ) then
			case state is
			
			
			
			when FIRST =>
			--max_rocks <= 20;
			res <= '0';
			temp2 <= 0;
			current_line <= 0;
			current_char <= 0;
			scan_line <= 0;
			current_line1 <= 0;
			current_line2<= 0;
			current_line3<= 0;
			current_line4<= 0;
			current_line5<= 0;
			current_line6<= 0;
			current_line7<= 0;
			current_line8<= 0;
			current_line9<= 0;
			current_line10<= 0;
			current_line11<= 0;
			current_line12<= 0;
			current_line13<= 0;
			current_line14<= 0;
			current_line15<= 0;
			current_line16<= 0;
			current_line17<= 0;
			current_line18<= 0;
			current_line19<= 0;
			current_line20<= 0;
			
			current_line21<= 0;
			current_line22<= 0;
			current_line23<= 0;
			current_line24<= 0;
			current_line25<= 0;
			current_line26<= 0;
			current_line27<= 0;
			current_line28<= 0;
			current_line29<= 0;
			current_line30<= 0;
			 fall_counter1<= 0;
			 fall_counter2<= 0;
			 fall_counter3<= 0;
			 fall_counter4<= 0;
			 fall_counter5<= 0;
			 fall_counter6<= 0;
			 fall_counter7<= 0;
			 fall_counter8<= 0;
			 fall_counter9<= 0;
			 fall_counter10<= 0;
			 fall_counter11<= 0;
			 fall_counter12<= 0;
			fall_counter13<= 0;
			fall_counter14<= 0;
			fall_counter15<= 0;
			fall_counter16<= 0;
			fall_counter17<= 0;
			fall_counter18<= 0;
			fall_counter19<= 0;
			fall_counter20 <= 0;
			
			 fall_counter21<= 0;
			 fall_counter22<= 0;
			fall_counter23<= 0;
			fall_counter24<= 0;
			fall_counter25<= 0;
			fall_counter26<= 0;
			fall_counter27<= 0;
			fall_counter28<= 0;
			fall_counter29<= 0;
			fall_counter30 <= 0;
--			fall_counter <= 0;
			temp <= 0;
			rock_count <= 1;
			reg_pixels <= X"00";
			code <= X"44";
			
			s1 <= 1310;
			s2<= 2700;
			s3 <= 3888;
			s4 <= 2500;
			s5 <= 1300;
			s6 <= 1700;
			s7 <= 2000;
			s8 <= 2500;
			s9 <= 2890;
			s10 <= 3171;
			s11 <= 1393;
			s12 <= 3029;
			s13 <= 1169;
			s14 <= 1755;
			s15 <= 3000;
			s16 <= 3700;
			s17 <= 2500;
			s18 <= 3155;
			s19 <= 1240;
			s20 <= 3100;
			s21 <= 2600;
			s22 <= 1000;
			s23 <= 2500;
			s24 <= 3170;
			s25 <= 1500;
			s26 <= 3500;
			s27 <= 3000;
			s28 <= 1500;
			s29 <= 1699;
			s30 <= 2167;
			
			rock1 <= 1;
			rock2 <= 5;
			rock3 <= 9;
			rock4 <= 13;
			rock5 <= 17;
			rock6 <= 21;
			rock7 <= 25;
			rock8 <= 29;
			rock9 <= 33;
			rock10 <= 37;
			rock11 <= 41;
			rock12 <= 77;
			rock13 <= 45;
			rock14 <= 49;
			rock15 <= 53;
			rock16 <= 57;
			rock17 <= 61;
			rock18 <= 65;
			rock19 <= 69;
			rock20 <= 73;
			
			rock21 <= 42;
			rock22 <= 78;
			rock23 <= 46;
			rock24 <= 50;
			rock25 <= 54;
			rock26 <= 58;
			rock27 <= 38;
			rock28 <= 33;
			rock29 <= 28;
			rock30 <= 21;
			
			
			state <= CLEARSCREEN;
			
			when CLEARSCREEN =>
				start <= '0';
				code <=X"29";
				if ( current_char = CHARS_PER_LINE-1 ) then
					current_char <= 0;
					if ( current_line = LINES_PER_PAGE-1 ) then
						current_char <= 0;
						current_line <= 0;
						code <= X"44";
						state <= HOME;
					else
						current_line <= current_line + 1;
					end if;
				else
						current_char <= current_char + 1;
						state <= GETPIXELS1;
				end if;
			when HOME =>
			code <= X"44";
				 if st = '1' then state <= INIT; start <= '1'; end if;
				 
			when INIT =>
			seed1 <= seed1 + 1;
			if test = '1' then state <= FIRST; end if;
			
			--if inc = '1' then max_rocks <= max_rocks + 1; end if;
			
			
			
			if done1 = '1' then
				rock1 <= ((seed1*seed2) mod 64) + 1; 
				done1 <= '0';
			end if;
			
			if done2 = '1' then
				rock2 <= ((seed1*seed2) mod 64) + seed3; 
				done2 <= '0';
			end if;
			
			if done3 = '1' then
				rock3 <= ((seed1*seed2) mod 64) + seed3;
				done3 <= '0';
			end if;
			
			if done4 = '1' then
				rock4 <= ((seed1*seed2) mod 64) + seed3;
				done4 <= '0';
			end if;
			
			if done5 = '1' then
				rock5 <= ((seed1*seed2) mod 64) + seed3;
				done5 <= '0';
			end if;
			
			if done6 = '1' then
				rock6 <= ((seed1*seed2) mod 64) + seed3;
				done6 <= '0';
			end if;
			
			if done7 = '1' then
				rock7 <= ((seed1*seed2) mod 64) + seed3;
				done7 <= '0';
			end if;
			
			if done8 = '1' then
				rock8 <= ((seed1*seed2) mod 64) + seed3;
				done8 <= '0';
			end if;
			
			if done9 = '1' then
				rock9 <= ((seed1*seed2) mod 64) + seed3;
				done9 <= '0';
			end if;
			
			if done10 = '1' then
				rock10 <= ((seed1*seed2) mod 64) + seed3;
				done10 <= '0';
			end if;
			
			if done11 = '1' then
				rock11 <= ((seed1*seed2) mod 64) + seed3;
				done11 <= '0';
			end if;
			
			if done12 = '1' then
				rock12 <= ((seed1*seed2) mod 64) + seed3;
				done12 <= '0';
			end if;
			
			if done13 = '1' then
				rock13 <= ((seed1*seed2) mod 64) + seed3;
				done13 <= '0';
			end if;
			
			if done14 = '1' then
				rock14 <= ((seed1*seed2) mod 64) + seed3;
				done14 <= '0';
			end if;
			
			if done15 = '1' then
				rock15 <= ((seed1*seed2) mod 64) + seed3;
				done15 <= '0';
			end if;
			
			if done16 = '1' then
				rock16 <= ((seed1*seed2) mod 64) + seed3;
				done16 <= '0';
			end if;
			
			if done17 = '1' then
				rock17 <= ((seed1*seed2) mod 64) + seed3;
				done17 <= '0';
			end if;
			
			if done18 = '1' then
				rock18 <= ((seed1*seed2) mod 64) + seed3;
				done18 <= '0';
			end if;
			
			if done19 = '1' then
				rock19 <= ((seed1*seed2) mod 64) + seed3;
				done19 <= '0';
			end if;
			
			if done20 = '1' then
				rock20 <= ((seed1*seed2) mod 64) + seed3;
				done20 <= '0';
			end if;
			
			
			if done21 = '1' then
				rock21 <= ((seed1*seed2) mod 64) + seed3;
				done21 <= '0';
			end if;
			
			if done22 = '1' then
				rock22 <= ((seed1*seed2) mod 64) + seed3;
				done22 <= '0';
			end if;
			
			if done23 = '1' then
				rock23 <= ((seed1*seed2) mod 64) + seed3;
				done23 <= '0';
			end if;
			
			if done24 = '1' then
				rock24 <= ((seed1*seed2) mod 64) + seed3;
				done24 <= '0';
			end if;
			
			if done25 = '1' then
				rock25 <= ((seed1*seed2) mod 64) + seed3;
				done25 <= '0';
			end if;
			
			if done26 = '1' then
				rock26 <= ((seed1*seed2) mod 64) + seed3;
				done26 <= '0';
			end if;
			
			if done27 = '1' then
				rock27 <= ((seed1*seed2) mod 64) + seed3;
				done27 <= '0';
			end if;
			
			if done28 = '1' then
				rock28 <= ((seed1*seed2) mod 64) + seed3;
				done28 <= '0';
			end if;
			
			if done29 = '1' then
				rock29 <= ((seed1*seed2) mod 64) + seed3;
				done29 <= '0';
			end if;
			
			if done30 = '1' then
				rock30 <= ((seed1*seed2) mod 64) + seed3;
				done30 <= '0';
			end if;
			
						
			
			state <= GETPIXELS1;		

			when GETPIXELS1 =>
		
				-- wait for pixels to be ready from lookup table
				state <= GETPIXELS2;

			when GETPIXELS2 =>
						pixelnum <= 0;
				
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
						when 8 =>
							state <= ROCKS8;
						when 9 =>
							state <= ROCKS9;
						
						when 10 =>
							state <= ROCKS10;
						when 11 =>
							state <= ROCKS11;
						when 12=>
							state <= ROCKS12;
						when 13 =>
							state <= ROCKS13;
						when 14=>
							state <= ROCKS14;
						when 15=>
							state <= ROCKS15;
						when 16 =>
							state <= ROCKS16;
						
						when 17 =>
							state <= ROCKS17;
						when 18 =>
							state <= ROCKS18;
						when 19 =>
							state <= ROCKS19;
						when 20 =>
							state <= ROCKS20;
						when 21 =>
							state <= ROCKS21;
						when 22=>
							state <= ROCKS22;
						when 23 =>
							state <= ROCKS23;
						when 24=>
							state <= ROCKS24;
						when 25=>
							state <= ROCKS25;
						when 26 =>
							state <= ROCKS26;
						
						when 27 =>
							state <= ROCKS27;
						when 28 =>
							state <= ROCKS28;
						when 29 =>
							state <= ROCKS29;
						when 30 =>
							state <= ROCKS30;
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
				from_rock <= '1';
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
				from_rock <= '1';
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
				from_rock <= '1';
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
				from_rock <= '1';
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
				from_rock <= '1';
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
				from_rock <= '1';
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
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS8 =>
			current_line <= current_line8;
			current_char <= rock8;
				if fall_counter8 = s8 then 
					fall_counter8 <= 0;
					current_line8 <= current_line8+ 1;
					if current_line8 = LINES_PER_PAGE-1 then current_line8 <= 0; done8 <= '1'; end if;
				elsif fall_counter8 > s8 - 500 then
					reg_pixels <= X"00";
					fall_counter8 <= fall_counter8 + 1;
				else
				fall_counter8 <= fall_counter8 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS9 =>
			current_line <= current_line9;
			current_char <= rock9;
				if fall_counter9 = s9 then 
					fall_counter9 <= 0;
					current_line9 <= current_line9 + 1;
					if current_line9 = LINES_PER_PAGE-1 then current_line9 <= 0; done9 <= '1'; end if;
				elsif fall_counter9 > s9 - 500 then
					reg_pixels <= X"00";
					fall_counter9 <= fall_counter9 + 1;
				else
				fall_counter9 <= fall_counter9 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS10 =>
			current_line <= current_line10;
			current_char <= rock10;
				if fall_counter10 = s10 then 
					fall_counter10 <= 0;
					current_line10 <= current_line10 + 1;
					if current_line10 = LINES_PER_PAGE-1 then current_line10 <= 0; done10 <= '1'; end if;
				elsif fall_counter10 > s10 - 500 then
					reg_pixels <= X"00";
					fall_counter10 <= fall_counter10 + 1;
				else
				fall_counter10 <= fall_counter10 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS11 =>
			current_line <= current_line11;
			current_char <= rock11;
				if fall_counter11 = s11 then 
					fall_counter11 <= 0;
					current_line11 <= current_line11 + 1;
					if current_line11 = LINES_PER_PAGE-1 then current_line11 <= 0; done11 <= '1'; end if;
				elsif fall_counter11 > s11 - 500 then
					reg_pixels <= X"00";
					fall_counter11 <= fall_counter11 + 1;
				else
				fall_counter11 <= fall_counter11 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS12 =>
			current_line <= current_line12;
			current_char <= rock12;
				if fall_counter12 = s12 then 
					fall_counter12 <= 0;
					current_line12 <= current_line12 + 1;
					if current_line12 = LINES_PER_PAGE-1 then current_line12 <= 0; done12 <= '1'; end if;
				elsif fall_counter12 > s12 - 500 then
					reg_pixels <= X"00";
					fall_counter12 <= fall_counter12 + 1;
				else
				fall_counter12 <= fall_counter12 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS13 =>
			current_line <= current_line13;
			current_char <= rock13;
				if fall_counter13 = s13 then 
					fall_counter13 <= 0;
					current_line13 <= current_line13 + 1;
					if current_line13 = LINES_PER_PAGE-1 then current_line13 <= 0; done13 <= '1'; end if;
				elsif fall_counter13 > s13 - 500 then
					reg_pixels <= X"00";
					fall_counter13 <= fall_counter13 + 1;
				else
				fall_counter13 <= fall_counter13 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS14 => 
			current_line <= current_line14;
			current_char <= rock14;
				if fall_counter14 = s14 then 
					fall_counter14 <= 0;
					current_line14 <= current_line14 + 1;
					if current_line14 = LINES_PER_PAGE-1 then current_line14 <= 0; done14 <= '1'; end if;
				elsif fall_counter14 > s14 - 500 then
					reg_pixels <= X"00";
					fall_counter14 <= fall_counter14 + 1;
				else
				fall_counter14 <= fall_counter14 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
					when ROCKS15=>
			current_line <= current_line15;
			current_char <= rock15;
				if fall_counter15 = s15 then 
					fall_counter15 <= 0;
					current_line15 <= current_line15 + 1;
					if current_line15 = LINES_PER_PAGE-1 then current_line15 <= 0; done15 <= '1'; end if;
				elsif fall_counter15 > s15 - 500 then
					reg_pixels <= X"00";
					fall_counter15 <= fall_counter15 + 1;
				else
				fall_counter15 <= fall_counter15 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS16 =>
			current_line <= current_line16;
			current_char <= rock16;
				if fall_counter16 = s16 then 
					fall_counter16 <= 0;
					current_line16 <= current_line16 + 1;
					if current_line16 = LINES_PER_PAGE-1 then current_line16 <= 0; done16 <= '1'; end if;
				elsif fall_counter16 > s16 - 500 then
					reg_pixels <= X"00";
					fall_counter16 <= fall_counter16 + 1;
				else
				fall_counter16 <= fall_counter16 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS17 =>
			current_line <= current_line17;
			current_char <= rock17;
				if fall_counter17 = s17 then 
					fall_counter17 <= 0;
					current_line17 <= current_line17 + 1;
					if current_line17 = LINES_PER_PAGE-1 then current_line17 <= 0; done17 <= '1'; end if;
				elsif fall_counter17 > s17 - 500 then
					reg_pixels <= X"00";
					fall_counter17 <= fall_counter17 + 1;
				else
				fall_counter17 <= fall_counter17 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS18 =>
			current_line <= current_line18;
			current_char <= rock18;
				if fall_counter18 = s18 then 
					fall_counter18 <= 0;
					current_line18 <= current_line18 + 1;
					if current_line18 = LINES_PER_PAGE-1 then current_line18 <= 0; done18 <= '1'; end if;
				elsif fall_counter18 > s18 - 500 then
					reg_pixels <= X"00";
					fall_counter18 <= fall_counter18 + 1;
				else
				fall_counter18 <= fall_counter18 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS19 =>
			current_line <= current_line19;
			current_char <= rock19;
				if fall_counter19 = s19 then 
					fall_counter19 <= 0;
					current_line19 <= current_line19 + 1;
					if current_line19 = LINES_PER_PAGE-1 then current_line19 <= 0; done19 <= '1'; end if;
				elsif fall_counter19 > s19 - 500 then
					reg_pixels <= X"00";
					fall_counter19 <= fall_counter19 + 1;
				else
				fall_counter19 <= fall_counter19 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS20 =>
			current_line <= current_line20;
			current_char <= rock20;
				if fall_counter20 = s20 then 
					fall_counter20 <= 0;
					current_line20 <= current_line20 + 1;
					if current_line20 = LINES_PER_PAGE-1 then current_line20 <= 0; done20 <= '1'; end if;
				elsif fall_counter20 > s20 - 500 then
					reg_pixels <= X"00";
					fall_counter20 <= fall_counter20 + 1;
				else
				fall_counter20 <= fall_counter20 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS21 =>
			current_line <= current_line21;
			current_char <= rock21;
			
				if fall_counter21 = s21 then 
					fall_counter21 <= 0;
					current_line21 <= current_line21 + 1;
					if current_line21 = LINES_PER_PAGE-1 then current_line21 <= 0; done21 <= '1'; end if;
				elsif fall_counter21 > s21 - 500 then
					reg_pixels <= X"00";
					fall_counter21 <= fall_counter21 + 1;
				else
				fall_counter21 <= fall_counter21 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS22 =>
			current_line <= current_line22;
			current_char <= rock22;
				if fall_counter22 = s22 then 
					fall_counter22 <= 0;
					current_line22 <= current_line22 + 1;
					if current_line22 = LINES_PER_PAGE-1 then current_line22 <= 0; done22 <= '1'; end if;
				elsif fall_counter22 > s22 - 500 then
					reg_pixels <= X"00";
					fall_counter22 <= fall_counter22 + 1;
				else
				fall_counter22 <= fall_counter22 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS23 =>
			current_line <= current_line23;
			current_char <= rock23;
				if fall_counter23 = s23 then 
					fall_counter23 <= 0;
					current_line23 <= current_line23 + 1;
					if current_line23 = LINES_PER_PAGE-1 then current_line23 <= 0; done23 <= '1'; end if;
				elsif fall_counter23 > s23 - 500 then
					reg_pixels <= X"00";
					fall_counter23 <= fall_counter23 + 1;
				else
				fall_counter23 <= fall_counter23 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS24 =>
			current_line <= current_line24;
			current_char <= rock24;
				if fall_counter24 = s24 then 
					fall_counter24 <= 0;
					current_line24 <= current_line24 + 1;
					if current_line24 = LINES_PER_PAGE-1 then current_line24 <= 0; done24 <= '1'; end if;
				elsif fall_counter24 > s24 - 500 then
					reg_pixels <= X"00";
					fall_counter24 <= fall_counter24 + 1;
				else
				fall_counter24 <= fall_counter24 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS25 =>
			current_line <= current_line25;
			current_char <= rock25;
				if fall_counter25 = s25 then 
					fall_counter25 <= 0;
					current_line25 <= current_line25 + 1;
					if current_line25 = LINES_PER_PAGE-1 then current_line25 <= 0; done25 <= '1'; end if;
				elsif fall_counter25 > s25 - 500 then
					reg_pixels <= X"00";
					fall_counter25 <= fall_counter25 + 1;
				else
				fall_counter25 <= fall_counter25 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS26 =>
			current_line <= current_line26;
			current_char <= rock26;
				if fall_counter26 = s26 then 
					fall_counter26 <= 0;
					current_line26 <= current_line26 + 1;
					if current_line26 = LINES_PER_PAGE-1 then current_line26 <= 0; done26 <= '1'; end if;
				elsif fall_counter26 > s26 - 500 then
					reg_pixels <= X"00";
					fall_counter26 <= fall_counter26 + 1;
				else
				fall_counter26 <= fall_counter26 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS27 => 
			current_line <= current_line27;
			current_char <= rock27;
				if fall_counter27 = s27 then 
					fall_counter27 <= 0;
					current_line27 <= current_line27 + 1;
					if current_line27 = LINES_PER_PAGE-1 then current_line27 <= 0; done27 <= '1'; end if;
				elsif fall_counter27 > s27 - 500 then
					reg_pixels <= X"00";
					fall_counter27 <= fall_counter27 + 1;
				else
				fall_counter27 <= fall_counter27 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS28 =>
			current_line <= current_line28;
			current_char <= rock28;
				if fall_counter28 = s28 then 
					fall_counter28 <= 0;
					current_line28 <= current_line28+ 1;
					if current_line28 = LINES_PER_PAGE-1 then current_line28 <= 0; done28 <= '1'; end if;
				elsif fall_counter28 > s28 - 500 then
					reg_pixels <= X"00";
					fall_counter28 <= fall_counter28 + 1;
				else
				fall_counter28 <= fall_counter28 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS29 =>
			current_line <= current_line29;
			current_char <= rock29;
				if fall_counter29 = s29 then 
					fall_counter29 <= 0;
					current_line29 <= current_line29 + 1;
					if current_line29 = LINES_PER_PAGE-1 then current_line29 <= 0; done29 <= '1'; end if;
				elsif fall_counter29 > s29 - 500 then
					reg_pixels <= X"00";
					fall_counter29 <= fall_counter29 + 1;
				else
				fall_counter29 <= fall_counter29 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when ROCKS30 =>
			
			current_line <= current_line30;
			current_char <= rock30;
				if fall_counter30 = s30 then 
					fall_counter30 <= 0;
					current_line30 <= current_line30 + 1;
					if current_line30 = LINES_PER_PAGE-1 then current_line30 <= 0; done30 <= '1'; end if;
				elsif fall_counter30 > s30 - 500 then
					reg_pixels <= X"00";
					fall_counter30 <= fall_counter30 + 1;
				else
				fall_counter30 <= fall_counter30 + 1;
				reg_pixels <= pixels;
				end if;
				from_rock <= '1';
			state <= WAIT4MEMACK;
			
			when WAIT4MEMACK =>
				if (from_rock = '1' and 
				xlocation = conv_std_logic_vector(current_line,8) and 
				ylocation = conv_std_logic_vector(current_char,8))then state <= FIRST; end if;
				from_rock <= '0';
				if current_line = 0 then reg_pixels <= x"00"; end if;
				seed2 <= seed2+1;
					if ( ack_i = '1' ) then
						if ( scan_line = CHAR_HEIGHT-1 ) then
							seed3 <= seed3+1;
							if start = '1' then state <= INIT; else state <= HOME; end if;
							rock_count <= rock_count + 1;
							if rock_count = max_rocks + 1  then rock_count <= 1; end if;
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
	req <= '1' when state =INIT  or state=WAIT4MEMACK or state = HOME or state = CLEARSCREEN else '0';
	
	--timer <= timer + 1; --500000000 = 10 second
	--tick <=  '1' when timer = 499999999 else '0' when tock = '1';
	--tick <= '0' when tock = '1';
	stb_o <= req;
	cyc_o <= req;
		
end Behavioral;
