library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity control_unit is
    port ( opcode     : in  std_logic_vector(3 downto 0);
           reg_dst    : out std_logic;
           reg_write  : out std_logic;
           alu_src    : out std_logic;
           mem_write  : out std_logic;
           mem_to_reg : out std_logic;
           in_to_reg  : out std_logic;
           out_enable : out std_logic;
           alu_mode   : out std_logic;
           branch     : out std_logic;   -- BNE
           dis_enable : out std_logic );  -- DIS
end control_unit;

architecture behavioural of control_unit is

constant OP_LOAD   : std_logic_vector(3 downto 0) := "0001";
constant OP_STORE  : std_logic_vector(3 downto 0) := "0011";
constant OP_BNE    : std_logic_vector(3 downto 0) := "0100"; 
constant OP_INPUT  : std_logic_vector(3 downto 0) := "0101";
constant OP_OUTPUT : std_logic_vector(3 downto 0) := "0110";
constant OP_DIS    : std_logic_vector(3 downto 0) := "0111"; 
constant OP_ADD    : std_logic_vector(3 downto 0) := "1000";
constant OP_SADD   : std_logic_vector(3 downto 0) := "1001";

begin
    -- write the rd field for ADD/SADD
    reg_dst    <= '1' when (opcode = OP_ADD or opcode = OP_SADD) else '0';
 
    reg_write  <= '1' when (opcode = OP_ADD or opcode = OP_LOAD or
                            opcode = OP_SADD or opcode = OP_INPUT) else '0';
    -- using the immediate as ALU operand B for LOAD/STORE and DIS
    alu_src    <= '1' when (opcode = OP_LOAD or opcode = OP_STORE or
                            opcode = OP_DIS) else '0';
    mem_write  <= '1' when opcode = OP_STORE  else '0';
    mem_to_reg <= '1' when opcode = OP_LOAD   else '0';
    in_to_reg  <= '1' when opcode = OP_INPUT  else '0';
    out_enable <= '1' when opcode = OP_OUTPUT else '0';
    alu_mode   <= '1' when opcode = OP_SADD   else '0';
   
    branch     <= '1' when opcode = OP_BNE    else '0';
    dis_enable <= '1' when opcode = OP_DIS    else '0';

end behavioural;
