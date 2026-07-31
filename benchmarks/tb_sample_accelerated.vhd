---------------------------------------------------------------------------
-- instruction_memory_pipelined.vhd
-- Case 2: Teacher sample using CPU + vector coprocessor
--
-- CPU:
--   1. Rearranges the five mark columns into contiguous vectors.
--   2. Dispatches four VADD operations and one VCLIP operation.
--   3. Removes the lower duplicate, sums the remaining totals,
--      divides by seven, and outputs the average.
--
-- Coprocessor:
--   VADD #1: M1 + M2
--   VADD #2: M3 + M4
--   VADD #3: previous two partial totals
--   VADD #4: add M5
--   VCLIP:   cap totals at 100
--
-- Expected final output: 0x004D (77 decimal)
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity tb_sample_accelerated is
    port (
        addr_in       : in  std_logic_vector(7 downto 0);
        insn_out      : out std_logic_vector(31 downto 0);
        transfer_addr : in  std_logic_vector(9 downto 0);
        transfer_data : out std_logic_vector(31 downto 0)
    );
end tb_sample_accelerated;

architecture behavioral of tb_sample_accelerated is
    type mem_array is array (0 to 1023) of std_logic_vector(31 downto 0);

    constant imem : mem_array := (

        -- =========================================================
        -- Final Case 2 program: Teacher sample, CPU + coprocessor
        -- =========================================================

        0   => X"00000000", -- NOOP
        1   => X"00001081", -- LOAD R8,1(R0) -> 15
        2   => X"0000B08D", -- SLT R0,R8,R13 -> R13=1
        3   => X"00008DDE", -- ADD R13,R13,R14 -> R14=2
        4   => X"00008EEF", -- ADD R14,R14,R15 -> R15=4
        5   => X"00008FF7", -- ADD R15,R15,R7 -> R7=8
        6   => X"00008778", -- ADD R7,R7,R8 -> R8=16
        7   => X"00008889", -- ADD R8,R8,R9 -> R9=32
        8   => X"00008992", -- ADD R9,R9,R2 -> R2=64
        9   => X"00008273", -- ADD R2,R7,R3 -> R3=72
        10  => X"00008374", -- ADD R3,R7,R4 -> R4=80
        11  => X"00008475", -- ADD R4,R7,R5 -> R5=88
        12  => X"00008576", -- ADD R5,R7,R6 -> R6=96
        13  => X"00008FEE", -- ADD R15,R14,R14 -> R14=6
        14  => X"00001181", -- LOAD R8,1(R1)
        15  => X"00001192", -- LOAD R9,2(R1)
        16  => X"000011A3", -- LOAD R10,3(R1)
        17  => X"000011B4", -- LOAD R11,4(R1)
        18  => X"000011C5", -- LOAD R12,5(R1)
        19  => X"00003280", -- STORE R8,0(R2)
        20  => X"00003390", -- STORE R9,0(R3)
        21  => X"000034A0", -- STORE R10,0(R4)
        22  => X"000035B0", -- STORE R11,0(R5)
        23  => X"000036C0", -- STORE R12,0(R6)
        24  => X"000081E1", -- raw pointer += 6
        25  => X"000082D2", -- R2 pointer += 1
        26  => X"000083D3", -- R3 pointer += 1
        27  => X"000084D4", -- R4 pointer += 1
        28  => X"000085D5", -- R5 pointer += 1
        29  => X"000086D6", -- R6 pointer += 1
        30  => X"0000A7D7", -- record count -= 1
        31  => X"00004701", -- if count != 0 continue
        32  => X"0000C022", -- all records copied
        33  => X"0000C00E", -- jump copy loop
        34  => X"00008FF8", -- R8=8
        35  => X"0000A281", -- R1=64 srcB
        36  => X"00008202", -- R2=72 srcC
        37  => X"00008603", -- R3=104 dst
        38  => X"00008804", -- R4=8 size
        39  => X"00000000", -- NOOP for R1-R4 writeback
        40  => X"00000000", -- NOOP for R1-R4 writeback
        41  => X"00000000", -- NOOP for R1-R4 writeback
        42  => X"00000000", -- NOOP for R1-R4 writeback
        43  => X"C000F000", -- VADD start
        44  => X"0000E0C0", -- POLL R12
        45  => X"00004C01", -- if done continue
        46  => X"0000C02C", -- poll again
        47  => X"00008281", -- R1=80 srcB
        48  => X"0000A582", -- R2=88 srcC
        49  => X"00008383", -- R3=112 dst
        50  => X"00008804", -- R4=8 size
        51  => X"00000000", -- NOOP for R1-R4 writeback
        52  => X"00000000", -- NOOP for R1-R4 writeback
        53  => X"00000000", -- NOOP for R1-R4 writeback
        54  => X"00000000", -- NOOP for R1-R4 writeback
        55  => X"C000F000", -- VADD start
        56  => X"0000E0C0", -- POLL R12
        57  => X"00004C01", -- if done continue
        58  => X"0000C038", -- poll again
        59  => X"00008601", -- R1=104 srcB
        60  => X"00008302", -- R2=112 srcC
        61  => X"00008383", -- R3=120 dst
        62  => X"00008804", -- R4=8 size
        63  => X"00000000", -- NOOP for R1-R4 writeback
        64  => X"00000000", -- NOOP for R1-R4 writeback
        65  => X"00000000", -- NOOP for R1-R4 writeback
        66  => X"00000000", -- NOOP for R1-R4 writeback
        67  => X"C000F000", -- VADD start
        68  => X"0000E0C0", -- POLL R12
        69  => X"00004C01", -- if done continue
        70  => X"0000C044", -- poll again
        71  => X"00008301", -- R1=120 srcB
        72  => X"00008502", -- R2=96 srcC
        73  => X"00008383", -- R3=128 dst
        74  => X"00008804", -- R4=8 size
        75  => X"00000000", -- NOOP for R1-R4 writeback
        76  => X"00000000", -- NOOP for R1-R4 writeback
        77  => X"00000000", -- NOOP for R1-R4 writeback
        78  => X"00000000", -- NOOP for R1-R4 writeback
        79  => X"C000F000", -- VADD start
        80  => X"0000E0C0", -- POLL R12
        81  => X"00004C01", -- if done continue
        82  => X"0000C050", -- poll again
        83  => X"00008301", -- R1=128 srcB
        84  => X"0000A222", -- R2=0 unused
        85  => X"00008383", -- R3=136 dst
        86  => X"00008804", -- R4=8 size
        87  => X"00000000", -- NOOP for R1-R4 writeback
        88  => X"00000000", -- NOOP for R1-R4 writeback
        89  => X"00000000", -- NOOP for R1-R4 writeback
        90  => X"00000000", -- NOOP for R1-R4 writeback
        91  => X"E000F000", -- VCLIP start
        92  => X"0000E0C0", -- POLL R12
        93  => X"00004C01", -- if done continue
        94  => X"0000C05C", -- poll again
        95  => X"00008301", -- R1=136 clipped pointer
        96  => X"00008802", -- R2=8 count
        97  => X"0000ACCC", -- R12=0 sum
        98  => X"00001190", -- LOAD clipped total
        99  => X"00008C9C", -- sum += total
        100 => X"000081D1", -- pointer +=1
        101 => X"0000A2D2", -- count -=1
        102 => X"00004201", -- if count !=0 continue
        103 => X"0000C069", -- sum complete
        104 => X"0000C062", -- jump sum loop
        105 => X"0000119C", -- LOAD duplicate total 1 at 140
        106 => X"000011AD", -- LOAD duplicate total 2 at 141
        107 => X"0000B9AB", -- R11=1 if first < second
        108 => X"00004B02", -- if first lower
        109 => X"0000ACAC", -- subtract second duplicate
        110 => X"0000C070", -- duplicate handled
        111 => X"0000AC9C", -- subtract first duplicate
        112 => X"00008EDF", -- R15=7
        113 => X"0000ABBB", -- R11=0 quotient
        114 => X"0000BCFA", -- R10=1 if sum <7
        115 => X"00004A03", -- if remainder <7 finish
        116 => X"0000ACFC", -- sum -=7
        117 => X"00008BDB", -- quotient +=1
        118 => X"0000C072", -- repeat division
        119 => X"000060B0", -- OUTPUT R11 expected 004D
        120 => X"0000C078", -- stop

        -- =========================================================
        -- Teacher sample raw dataset
        -- IMEM 256-303 is copied into DMEM 0-47
        -- =========================================================

        256 => X"0000008A",
        257 => X"0000000F",
        258 => X"00000008",
        259 => X"00000009",
        260 => X"00000014",
        261 => X"0000002D",

        262 => X"0000008C",
        263 => X"0000000C",
        264 => X"00000009",
        265 => X"00000006",
        266 => X"0000000F",
        267 => X"00000000",

        268 => X"0000008D",
        269 => X"0000000F",
        270 => X"0000000A",
        271 => X"0000000A",
        272 => X"00000012",
        273 => X"00000037",

        274 => X"0000008F",
        275 => X"0000000A",
        276 => X"00000005",
        277 => X"00000007",
        278 => X"0000000C",
        279 => X"0000002D",

        280 => X"00000091",
        281 => X"0000000A",
        282 => X"0000000A",
        283 => X"00000000",
        284 => X"00000000",
        285 => X"00000000",

        286 => X"00000091",
        287 => X"0000000A",
        288 => X"0000000A",
        289 => X"0000000B",
        290 => X"0000000F",
        291 => X"00000028",

        292 => X"00000093",
        293 => X"00000014",
        294 => X"0000000A",
        295 => X"0000000A",
        296 => X"0000000F",
        297 => X"0000001E",

        298 => X"0000009C",
        299 => X"0000000A",
        300 => X"00000005",
        301 => X"00000006",
        302 => X"00000005",
        303 => X"00000019",

        others => X"00000000"
    );

begin
    insn_out      <= imem(to_integer(unsigned(addr_in)));
    transfer_data <= imem(to_integer(unsigned(transfer_addr)));
end behavioral;
