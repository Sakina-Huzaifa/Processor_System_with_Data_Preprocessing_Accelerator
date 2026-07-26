library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mux_3to1_16b is
    port ( mux_select : in  std_logic_vector(1 downto 0);
           data_a     : in  std_logic_vector(15 downto 0);
           data_b     : in  std_logic_vector(15 downto 0);
           data_c     : in  std_logic_vector(15 downto 0);
           data_out   : out std_logic_vector(15 downto 0) );
end mux_3to1_16b;

architecture behavioral of mux_3to1_16b is

begin

    with mux_select select
        data_out <= data_a when "00",      -- ALU result (alu_data)
                    data_b when "01",      -- Memory output (mem_data)
                    data_c when "10",      -- Switch input (input_data)
                    data_a when others;    -- Default to ALU

end behavioral;
