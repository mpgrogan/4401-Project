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
use IEEE.MATH_REAL.ALL;

---- Uncomment the following library declaration if instantiating
---- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;
--
entity videomem_master is
	Port ( clk_i : in std_logic;
          rst_i : in std_logic;
		    adr_o : out std_logic_vector(31 downto 0);
          dat_i : in std_logic_vector(31 downto 0);
          dat_o : out std_logic_vector(31 downto 0);
          ack_i : in std_logic;
          cyc_o : out std_logic;
          stb_o : out std_logic;
          we_o  : out std_logic;
			 irq_i : in std_logic;
			 irqv_i: in std_logic_vector(1 downto 0);
			 leds_o : out std_logic_vector(7 downto 0);
			 location : inout std_logic_vector(31 downto 0);
			 res : inout std_logic);
end videomem_master;

architecture Behavioral of videomem_master is
	signal code, ascii, volume : std_logic_vector(7 downto 0);
	signal shift, ctrl, alt : std_logic;
	signal req : std_logic;

	signal current_addr : std_logic_vector(31 downto 0);
	type state_type is (FIRST,INITMEM, WAIT4IRQ, WAIT4CODE, GETPIXELS1, GETPIXELS2, WAIT4MEMACK,SHIP,LASER,CLOCK,CLOCK2);
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
	signal current_line : integer range 0 to LINES_PER_PAGE-1;
	signal scan_line : integer range 0 to CHAR_HEIGHT;
	signal pixelnum : integer range 0 to CHAR_WIDTH-1;
	signal delete_count,laser_counter,laser_speed,laser_line,laser_char,ship_char,ship_line,ship_speed,move_counter : integer ;
	signal reset1,delete_laser: std_logic;
	signal count,count2 : integer RANGE 0 to 9;
	signal ans: integer RANGE 0 to 2;
	signal timer : integer RANGE 0 to 500000;
	signal alternate : integer RANGE 0 to 3;
	signal number : std_logic_vector(7 downto 0);
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
		variable extended, keyup : std_logic;
		variable l_down, r_down, u_down, d_down,movement,shoot : std_logic;
		variable next_state : state_type;
		variable scancode : std_logic_vector(7 downto 0);
	begin
		if ( rst_i = '1') then
			reset1 <= '0';
			--res <= '0';
			current_char <= 0;
			current_line <= 0;
			scan_line <= 0;
			shift <= '1';
			reg_pixels <= X"00";
			state <= FIRST;
			
			laser_counter <= 0;
			laser_speed <= 18000;
			r_down := '0';
			u_down := '0';
			l_down := '0';
			d_down := '0';
			shoot := '0';
			movement := '1';
			keyup := '0';
			extended := '0';
			ship_char <= 40;
			ship_line <= LINES_PER_PAGE - 2;
		elsif ( clk_i'event and clk_i='1' ) then
			case state is
			
			when FIRST =>
			reset1 <= '0';
			current_char <= 0;
			current_line <= 0;
			scan_line <= 0;
			reg_pixels <= X"00";
			state <= INITMEM;
		
			r_down := '0';
			u_down := '0';
			l_down := '0';
			d_down := '0';
			movement := '1';
			keyup := '0';
			extended := '0';
				
			when INITMEM =>
			reg_pixels <= X"00";
				if ( ack_i = '1' ) then
					if ( scan_line = CHAR_HEIGHT-1 ) then
						scan_line <= 0;
						if ( current_char = CHARS_PER_LINE-1 ) then
							current_char <= 0;
							if ( current_line = LINES_PER_PAGE-1 ) then
							--	current_line <= 25;
							--	current_char <= 30;
								state <= WAIT4IRQ;
							else
								current_line <= current_line + 1;
							end if;
						else
							current_char <= current_char + 1;
						end if;
					else
						scan_line <= scan_line + 1;
						
						state <= INITMEM;
					end if;
				end if;

			when WAIT4IRQ =>
				--if reset1 = '1' then reset1 <= '0'; state <= FIRST;end if;
				
				  state <= WAIT4CODE;
				

			when WAIT4CODE =>
				if ( ack_i ='1' ) then
					next_state := WAIT4IRQ;
					scancode := dat_i(7 downto 0);

					if ( scancode = X"F0" ) then
						keyup := '1';
					elsif ( scancode = X"E0" ) then
						extended := '1';
					else
						if ( keyup = '1' ) then
							if (scancode = X"1C") then
								if shoot = '1' then 
									delete_laser <= '1';
								else shoot := '1'; end if;
								laser_char <= ship_char;
								laser_line <= ship_line -1;
								next_state := GETPIXELS1;
							end if;
						elsif ( extended = '1' ) then
							if ( scancode = X"75" ) then 
								u_down := '1';
								next_state := GETPIXELS1;
							elsif ( scancode = X"6B" ) then 
								l_down := '1';
								next_state := GETPIXELS1;
							elsif ( scancode = X"72" ) then 
								d_down := '1';
								next_state := GETPIXELS1;
							elsif ( scancode = X"74" ) then 
								r_down := '1';
								next_state := GETPIXELS1;	
							end if;
						else
							next_state := GETPIXELS1;
						end if;
						keyup := '0';
						extended := '0';
					end if;

					-- transfer variables to signals
					state <= next_state;
					if (l_down = '0' and r_down  = '0' and d_down = '0' and u_down = '0' ) then
						code <= X"22";
					else
						code <= scancode;
					end if;
				end if;

			when GETPIXELS1 =>
				-- wait for pixels to be ready from lookup table
				if alternate = 0 then
					shift <= '1';
					code <= X"22"; -- ship
				elsif (shoot = '1' and alternate = 1) then
					shift <= '1';
					code <= X"25"; --laser
				elsif (alternate = 2) then
					shift <= '0';
					timer <= timer + 1;
					
					if timer = 0 then
						count <= count + 1;	
						if count = 9 then count2 <= count2 + 1; end if;
					end if;
					
					case count is
						when 0 => 
							code <= X"45"; 
						when 1 => 
							code <= X"16"; 
						when 2 => 
							code <= X"1E"; 
						when 3 => 
							code <= X"26"; 
						when 4 => 
							code <= X"25"; 
						when 5 => 
							code <= X"2E"; 
						when 6 => 
							code <= X"36"; 
						when 7 => 
							code <= X"3D"; 
						when 8 => 
							code <= X"3E"; 
						when 9 => 
							code <= X"46"; 
						when others =>  code <= X"45";	
					end case;
				else
					case count2 is
						when 0 => 
							code <= X"45"; 
						when 1 => 
							code <= X"16"; 
						when 2 => 
							code <= X"1E"; 
						when 3 => 
							code <= X"26"; 
						when 4 => 
							code <= X"25"; 
						when 5 => 
							code <= X"2E"; 
						when 6 => 
							code <= X"36"; 
						when 7 => 
							code <= X"3D"; 
						when 8 => 
							code <= X"3E"; 
						when 9 => 
							code <= X"46"; 
						when others =>  code <= X"45";	
					end case;
				end if;
				
				
				
				state <= GETPIXELS2;

			when GETPIXELS2 =>
				pixelnum <= 0;
				if alternate = 0 then
					state <= SHIP;
				elsif (shoot = '1' and alternate = 1) then
					state <= LASER;
				elsif (alternate = 2) then
					state <= CLOCK;
				else
					state <= CLOCK2;
				end if;
				
			when LASER =>
				if delete_laser = '1' then
					current_line <= laser_line;
					current_char <= laser_char;
					reg_pixels <= X"00";
					if delete_count = 500 then
						delete_laser <= '0';
					else
					delete_count <= delete_count + 1;
					end if;
					
				elsif shoot = '1' then
					current_line <= laser_line;
					current_char <= laser_char;
					if laser_counter = laser_speed then 
						laser_counter <= 0;
						laser_line <= laser_line - 1;
						if laser_line = 2  then shoot := '0'; end if;
					elsif laser_counter > laser_speed - 900 then
						reg_pixels <= X"00";
						laser_counter <= laser_counter + 1;
					else
					laser_counter <= laser_counter + 1;
					reg_pixels <= pixels;
					end if;
				end if;
				state <= WAIT4MEMACK;
				
			when SHIP =>
				
				current_char <= ship_char;
				current_line <= ship_line;
						--if count = 100 then 
						if (l_down = '1' or r_down = '1' or d_down = '1' or u_down = '1') then
							reg_pixels <= X"00";
							move_counter <= move_counter + 1;
							if move_counter = 500 then
								move_counter <= 0;
								if (l_down = '1') then
									l_down := '0';
									if (ship_char /= 0 ) then ship_char <= ship_char - 1; end if;
								elsif (r_down = '1') then
									r_down := '0'; 
									if (ship_char /= CHARS_PER_LINE ) then ship_char <= ship_char + 1; end if;
								elsif (u_down = '1') then
									u_down := '0';
									if (ship_line /= 0) then ship_line <= ship_line - 1; end if;
								elsif (d_down = '1') then
									d_down := '0';
									if (current_line /= LINES_PER_PAGE) then ship_line <= ship_line + 1; end if;
								end if;
							end if;
						else
							reg_pixels <= pixels;
						end if;
						--else count <= count +1; end if;
				state <= WAIT4MEMACK;
				
			when CLOCK =>
				current_line <= 1;
				current_char <= CHARS_PER_LINE - 1;
				reg_pixels <= pixels;
				state <= WAIT4MEMACK;
	
			when CLOCK2 =>
				current_line <= 1;
				current_char <= CHARS_PER_LINE - 2;
				reg_pixels <= pixels;
				state <= WAIT4MEMACK;
			when WAIT4MEMACK =>
			
			--location <= current_line*current_char;
				if ( ack_i = '1' ) then
					if ( scan_line = CHAR_HEIGHT-1 ) then
					alternate <= alternate + 1;
						state <= WAIT4IRQ;
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

			when others => state <= INITMEM;
			end case;
		end if;
	end process;

	-- set dat_o to the color pixels output
	dat_o <= color_pixels;

	-- we_o to '1' when we are in WAIT4MEMACK where we do writes
	we_o <= '1' when state = WAIT4MEMACK or state=INITMEM else '0';

	-- set the adr_o appropriately depending on which state we're in.  
	-- base address 
	-- 0x4 when reading from the keyboard,
	-- 0x0 when writing to memory
	adr_o <= current_addr when state = WAIT4MEMACK or state=INITMEM else
			   X"40000000";

	

	buffer_base <= X"00000000";
--	current_addr <= buffer_base + (current_line*CHARS_PER_LINE*CHAR_HEIGHT + current_char + scan_line*CHARS_PER_LINE + pixelnum/PIXELS_PER_WORD)*CHAR_WIDTH/PIXELS_PER_WORD*4;
	current_addr <= buffer_base + (current_line*CHARS_PER_LINE*CHAR_HEIGHT + current_char + scan_line*CHARS_PER_LINE)*CHAR_WIDTH/PIXELS_PER_WORD*4;
	
	-- grab the bus when we are in a state that is reading or writing from a slave module
	req <= '1' when state =INITMEM or state=WAIT4MEMACK or state=WAIT4CODE or state=GETPIXELS1 or state =GETPIXELS2 else '0';
	stb_o <= req;
	cyc_o <= req;

	--reset1 <= '1' when res = '1';
	--location <= conv_std_logic_vector(current_line*current_char,32);
		
end Behavioral;
--