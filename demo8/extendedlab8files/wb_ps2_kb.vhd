--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:    16:27:32 08/15/05
-- Design Name:    
-- Module Name:    wb_ps2_kb - Behavioral
-- Project Name:   
-- Target Device:  
-- Tool versions:  
-- Description:
--
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

entity wb_ps2_kb is
	Port ( clk_i : in std_logic;
          rst_i : in std_logic;
		    adr_i : in std_logic_vector(31 downto 0);
          dat_i : in std_logic_vector(31 downto 0);
          dat_o : out std_logic_vector(31 downto 0);
          ack_o : out std_logic;
          stb_i : in std_logic;
          we_i  : in std_logic;
			 ps2_clk : inout std_logic;
          ps2_data : inout std_logic;
			 irq_o : out std_logic
		 );
end wb_ps2_kb;

architecture Behavioral of wb_ps2_kb is
	type state_type is (START, DATA0, DATA1, DATA2, DATA3, DATA4, DATA5, DATA6, DATA7, PARITY, STOP);
	signal state : state_type;
	type state2_type is (WAIT4CODE,WAIT4IRQACK,WAIT4ZERO);
	signal state2 : state2_type;
	signal scancode : std_logic_vector(7 downto 0);
	signal scancode_available : std_logic;
begin

	process( ps2_clk, rst_i )
		variable code : std_logic_vector(7 downto 0);
		variable p : std_logic;
	begin
		if ( rst_i = '1' ) then
			state <= START;
			scancode_available <= '0';
		elsif ( ps2_clk'event and ps2_clk='0' ) then

			case state is
			when START =>
				scancode_available <= '0';
				if ( ps2_data = '0' ) then
					state <= DATA0;
					p := '1';
				end if;

			when DATA0 =>
				code(0) := ps2_data;
				p := p xor ps2_data;
				state <= DATA1;

			when DATA1 =>
				code(1) := ps2_data;
				p := p xor ps2_data;
				state <= DATA2;

			when DATA2 =>
				code(2) := ps2_data;
				p := p xor ps2_data;
				state <= DATA3;

			when DATA3 =>
				code(3) := ps2_data;
				p := p xor ps2_data;
				state <= DATA4;

			when DATA4 =>
				code(4) := ps2_data;
				p := p xor ps2_data;
				state <= DATA5;

			when DATA5 =>
				code(5) := ps2_data;
				p := p xor ps2_data;
				state <= DATA6;

			when DATA6 =>
				code(6) := ps2_data;
				p := p xor ps2_data;
				state <= DATA7;

			when DATA7 =>
				code(7) := ps2_data;
				p := p xor ps2_data;
				state <= PARITY;

			when PARITY =>
				if ( ps2_data = p ) then
					state <= STOP;
				else
					state <= START;
				end if;

			when STOP =>
				if ( ps2_data = '1' ) then
					scancode_available <= '1';
					scancode <= code;
				end if;
				state <= START;

			when others => state <= START;
			end case;
		end if;
	end process;
	
	process(clk_i,rst_i)
	begin
		if ( rst_i = '1' ) then
			state2 <= WAIT4CODE;
		elsif ( clk_i'event and clk_i='0' ) then

			case state2 is
			when WAIT4CODE =>
				if (scancode_available='1') then
					state2 <= WAIT4IRQACK;
				end if;
			
			when WAIT4IRQACK =>
				if ( stb_i <= '1' ) then
					if ( scancode_available ='0' ) then
						state2 <= WAIT4CODE;
					else
						state2 <= WAIT4ZERO;
					end if;
				end if;
					
			when WAIT4ZERO =>
				if ( scancode_available = '0' ) then
					state2 <= WAIT4CODE;
				end if;
			
			when others => state2 <= WAIT4CODE;
			
			end case;
		end if;
	end process;

	dat_o(7 downto 0) <= scancode;
	dat_o(31 downto 8) <= X"000000";
	ack_o <= '1';
	irq_o <= '1' when state2 = WAIT4IRQACK else '0';
	
end Behavioral;
