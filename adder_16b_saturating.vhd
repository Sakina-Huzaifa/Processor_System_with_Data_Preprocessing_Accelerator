library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity adder_16b_saturating is
    port ( src_a     : in  std_logic_vector(15 downto 0);
           src_b     : in  std_logic_vector(15 downto 0);
           sat_mode  : in  std_logic;
           sum       : out std_logic_vector(15 downto 0);
           carry_out : out std_logic );
end adder_16b_saturating;

architecture behavioural of adder_16b_saturating is

signal sig_result : std_logic_vector(16 downto 0);

begin

    sig_result <= ('0' & src_a) + ('0' & src_b);
    
    -- When sat_mode = '1', check for carry and saturate if needed
    -- When sat_mode = '0', perform regular addition
    process(sig_result, sat_mode)
    begin
        if (sat_mode = '1') then
            -- Saturating addition mode
            if (sig_result(16) = '1') then
                -- Overflow occurred, saturate to maximum value (0xFFFF)
                sum <= X"FFFF";
            else
                -- No overflow, use result as is
                sum <= sig_result(15 downto 0);
            end if;
        else
            -- Regular addition mode
            sum <= sig_result(15 downto 0);
        end if;
    end process;
    
    carry_out <= sig_result(16);
    
end behavioural;
