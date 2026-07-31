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

entity tb_sample_cpu_only is
    port (
        addr_in       : in  std_logic_vector(7 downto 0);
        insn_out      : out std_logic_vector(31 downto 0);
        transfer_addr : in  std_logic_vector(9 downto 0);
        transfer_data : out std_logic_vector(31 downto 0)
    );
end tb_sample_cpu_only;

architecture behavioral of tb_sample_cpu_only is
    type mem_array is array (0 to 1023) of std_logic_vector(31 downto 0);

    constant imem : mem_array := (

        -- =========================================================
        -- Case 1: Teacher sample - CPU only
        --
        -- Process all 8 records
        -- Cap each total at 100
        -- Compare the two duplicate records and remove the lower one
        -- Calculate average of 7 remaining records
        --
        -- Expected final output:
        -- 540 / 7 = 77 = 0x004D
        -- =========================================================

        ----------------------------------------------------------------
        -- Initialise constants
        ----------------------------------------------------------------

        0  => X"00000000", -- NOOP

        -- Load a non-zero value, then use SLT to make constant 1
        1  => X"00001081", -- LOAD R8, 1(R0)  -> R8 = 15
        2  => X"0000B084", -- SLT  R0, R8, R4 -> R4 = 1

        -- Build useful constants
        3  => X"00008449", -- ADD R4, R4, R9   -> R9  = 2
        4  => X"0000899A", -- ADD R9, R9, R10  -> R10 = 4
        5  => X"00008A95", -- ADD R10, R9, R5  -> R5  = 6
        6  => X"0000854F", -- ADD R5, R4, R15  -> R15 = 7
        7  => X"00008AAB", -- ADD R10, R10, R11 -> R11 = 8
        8  => X"00008BBD", -- ADD R11, R11, R13 -> R13 = 16
        9  => X"00008DDE", -- ADD R13, R13, R14 -> R14 = 32
        10 => X"00008EE2", -- ADD R14, R14, R2  -> R2 = 64

        -- Build constant 100
        11 => X"000082E6", -- ADD R2, R14, R6  -> R6 = 96
        12 => X"000086A6", -- ADD R6, R10, R6  -> R6 = 100

        -- Loop counter = 8
        13 => X"00008B03", -- ADD R11, R0, R3 -> R3 = 8

        -- Initial values:
        -- R1  = input pointer  = 0
        -- R2  = output pointer = 64
        -- R3  = record count   = 8
        -- R4  = 1
        -- R5  = 6
        -- R6  = 100
        -- R12 = total sum      = 0
        -- R15 = 7

        14 => X"00000000", -- NOOP


        ----------------------------------------------------------------
        -- Record-processing loop
        -- Each input record occupies 6 DMEM words:
        -- ID, M1, M2, M3, M4, M5
        ----------------------------------------------------------------

        15 => X"00001181", -- LOAD R8,  1(R1) -> mark 1
        16 => X"00001192", -- LOAD R9,  2(R1) -> mark 2
        17 => X"000011A3", -- LOAD R10, 3(R1) -> mark 3
        18 => X"000011B4", -- LOAD R11, 4(R1) -> mark 4
        19 => X"000011D5", -- LOAD R13, 5(R1) -> mark 5

        -- Calculate total in R7
        20 => X"00008897", -- ADD R8, R9, R7
        21 => X"000087A7", -- ADD R7, R10, R7
        22 => X"000087B7", -- ADD R7, R11, R7
        23 => X"000087D7", -- ADD R7, R13, R7

        -- Cap total at 100
        -- R14 = 1 when total < 100
        24 => X"0000B76E", -- SLT R7, R6, R14

        -- If total < 100, skip replacement
        25 => X"00004E01", -- BNE R14, R0, +1

        -- Otherwise total becomes 100
        26 => X"00008607", -- ADD R6, R0, R7

        -- Store one total at DMEM[64..71]
        27 => X"00003270", -- STORE R7, 0(R2)

        -- Add this total into the overall sum
        28 => X"00008C7C", -- ADD R12, R7, R12

        -- Move to next input record
        29 => X"00008151", -- ADD R1, R5, R1 -> input pointer += 6

        -- Move to next output total
        30 => X"00008242", -- ADD R2, R4, R2 -> output pointer += 1

        -- Decrease record count
        31 => X"0000A343", -- SUB R3, R4, R3

        -- Continue loop when R3 is not zero
        32 => X"00004301", -- BNE R3, R0, +1
        33 => X"0000C023", -- JMP 35: processing finished
        34 => X"0000C00F", -- JMP 15: process next record


        ----------------------------------------------------------------
        -- Duplicate handling
        --
        -- After the loop:
        -- R2 = 72
        --
        -- Record 4 total is at DMEM[68] = R2 - 4
        -- Record 5 total is at DMEM[69] = R2 - 3
        --
        -- These are the duplicate ID 0x91 records.
        -- Compare their totals and subtract the lower one from the sum.
        ----------------------------------------------------------------

        35 => X"0000128C", -- LOAD R8, -4(R2) -> first 0x91 total
        36 => X"0000129D", -- LOAD R9, -3(R2) -> second 0x91 total

        -- R13 = 1 when first total < second total
        37 => X"0000B89D", -- SLT R8, R9, R13

        -- If first is lower, jump to address 41
        38 => X"00004D02", -- BNE R13, R0, +2

        -- Otherwise second total is lower
        39 => X"0000AC9C", -- SUB R12, R9, R12
        40 => X"0000C02A", -- JMP 42

        -- First total is lower
        41 => X"0000AC8C", -- SUB R12, R8, R12

        -- At this point:
        -- R12 = 540


        ----------------------------------------------------------------
        -- Divide R12 by 7 using repeated subtraction
        ----------------------------------------------------------------

        42 => X"0000AEEE", -- SUB R14, R14, R14 -> quotient = 0

        -- Division loop
        -- R13 = 1 when remaining sum < 7
        43 => X"0000BCFD", -- SLT R12, R15, R13

        -- Exit division loop when remaining value is below 7
        44 => X"00004D03", -- BNE R13, R0, +3

        -- remaining -= 7
        45 => X"0000ACFC", -- SUB R12, R15, R12

        -- quotient += 1
        46 => X"00008E4E", -- ADD R14, R4, R14

        -- Repeat division
        47 => X"0000C02B", -- JMP 43


        ----------------------------------------------------------------
        -- Final output
        ----------------------------------------------------------------

        48 => X"000060E0", -- OUTPUT R14 -> expected 004D
        49 => X"0000C031", -- JMP 49: stop here


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
