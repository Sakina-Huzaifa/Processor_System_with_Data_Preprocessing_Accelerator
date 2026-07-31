---------------------------------------------------------------------------
-- instruction_memory_pipelined.vhd
-- Custom benchmark, Case 2: CPU + Coprocessor
--
-- Same dataset and algorithm as the CPU-only custom benchmark:
--   A = [10,20,30,40,50,60,70,80]
--   B = [5,10,15,20,25,30,35,40]
--
-- Coprocessor:
--   1. VADD:   T1 = A + B
--   2. VSCALE: T2 = T1 * 2
--   3. VCLIP:  T3 = clip(T2, 100)
--
-- CPU:
--   Polls each operation, then sums T3.
--
-- Expected final vector:
--   [30,60,90,100,100,100,100,100]
--
-- Expected output:
--   680 decimal = 0x02A8
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity tb_custom_accelerated is
    port (
        addr_in       : in  std_logic_vector(7 downto 0);
        insn_out      : out std_logic_vector(31 downto 0);
        transfer_addr : in  std_logic_vector(9 downto 0);
        transfer_data : out std_logic_vector(31 downto 0)
    );
end tb_custom_accelerated;

architecture behavioral of tb_custom_accelerated is

    type mem_array is array (0 to 1023) of std_logic_vector(31 downto 0);

    constant imem : mem_array := (

        -- =========================================================
        -- Custom benchmark Case 2 program
        -- =========================================================

        0   => X"00000000", -- NOOP; CPU waits at PC 0 until IMEM-to-DMEM transfer completes
        1   => X"00001050", -- LOAD R5,0(R0) -> R5=10
        2   => X"0000B057", -- SLT R0,R5,R7 -> R7=1
        3   => X"00008778", -- ADD R7,R7,R8 -> R8=2
        4   => X"00008884", -- ADD R8,R8,R4 -> R4=4
        5   => X"00008444", -- ADD R4,R4,R4 -> R4=8 (vector size)
        6   => X"00008001", -- ADD R0,R0,R1 -> R1=0 (A base)
        7   => X"00008402", -- ADD R4,R0,R2 -> R2=8 (B base)
        8   => X"00008443", -- ADD R4,R4,R3 -> R3=16 (VADD destination)
        9   => X"00000000", -- NOOP; allow R1-R4 to reach register file
        10  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        11  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        12  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        13  => X"C000F000", -- SPECIAL VADD: DMEM[16..23] = A + B
        14  => X"0000E0D0", -- POLL R13
        15  => X"00004D01", -- BNE R13,R0,+1 -> leave polling loop when done
        16  => X"0000C00E", -- JMP back to VADD polling loop
        17  => X"00008301", -- ADD R3,R0,R1 -> R1=16 (VADD result base)
        18  => X"00008802", -- ADD R8,R0,R2 -> R2=2 (scale factor k)
        19  => X"00008343", -- ADD R3,R4,R3 -> R3=24 (VSCALE destination)
        20  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        21  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        22  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        23  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        24  => X"D000F000", -- SPECIAL VSCALE: DMEM[24..31] = DMEM[16..23] * 2
        25  => X"0000E0D0", -- POLL R13
        26  => X"00004D01", -- BNE R13,R0,+1 -> leave polling loop when done
        27  => X"0000C019", -- JMP back to VSCALE polling loop
        28  => X"00008301", -- ADD R3,R0,R1 -> R1=24 (scaled vector base)
        29  => X"00008002", -- ADD R0,R0,R2 -> R2=0 (unused by VCLIP)
        30  => X"00008343", -- ADD R3,R4,R3 -> R3=32 (VCLIP destination)
        31  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        32  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        33  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        34  => X"00000000", -- NOOP; allow R1-R4 to reach register file
        35  => X"E000F000", -- SPECIAL VCLIP: DMEM[32..39] = clip(DMEM[24..31],100)
        36  => X"0000E0D0", -- POLL R13
        37  => X"00004D01", -- BNE R13,R0,+1 -> leave polling loop when done
        38  => X"0000C024", -- JMP back to VCLIP polling loop
        39  => X"00008301", -- ADD R3,R0,R1 -> R1=32 (clipped result base)
        40  => X"0000ACCC", -- SUB R12,R12,R12 -> R12=0 (sum)
        41  => X"00001180", -- LOAD R8,0(R1) -> clipped[0]
        42  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        43  => X"00001181", -- LOAD R8,1(R1) -> clipped[1]
        44  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        45  => X"00001182", -- LOAD R8,2(R1) -> clipped[2]
        46  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        47  => X"00001183", -- LOAD R8,3(R1) -> clipped[3]
        48  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        49  => X"00001184", -- LOAD R8,4(R1) -> clipped[4]
        50  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        51  => X"00001185", -- LOAD R8,5(R1) -> clipped[5]
        52  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        53  => X"00001186", -- LOAD R8,6(R1) -> clipped[6]
        54  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        55  => X"00001187", -- LOAD R8,7(R1) -> clipped[7]
        56  => X"00008C8C", -- ADD R12,R8,R12 -> accumulate sum
        57  => X"000060C0", -- OUTPUT R12 -> expected 0x02A8
        58  => X"0000C03A", -- JMP stop

        -- =========================================================
        -- Same custom dataset used by the CPU-only version
        -- IMEM[256..272] is copied into DMEM[0..16]
        -- =========================================================

        256 => X"0000000A", -- DMEM[0] = 10
        257 => X"00000014", -- DMEM[1] = 20
        258 => X"0000001E", -- DMEM[2] = 30
        259 => X"00000028", -- DMEM[3] = 40
        260 => X"00000032", -- DMEM[4] = 50
        261 => X"0000003C", -- DMEM[5] = 60
        262 => X"00000046", -- DMEM[6] = 70
        263 => X"00000050", -- DMEM[7] = 80
        264 => X"00000005", -- DMEM[8] = 5
        265 => X"0000000A", -- DMEM[9] = 10
        266 => X"0000000F", -- DMEM[10] = 15
        267 => X"00000014", -- DMEM[11] = 20
        268 => X"00000019", -- DMEM[12] = 25
        269 => X"0000001E", -- DMEM[13] = 30
        270 => X"00000023", -- DMEM[14] = 35
        271 => X"00000028", -- DMEM[15] = 40
        272 => X"00000064", -- DMEM[16] = 100

        others => X"00000000"
    );

begin
    insn_out      <= imem(to_integer(unsigned(addr_in)));
    transfer_data <= imem(to_integer(unsigned(transfer_addr)));
end behavioral;
