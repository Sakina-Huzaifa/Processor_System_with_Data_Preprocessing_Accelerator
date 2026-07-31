---------------------------------------------------------------------------
-- data_memory.vhd - Implementation of A Single-Port, 16 x 16-bit Data
--                   Memory.
-- 
--
-- Copyright (C) 2006 by Lih Wen Koh (lwkoh@cse.unsw.edu.au)
-- All Rights Reserved. 
--
-- The single-cycle processor core is provided AS IS, with no warranty of 
-- any kind, express or implied. The user of the program accepts full 
-- responsibility for the application of the program and the use of any 
-- results. This work may be downloaded, compiled, executed, copied, and 
-- modified solely for nonprofit, educational, noncommercial research, and 
-- noncommercial scholarship purposes provided that this notice in its 
-- entirety accompanies all copies. Copies of the modified software can be 
-- delivered to persons who use it solely for nonprofit, educational, 
-- noncommercial research, and noncommercial scholarship purposes provided 
-- that this notice in its entirety accompanies all copies.
--
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity data_memory is
    port ( reset        : in  std_logic;
           clk          : in  std_logic;
           write_enable : in  std_logic;
           write_data   : in  std_logic_vector(15 downto 0);
           addr_in      : in  std_logic_vector(9 downto 0);
           data_out     : out std_logic_vector(15 downto 0);
           
           cop_busy         : in std_logic;
           cop_write_enable : in std_logic;
           cop_write_data   : in std_logic_vector(15 downto 0);
           cop_addr_in      : in std_logic_vector(9 downto 0);
           
           transfer_busy         : in std_logic;
           transfer_write_enable : in std_logic;
           transfer_write_data   : in std_logic_vector(15 downto 0);
           transfer_addr_in      : in std_logic_vector(9 downto 0) );
end data_memory;

architecture behavioral of data_memory is

type mem_array is array(0 to 1023) of std_logic_vector(15 downto 0);
signal sig_data_mem : mem_array;

signal selected_addr           : std_logic_vector(9 downto 0);
signal selected_write_enable   : std_logic;
signal selected_write_data     : std_logic_vector(15 downto 0);

begin

select_inputs: process(cop_busy, cop_addr_in, cop_write_enable, cop_write_data,
                        transfer_busy, transfer_write_enable, transfer_addr_in, 
                        transfer_write_data, addr_in, write_enable, write_data)
begin 
    if cop_busy = '1' then
        selected_addr           <= cop_addr_in;
        selected_write_enable   <= cop_write_enable;
        selected_write_data     <= cop_write_data;
        
    elsif transfer_busy = '1' then 
        selected_addr           <= transfer_addr_in;
        selected_write_enable   <= transfer_write_enable;
        selected_write_data     <= transfer_write_data;
    
    else    
        selected_addr           <= addr_in;
        selected_write_enable   <= write_enable;
        selected_write_data     <= write_data;
    
    end if;
end process;
    
mem_process: process ( reset,
                           clk,
                           selected_addr,
                           selected_write_enable,
                           selected_write_data ) is
  
    variable var_data_mem : mem_array;
    variable var_addr     : integer;
  
    begin
        var_addr := conv_integer(selected_addr);
        
        if (reset = '1') then
            -- initial values of the data memory : reset to zero 
            for i in 0 to 1023 loop 
                var_data_mem(i) := X"0000";
            end loop;

        elsif (falling_edge(clk) and selected_write_enable = '1') then
            -- memory writes on the falling clock edge
            var_data_mem(var_addr) := selected_write_data;
        end if;
       
        -- continuous read of the memory location given by var_addr 
        data_out <= var_data_mem(var_addr);
 
        -- for simulation 
        sig_data_mem <= var_data_mem;

    end process;
  
end behavioral;
