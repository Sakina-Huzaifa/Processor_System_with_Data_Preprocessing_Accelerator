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
use IEEE.numeric_std.ALL;

entity instruction_memory_pipelined is
    port (
        addr_in  : in  std_logic_vector(7 downto 0);
        insn_out : out std_logic_vector(31 downto 0);
        
        transfer_addr   : in std_logic_vector(7 downto 0);
        transfer_data   : out std_logic_vector(31 downto 0)
    );
end instruction_memory_pipelined;

architecture behavioral of instruction_memory_pipelined is

    type mem_array is array (0 to 255) of std_logic_vector(31 downto 0);
    
    constant imem : mem_array := (
        0 => X"00000000",
        1 => X"00000000",
        2 => X"00000000",
        3 => X"00000000",
        others => X"00000000"    
    );
begin
    insn_out <= imem(TO_INTEGER(unsigned(addr_in)));
    transfer_data <= imem(TO_INTEGER(unsigned(transfer_addr)));
end behavioral;
