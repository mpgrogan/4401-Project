--------------------------------------------------------------------------------
-- Company: UNIVERSITY OF CONNECTICUT
-- Engineer: John A. Chandy
--
-- Create Date:    16:28:25 06/18/10
-- Module Name:    sram16ctl - Behavioral
-- Additional Comments:
--   This module is a Wishbone module that provides an interface to external SRAM
--   on the Digilent Nexys2 board
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

---- Uncomment the following library declaration if instantiating
---- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity sram16ctl is
	generic  (num_read_waits : natural := 4; 
				 num_page_mode_read_waits : natural := 4;
				 num_write_waits : natural := 4);
	Port ( clk_i : in std_logic;
          rst_i : in std_logic;
          adr_i : in std_logic_vector(31 downto 0);
          dat_i : in std_logic_vector(31 downto 0);
          dat_o : out std_logic_vector(31 downto 0);
          ack_o : out std_logic;
          stb_i : in std_logic;
          we_i  : in std_logic;
          MemAdr : out std_logic_vector(23 downto 1);
          MemOE : out std_logic;
          MemWR : out std_logic;
          MemDB : inout std_logic_vector(15 downto 0);
          RamCS : out std_logic;
          RamUB : out std_logic;
          RamLB : out std_logic;
          RamAdv : out std_logic;
          RamClk : out std_logic;
          RamCRE : out std_logic
		);
end sram16ctl;

architecture Behavioral of sram16ctl is
	signal be, we : std_logic;
	signal ready : std_logic;
	signal waits : natural;
	signal data_hi : std_logic_vector(31 downto 16);
begin

	-- this process basically counts for num_write_waits or num_read_waits clock cycles depending
	-- on whether its a read or a write
	process(clk_i,rst_i)
	begin
		if (rst_i='1') then
			waits <= 0;
		elsif (clk_i'event and clk_i='1') then
			if (stb_i='1' and we_i='1') then
				if (waits<(2*num_write_waits-1)) then 
					waits <= waits + 1;
				else
					waits <= 0;
				end if;
			elsif (stb_i='1' and we_i='0') then
				if (waits<(num_read_waits+num_page_mode_read_waits)) then
					waits <= waits + 1;
					if (waits<num_read_waits) then 
						dat_o(15 downto 0) <= MemDB(15 downto 0);
--						dat_o(15 downto 0) <= X"FFFF";
					end if;
				else
					waits <= 0;
				end if;
			end if;
		end if;
	end process;

	-- this process figures out whether to assert the ready/ack signal based on whether the
	-- waits count has reached num_write_waits or num_read_waits
	process(stb_i,we_i,waits)
	variable rready, wready : std_logic;
	begin
		if ( num_read_waits = 0 ) then
			rready := not we_i;
		elsif (stb_i='1' and we_i='0' and waits=num_read_waits+num_page_mode_read_waits-1) then
			rready := '1';
		else
			rready := '0';
		end if;
		if ( num_write_waits = 0 ) then
			wready := we_i;
		elsif (stb_i='1' and we_i='1' and waits=2*num_write_waits-1) then
			wready := '1';
		else
			wready := '0';
		end if;

		ready <= wready or rready;
	end process;

	MemAdr(23 downto 2) <= adr_i(23 downto 2);
	MemAdr(1) <= '1' when (we_i='1' and waits >= num_write_waits) or
								 (we_i='0' and waits >= num_read_waits)
			  else '0';
	MemDB <= dat_i(15 downto 0)  when we_i='1' and waits < num_write_waits
		 else dat_i(31 downto 16) when we_i='1' and waits >= num_write_waits
		 else (others => 'Z');
	dat_o(31 downto 16) <= MemDB;
	RamCS <= not stb_i;
	we <= '0' when we_i='1' and stb_i='1' else '1';
	MemWR <= we;
	MemOE <= '0';
   be <= '0';
	RamUB <= be;
	RamLB <= be;
	ack_o <= ready;

	-- Pseudo-SRAM is operated in asynchronous mode
	RamAdv <= '0';
	RamClk <= '0';
	RamCRE <= '0';

end Behavioral;
