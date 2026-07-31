library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity simple_alu is
    port (
        src_a  : in  std_logic_vector(15 downto 0);
        src_b  : in  std_logic_vector(15 downto 0);
        is_slt : in  std_logic;
        result : out std_logic_vector(15 downto 0)
    );
end simple_alu;

architecture behavioural of simple_alu is
begin

    process(src_a, src_b, is_slt)
    begin

        if is_slt = '1' then

            -- SLT: set result to 1 when src_a is smaller than src_b
            if src_a < src_b then
                result <= X"0001";
            else
                result <= X"0000";
            end if;

        else

            -- SUB: normal 16-bit subtraction
            result <= src_a - src_b;

        end if;

    end process;

end behavioural;