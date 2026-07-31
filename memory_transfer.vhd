----------------------------------------------------------------------------------
-- Create Date: 31.07.2026 10:31:36
-- Module Name: memory_transfer - Behavioral
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity memory_transfer is
    port (
        clk   : in std_logic;
        reset : in std_logic;
        start : in std_logic;

        imem_addr : out std_logic_vector(9 downto 0);
        imem_data : in  std_logic_vector(31 downto 0);
        transfer_size : in std_logic_vector(9 downto 0);

        dmem_addr            : out std_logic_vector(9 downto 0);
        dmem_write_data      : out std_logic_vector(15 downto 0);
        dmem_write_enable    : out std_logic;

        busy : out std_logic;
        done : out std_logic
    );
end memory_transfer;

architecture Behavioral of memory_transfer is

constant SOURCE_BASE : unsigned(9 downto 0) := to_unsigned(256, 10);

signal end_copy : std_logic;

signal copy_addr : std_logic_vector(9 downto 0);

type state_type is (wait_start, copy, done_copy);
signal y : state_type;
signal next_y : state_type;

begin
state_reg: PROCESS(clk, reset)
begin
    if reset = '1' then
        y <= wait_start; 
    elsif rising_edge(clk) then 
        y <= next_y; 
    end if;
end process;

addr_counter: process(clk, reset)
begin
    if reset = '1' then 
        copy_addr <= (others => '0');
        
    elsif rising_edge(clk) then
        if y = wait_start then 
            copy_addr <= (others => '0');
        
        elsif y = copy then 
            if end_copy = '0' then 
                copy_addr <= std_logic_vector(unsigned(copy_addr) + 1);
            end if;
        end if;
    end if;
end process;

next_state: PROCESS(y, start, end_copy)
begin 
    next_y <= y;
    
    case y is 
        when wait_start => 
            if start = '1' then
                next_y <= copy;
            end if;
        
        when copy => 
            if end_copy = '1' then  
                next_y <= done_copy;
            end if;
        
        when done_copy => 
            next_y <= done_copy;
        
        when others => next_y <= wait_start;
     end case;
end process;

outputs: PROCESS(y)
begin 
    dmem_write_enable <= '0';
    busy <= '0';
    done <= '0';
    
    case y is 
        when wait_start => 
            null;
        
        when copy => 
            dmem_write_enable <= '1';
            busy <= '1';
        
        when done_copy => 
            done <= '1';
        
        when others => null;
    end case;
end process;    

imem_addr <= std_logic_vector(SOURCE_BASE + unsigned(copy_addr));
dmem_addr <= copy_addr;
dmem_write_data <= imem_data(15 downto 0);
end_copy <= '1' when
                unsigned(transfer_size) = 0
                or unsigned(copy_addr) = unsigned(transfer_size) - 1
            else '0';

end Behavioral;
