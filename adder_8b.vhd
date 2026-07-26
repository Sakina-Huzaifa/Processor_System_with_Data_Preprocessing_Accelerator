library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
 
entity adder_8b is
    port (
        src_a     : in  std_logic_vector(7 downto 0);
        src_b     : in  std_logic_vector(7 downto 0);
        sum       : out std_logic_vector(7 downto 0);
        carry_out : out std_logic
    );
end adder_8b;
 
architecture behavioural of adder_8b is
    signal sig_result : std_logic_vector(8 downto 0);
begin
    sig_result <= ('0' & src_a) + ('0' & src_b);
    sum        <= sig_result(7 downto 0);
    carry_out  <= sig_result(8);
end behavioural;
