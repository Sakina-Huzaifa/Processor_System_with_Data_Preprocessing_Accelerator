---------------------------------------------------------------------------
-- instruction_memory_pipelined.vhd
--
-- CHANGES FROM LAB 3
--   addr_in  : 4-bit  to  8-bit   (256 addressable locations)
--   insn_out : 16-bit to  32-bit  (upper 16 bits carry coprocessor fields)
--
-- INSTRUCTION ENCODING (32-bit)
--   Basic instructions (upper 16 bits = 0x0000):
--     [31:16] = 0x0000
--     [15:12] = opcode   (same as Lab 3)
--     [11:8]  = Rs
--     [7:4]   = Rt / Rd
--     [3:0]   = Rd / imme
--
--   Special (coprocessor) instructions:
--     [31:30] = "11"     (marks as special)
--     [29:28] = cop_op   (00=VADD  01=VSCALE  10=VCLIP)
--     [27:16] = reserved (0)
--     [15:12] = "1111"   (OP_SPECIAL opcode)
--     [11:8]  = Rs field (used to read cop_dst from register file)
--     [7:4]   = Rt field (used to read cop_srcB from register file)
--     [3:0]   = reserved (0)
--
-- MEMORY LAYOUT
--   0x00 - 0x7F : Program instructions
--   0x80 - 0xFF : Available (dataset can be stored here if needed)
--
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity instruction_memory_pipelined is
    port (
        addr_in  : in  std_logic_vector(7 downto 0);
        insn_out : out std_logic_vector(31 downto 0)
    );
end instruction_memory_pipelined;

architecture behavioral of instruction_memory_pipelined is
begin
    process(addr_in)
    begin
        case addr_in is
            
            when X"00" => insn_out <= X"00005010"; -- IN   $1
            when X"01" => insn_out <= X"00001021"; -- LOAD $2, $0, 1
            when X"02" => insn_out <= X"00001040"; -- LOAD $4, $0, 0
            when X"03" => insn_out <= X"00000000"; -- NOOP
            when X"04" => insn_out <= X"00004126"; -- BNE  $1,$2,6
            when X"05" => insn_out <= X"00000000"; -- NOOP
            when X"06" => insn_out <= X"00000000"; -- NOOP
            when X"07" => insn_out <= X"00006040"; -- OUT  $4(not-taken path)
            when X"08" => insn_out <= X"00004204"; -- BNE  $2,$0,4
            when X"09" => insn_out <= X"00000000"; -- NOOP
            when X"0A" => insn_out <= X"00000000"; -- NOOP
            when X"0B" => insn_out <= X"00006020"; -- OUT  $2(taken path)
            when X"0C" => insn_out <= X"00000000"; -- NOOP
            when X"0D" => insn_out <= X"00007124"; -- DIS  $2,$1,4
       
            when others => insn_out <= X"00000000"; -- NOOP
        end case;
    end process;
end behavioral;
