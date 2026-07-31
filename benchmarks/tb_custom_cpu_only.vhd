---------------------------------------------------------------------------
-- instruction_memory_pipelined.vhd
-- Custom benchmark, Case 1: CPU-only
--
-- Sensor vectors:
--   A = [10,20,30,40,50,60,70,80]
--   B = [5,10,15,20,25,30,35,40]
--
-- CPU performs for every element:
--   value = (A[i] + B[i]) * 2
--   value = min(value, 100)
--   sum   = sum + value
--
-- Expected result:
--   [30,60,90,100,100,100,100,100]
--   sum = 680 = 0x02A8
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity tb_custom_cpu_only is
    port (
        addr_in       : in  std_logic_vector(7 downto 0);
        insn_out      : out std_logic_vector(31 downto 0);
        transfer_addr : in  std_logic_vector(9 downto 0);
        transfer_data : out std_logic_vector(31 downto 0)
    );
end tb_custom_cpu_only;

architecture behavioral of tb_custom_cpu_only is
    type mem_array is array (0 to 1023) of std_logic_vector(31 downto 0);

    constant imem : mem_array := (

        -- =========================================================
        -- Custom benchmark Case 1: CPU-only program
        -- =========================================================

        0   => X"00000000", -- NOOP
        1   => X"00001010", -- LOAD R1,0(R0) -> A[0]=10
        2   => X"0000B017", -- SLT R0,R1,R7 -> R7=1
        3   => X"00008778", -- ADD R7,R7,R8 -> R8=2
        4   => X"00008888", -- ADD R8,R8,R8 -> R8=4
        5   => X"00008888", -- ADD R8,R8,R8 -> R8=8 (B base)
        6   => X"00008885", -- ADD R8,R8,R5 -> R5=16
        7   => X"00001540", -- LOAD R4,0(R5) -> clip limit 100
        8   => X"0000ACCC", -- SUB R12,R12,R12 -> sum=0
        9   => X"00001010", -- LOAD R1,0(R0) -> A[0]
        10  => X"00001820", -- LOAD R2,0(R8) -> B[0]
        11  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        12  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        13  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        14  => X"00004602", -- if value<100, use calculated value
        15  => X"00008C4C", -- sum += 100 (clipped case)
        16  => X"0000C012", -- jump to next element
        17  => X"00008C3C", -- sum += calculated value
        18  => X"00001011", -- LOAD R1,1(R0) -> A[1]
        19  => X"00001821", -- LOAD R2,1(R8) -> B[1]
        20  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        21  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        22  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        23  => X"00004602", -- if value<100, use calculated value
        24  => X"00008C4C", -- sum += 100 (clipped case)
        25  => X"0000C01B", -- jump to next element
        26  => X"00008C3C", -- sum += calculated value
        27  => X"00001012", -- LOAD R1,2(R0) -> A[2]
        28  => X"00001822", -- LOAD R2,2(R8) -> B[2]
        29  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        30  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        31  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        32  => X"00004602", -- if value<100, use calculated value
        33  => X"00008C4C", -- sum += 100 (clipped case)
        34  => X"0000C024", -- jump to next element
        35  => X"00008C3C", -- sum += calculated value
        36  => X"00001013", -- LOAD R1,3(R0) -> A[3]
        37  => X"00001823", -- LOAD R2,3(R8) -> B[3]
        38  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        39  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        40  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        41  => X"00004602", -- if value<100, use calculated value
        42  => X"00008C4C", -- sum += 100 (clipped case)
        43  => X"0000C02D", -- jump to next element
        44  => X"00008C3C", -- sum += calculated value
        45  => X"00001014", -- LOAD R1,4(R0) -> A[4]
        46  => X"00001824", -- LOAD R2,4(R8) -> B[4]
        47  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        48  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        49  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        50  => X"00004602", -- if value<100, use calculated value
        51  => X"00008C4C", -- sum += 100 (clipped case)
        52  => X"0000C036", -- jump to next element
        53  => X"00008C3C", -- sum += calculated value
        54  => X"00001015", -- LOAD R1,5(R0) -> A[5]
        55  => X"00001825", -- LOAD R2,5(R8) -> B[5]
        56  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        57  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        58  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        59  => X"00004602", -- if value<100, use calculated value
        60  => X"00008C4C", -- sum += 100 (clipped case)
        61  => X"0000C03F", -- jump to next element
        62  => X"00008C3C", -- sum += calculated value
        63  => X"00001016", -- LOAD R1,6(R0) -> A[6]
        64  => X"00001826", -- LOAD R2,6(R8) -> B[6]
        65  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        66  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        67  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        68  => X"00004602", -- if value<100, use calculated value
        69  => X"00008C4C", -- sum += 100 (clipped case)
        70  => X"0000C048", -- jump to next element
        71  => X"00008C3C", -- sum += calculated value
        72  => X"00001017", -- LOAD R1,7(R0) -> A[7]
        73  => X"00001827", -- LOAD R2,7(R8) -> B[7]
        74  => X"00008123", -- ADD R1,R2,R3 -> A[i]+B[i]
        75  => X"00008333", -- ADD R3,R3,R3 -> scale by 2
        76  => X"0000B346", -- SLT R3,R4,R6 -> 1 when value<100
        77  => X"00004602", -- if value<100, use calculated value
        78  => X"00008C4C", -- sum += 100 (clipped case)
        79  => X"0000C051", -- jump to next element
        80  => X"00008C3C", -- sum += calculated value
        81  => X"000060C0", -- OUTPUT R12 -> expected 02A8
        82  => X"0000C052", -- stop

        -- =========================================================
        -- Dataset copied from IMEM[256...] to DMEM[0...]
        -- DMEM[0..7]   = A
        -- DMEM[8..15]  = B
        -- DMEM[16]     = clip limit 100
        -- =========================================================

        256 => X"0000000A", -- DMEM[0]
        257 => X"00000014", -- DMEM[1]
        258 => X"0000001E", -- DMEM[2]
        259 => X"00000028", -- DMEM[3]
        260 => X"00000032", -- DMEM[4]
        261 => X"0000003C", -- DMEM[5]
        262 => X"00000046", -- DMEM[6]
        263 => X"00000050", -- DMEM[7]
        264 => X"00000005", -- DMEM[8]
        265 => X"0000000A", -- DMEM[9]
        266 => X"0000000F", -- DMEM[10]
        267 => X"00000014", -- DMEM[11]
        268 => X"00000019", -- DMEM[12]
        269 => X"0000001E", -- DMEM[13]
        270 => X"00000023", -- DMEM[14]
        271 => X"00000028", -- DMEM[15]
        272 => X"00000064", -- DMEM[16]

        others => X"00000000"
    );

begin
    insn_out      <= imem(to_integer(unsigned(addr_in)));
    transfer_data <= imem(to_integer(unsigned(transfer_addr)));
end behavioral;
