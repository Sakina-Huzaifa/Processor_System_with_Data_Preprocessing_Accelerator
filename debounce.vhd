library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity debounce is
    port ( clk     : in  std_logic;
           btn_in  : in  std_logic;
           btn_out : out std_logic );
end debounce;
architecture behavioral of debounce is
    signal shift_reg : std_logic_vector(19 downto 0) := (others => '0');
begin
    process(clk) is
    begin
        if rising_edge(clk) then
            shift_reg <= shift_reg(18 downto 0) & btn_in;
        end if;
    end process;
    btn_out <= '1' when shift_reg = (shift_reg'range => '1') else '0';
end behavioral;
