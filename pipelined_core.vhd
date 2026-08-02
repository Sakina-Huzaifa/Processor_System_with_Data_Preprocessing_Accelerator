---------------------------------------------------------------------------
-- pipelined_core.vhd  -  5-Stage Pipelined Processor
--
-- 1. INSTRUCTION WIDTH: 16-bit changed to 32-bit
--      if_id_insn, sig_insn_if are now 32-bit.
--      Field mapping (unchanged for bits 15:0, upper 16 bits new):
--        insn[31:28] = extended opcode / special marker
--        insn[27:24] = reserved / cop_op (for special instructions)
--        insn[23:16] = reserved
--        insn[15:12] = opcode   (same as Lab 3)
--        insn[11:8]  = Rs       (same as Lab 3)
--        insn[7:4]   = Rt / Rd  (same as Lab 3)
--        insn[3:0]   = Rd / imme (same as Lab 3)
--      Basic instructions: upper 16 bits = 0x0000.
--      Special (coprocessor) instructions: upper 16 bits carry extra fields.
--
-- 2. PC WIDTH: 4-bit changed to 8-bit  (addresses 256-word IMEM)
--
-- 3. FORWARDING UNIT  (DATA HAZARD)
--      Two forwarding paths added in the EX stage:
--        fwd_a / fwd_b : "00" = register file (no hazard)
--                        "01" = forward from EX/MEM (1-cycle gap)
--                        "10" = forward from MEM/WB (2-cycle gap)
--      Forwarding MUXes sit in front of the ALU inputs.
--      EX/MEM takes priority over MEM/WB when both match.
--
-- 4. LOAD-USE STALL  (DATA HAZARD - cannot be forwarded)
--      Detected when: EX stage is a LOAD (id_ex_mem_to_reg='1')
--                     AND the next instruction (in ID) reads that register.
--      Action: freeze PC + IF/ID for 1 cycle, insert bubble into ID/EX.
--      sig_stall drives all three of these.
--
-- 5. STALL vs SQUASH PRIORITY
--      Branch squash (sig_branch_taken) takes priority over stall.
--      Both conditions are checked independently in each process.
--
-- 6. COPROCESSOR INTERFACE (new signals, driven in ID stage)
--      cop_start  : pulsed for 1 cycle when opcode = OP_SPECIAL
--      cop_op     : 2-bit operation (from insn[29:28])
--      cop_done   : input from coprocessor, readable via POLL instruction
--      cop_dst/srcB/srcC/size : taken from R1/R2/R3/R4 at dispatch time
--
-- SIGNALS THAT ARE UNCHANGED FORM THE LAB 3 TASK 2
-- ────────────────────────────────────────
--   sig_slow_clk, clock_divider process
--   Control unit port map (same 10 outputs)
--   Register file port map (same interface)
--   adder_16b_saturating (ALU component, unchanged)
--   EX stage branch logic (sig_branch_taken, sig_branch_target)
--   MEM stage (data_memory port map)
--   WB stage mux (sig_wb_data priority)
--   Board output assignments (leds, seg, an)
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pipelined_core is
    generic ( g_CLK_DIV : integer := 8000000 );
    port (
        reset    : in  std_logic;
        clk      : in  std_logic;
        switches : in  std_logic_vector(15 downto 0);
        
        -- board output signals
        output_reg_out : out std_logic_vector(15 downto 0);
        cop1_out       : out std_logic_vector(15 downto 0);
        cop2_out       : out std_logic_vector(15 downto 0);
        flag_out       : out std_logic;
        
        -- Coprocessor interface
        cop_start    : out std_logic;
        cop_op       : out std_logic_vector(1 downto 0);
        cop_dst      : out std_logic_vector(7 downto 0);
        cop_srcB     : out std_logic_vector(7 downto 0);
        cop_srcC     : out std_logic_vector(7 downto 0);
        cop_size     : out std_logic_vector(7 downto 0);
        cop_done     : in  std_logic;
          
        cop_busy         : in  std_logic;
        cop_addr_in      : in  std_logic_vector(9 downto 0);
        cop_write_data   : in  std_logic_vector(15 downto 0);
        cop_write_enable : in  std_logic;
        
        -- Signals returned to the coprocessor
        cop_read_data    : out std_logic_vector(15 downto 0);
        cop_clk_out      : out std_logic
    );
end pipelined_core;

architecture pipelined of pipelined_core is

    -- CHANGED FROM LAB 3: addr_in widened to 8-bit, insn_out widened to 32-bit
    component instruction_memory_pipelined is
        port ( addr_in  : in  std_logic_vector(7 downto 0);
               insn_out : out std_logic_vector(31 downto 0);
               transfer_addr : in std_logic_vector(9 downto 0);
               transfer_data   : out std_logic_vector(31 downto 0));
    end component;

    component control_unit is
        port ( opcode     : in  std_logic_vector(3 downto 0);
               reg_dst    : out std_logic; reg_write  : out std_logic;
               alu_src    : out std_logic; mem_write  : out std_logic;
               mem_to_reg : out std_logic; in_to_reg  : out std_logic;
               out_enable : out std_logic; alu_mode   : out std_logic;
               branch     : out std_logic; dis_enable : out std_logic;
               sub_enable : out std_logic; slt_enable : out std_logic;
               jump       : out std_logic);

    end component;

    component register_file is
        port ( reset           : in  std_logic; clk : in std_logic;
               read_register_a : in  std_logic_vector(3 downto 0);
               read_register_b : in  std_logic_vector(3 downto 0);
               read_register_c : in  std_logic_vector(3 downto 0);
               read_register_d : in  std_logic_vector(3 downto 0);
               write_enable    : in  std_logic;
               write_register  : in  std_logic_vector(3 downto 0);
               write_data      : in  std_logic_vector(15 downto 0);
               read_data_a     : out std_logic_vector(15 downto 0);
               read_data_b     : out std_logic_vector(15 downto 0);
               read_data_c     : out std_logic_vector(15 downto 0);
               read_data_d     : out std_logic_vector(15 downto 0) );
    end component;

    component sign_extend_4to16 is
        port ( data_in  : in  std_logic_vector(3 downto 0);
               data_out : out std_logic_vector(15 downto 0) );
    end component;

    -- CHANGED FROM LAB 3: widened to 8-bit (PC is now 8-bit)
    component adder_8b is
        port ( src_a     : in  std_logic_vector(7 downto 0);
               src_b     : in  std_logic_vector(7 downto 0);
               sum       : out std_logic_vector(7 downto 0);
               carry_out : out std_logic );
    end component;

    component adder_16b_saturating is
        port ( src_a : in std_logic_vector(15 downto 0);
               src_b : in std_logic_vector(15 downto 0);
               sat_mode : in std_logic;
               sum   : out std_logic_vector(15 downto 0);
               carry_out : out std_logic );
    end component;

    component simple_alu is
        port (
            src_a  : in  std_logic_vector(15 downto 0);
            src_b  : in  std_logic_vector(15 downto 0);
            is_slt : in  std_logic;
            result : out std_logic_vector(15 downto 0)
        );
    end component;

    component data_memory is
        port ( reset : in std_logic; clk : in std_logic;
               write_enable : in std_logic;
               write_data   : in std_logic_vector(15 downto 0);
               addr_in      : in std_logic_vector(9 downto 0);
               data_out     : out std_logic_vector(15 downto 0);
               cop_busy         : in std_logic;
               cop_write_enable : in std_logic;
               cop_write_data   : in std_logic_vector(15 downto 0);
               cop_addr_in      : in std_logic_vector(9 downto 0);
               transfer_busy         : in std_logic;
               transfer_write_enable : in std_logic;
               transfer_write_data   : in std_logic_vector(15 downto 0);
               transfer_addr_in      : in std_logic_vector(9 downto 0));
    end component;

    component memory_transfer is
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
            done : out std_logic  );
     end component;

    ---------------------------------------------------------------------------
    -- Opcode constants
    ---------------------------------------------------------------------------
    constant OP_NOOP    : std_logic_vector(3 downto 0) := "0000";
    constant OP_LOAD    : std_logic_vector(3 downto 0) := "0001";
    constant OP_STORE   : std_logic_vector(3 downto 0) := "0011";
    constant OP_BNE     : std_logic_vector(3 downto 0) := "0100";
    constant OP_INPUT   : std_logic_vector(3 downto 0) := "0101";
    constant OP_OUTPUT  : std_logic_vector(3 downto 0) := "0110";
    constant OP_DIS     : std_logic_vector(3 downto 0) := "0111";
    constant OP_ADD     : std_logic_vector(3 downto 0) := "1000";
    constant OP_SADD    : std_logic_vector(3 downto 0) := "1001";
    -- NEW opcodes for assignment
    constant OP_SPECIAL : std_logic_vector(3 downto 0) := "1111"; -- coprocessor
    constant OP_POLL    : std_logic_vector(3 downto 0) := "1110"; -- read cop_done

    constant OP_SUB : std_logic_vector(3 downto 0) := "1010";
    constant OP_SLT : std_logic_vector(3 downto 0) := "1011";
    constant OP_JMP : std_logic_vector(3 downto 0) := "1100";

    ---------------------------------------------------------------------------
    -- IF stage signals
    ---------------------------------------------------------------------------
    signal sig_pc        : std_logic_vector(7 downto 0) := (others => '0');
    signal sig_pc_next   : std_logic_vector(7 downto 0);
    signal sig_pc_plus_1 : std_logic_vector(7 downto 0);
    signal sig_pc_carry  : std_logic;
    signal sig_one_8b    : std_logic_vector(7 downto 0);

    signal sig_insn_if   : std_logic_vector(31 downto 0);

    -- IF/ID pipeline register
    signal if_id_insn      : std_logic_vector(31 downto 0) := (others => '0');
    signal if_id_pc_plus_1 : std_logic_vector(7 downto 0)  := (others => '0');

    ---------------------------------------------------------------------------
    -- ID stage signals
    ---------------------------------------------------------------------------
    signal sig_reg_dst, sig_reg_write, sig_alu_src      : std_logic;
    signal sig_mem_write, sig_mem_to_reg, sig_in_to_reg : std_logic;
    signal sig_out_enable, sig_alu_mode                 : std_logic;
    signal sig_branch, sig_dis_enable                   : std_logic;
    signal sig_rd_a, sig_rd_b  : std_logic_vector(15 downto 0);
    signal sig_rd_c, sig_rd_d  : std_logic_vector(15 downto 0);
    signal sig_sign_ext        : std_logic_vector(15 downto 0);
    signal sig_wreg_id         : std_logic_vector(3 downto 0);

    signal sig_rs_idx : std_logic_vector(3 downto 0);   -- insn[11:8]
    signal sig_rt_idx : std_logic_vector(3 downto 0);   -- insn[7:4]

    signal sig_read_reg_a : std_logic_vector(3 downto 0);
    signal sig_read_reg_b : std_logic_vector(3 downto 0);

    -- ID/EX pipeline register
    signal id_ex_pc_plus_1 : std_logic_vector(7 downto 0)  := (others => '0');
    signal id_ex_rd_a      : std_logic_vector(15 downto 0) := (others => '0');
    signal id_ex_rd_b      : std_logic_vector(15 downto 0) := (others => '0');
    signal id_ex_sign_ext  : std_logic_vector(15 downto 0) := (others => '0');
    signal id_ex_imme      : std_logic_vector(3 downto 0)  := (others => '0');
    signal id_ex_jump_target : std_logic_vector(7 downto 0):= (others => '0');
    signal id_ex_wreg      : std_logic_vector(3 downto 0)  := (others => '0');
    signal id_ex_rs_idx    : std_logic_vector(3 downto 0)  := (others => '0');
    signal id_ex_rt_idx    : std_logic_vector(3 downto 0)  := (others => '0');
    signal id_ex_switches  : std_logic_vector(15 downto 0) := (others => '0');
    signal id_ex_reg_write, id_ex_alu_src, id_ex_alu_mode   : std_logic := '0';
    signal id_ex_sub_enable : std_logic := '0';
    signal id_ex_slt_enable : std_logic := '0';
    signal id_ex_jump       : std_logic := '0';
    signal id_ex_mem_write, id_ex_mem_to_reg, id_ex_in_to_reg : std_logic := '0';
    signal id_ex_out_enable, id_ex_branch, id_ex_dis_enable : std_logic := '0';
    signal id_ex_is_poll   : std_logic := '0';  -- NEW: POLL instruction flag

    ---------------------------------------------------------------------------
    -- EX stage signals
    ---------------------------------------------------------------------------
    signal sig_alu_a         : std_logic_vector(15 downto 0); -- forwarded A
    signal sig_alu_b_fwd     : std_logic_vector(15 downto 0); -- forwarded B
    signal sig_alu_b         : std_logic_vector(15 downto 0);
    signal sig_alu_result    : std_logic_vector(15 downto 0);
    signal sig_simple_result : std_logic_vector(15 downto 0);
    signal sig_final_result  : std_logic_vector(15 downto 0);
    signal sig_sub_enable    : std_logic;
    signal sig_slt_enable    : std_logic;
    signal sig_jump          : std_logic;
    signal sig_alu_carry     : std_logic;
    signal sig_branch_target : std_logic_vector(7 downto 0);
    signal sig_br_carry      : std_logic;
    signal sig_not_equal     : std_logic;
    signal sig_branch_taken  : std_logic;
    signal sig_control_redirect : std_logic;

    -- forwarding select signals (2-bit each)
    -- "00" = use register file value (no hazard)
    -- "01" = forward from EX/MEM stage (1-cycle gap)
    -- "10" = forward from MEM/WB stage (2-cycle gap)
    signal fwd_a : std_logic_vector(1 downto 0);
    signal fwd_b : std_logic_vector(1 downto 0);

    -- load-use stall signal
    signal sig_stall    : std_logic;

    -- zero-extended immediate for branch adder port map
    signal sig_imme_ext : std_logic_vector(7 downto 0);

    -- EX/MEM pipeline register
    signal ex_mem_alu_result : std_logic_vector(15 downto 0) := (others => '0');
    signal ex_mem_rd_b       : std_logic_vector(15 downto 0) := (others => '0');
    signal ex_mem_wreg       : std_logic_vector(3 downto 0)  := (others => '0');
    signal ex_mem_switches   : std_logic_vector(15 downto 0) := (others => '0');
    signal ex_mem_reg_write, ex_mem_mem_write, ex_mem_mem_to_reg : std_logic := '0';
    signal ex_mem_in_to_reg, ex_mem_out_enable, ex_mem_dis_enable : std_logic := '0';

    ---------------------------------------------------------------------------
    -- MEM stage / MEM/WB register
    ---------------------------------------------------------------------------
    signal sig_dmem_out      : std_logic_vector(15 downto 0);
    signal mem_wb_alu_result : std_logic_vector(15 downto 0) := (others => '0');
    signal mem_wb_dmem_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal mem_wb_switches   : std_logic_vector(15 downto 0) := (others => '0');
    signal mem_wb_wreg       : std_logic_vector(3 downto 0)  := (others => '0');
    signal mem_wb_reg_write, mem_wb_mem_to_reg, mem_wb_in_to_reg : std_logic := '0';

    ---------------------------------------------------------------------------
    -- WB stage 
    ---------------------------------------------------------------------------
    signal sig_wb_data : std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- Board I/O / special registers
    ---------------------------------------------------------------------------
    signal sig_output_register : std_logic_vector(15 downto 0) := (others => '0');
    signal sig_cop1            : std_logic_vector(15 downto 0) := (others => '0');
    signal sig_cop2            : std_logic_vector(15 downto 0) := (others => '0');
    signal sig_flag            : std_logic := '0';

    signal sig_div_counter     : std_logic_vector(26 downto 0) := (others => '0');
    signal sig_slow_clk        : std_logic := '0';
    signal sig_display_value   : std_logic_vector(15 downto 0);
    signal sig_refresh_counter : std_logic_vector(16 downto 0) := (others => '0');
    signal sig_digit_select    : std_logic_vector(1 downto 0);
    signal sig_digit_value     : std_logic_vector(3 downto 0);
    
    ---------------------------------------------------------------------------------
    -- Signals for data transfer
    --------------------------------------------------------------------------------
    signal sig_transfer_addr        : std_logic_vector(9 downto 0);
    signal sig_transfer_write_data  : std_logic_vector(15 downto 0);
    signal sig_transfer_write_enable: std_logic;
    signal sig_transfer_busy        : std_logic;
    signal sig_transfer_done        : std_logic ;
    
    signal sig_transfer_imem_addr   : std_logic_vector(9 downto 0);
    signal sig_transfer_imem_data   : std_logic_vector(31 downto 0);

begin

    sig_one_8b <= x"01";

    ---------------------------------------------------------------------------
    -- Clock divider
    ---------------------------------------------------------------------------
    clock_divider : process(clk, reset)
    begin
        if reset = '1' then
            sig_div_counter <= (others => '0');
            sig_slow_clk    <= '0';
        elsif rising_edge(clk) then
            if sig_div_counter >= g_CLK_DIV then
                sig_div_counter <= (others => '0');
                sig_slow_clk    <= not sig_slow_clk;
            else
                sig_div_counter <= sig_div_counter + 1;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- STAGE 1 : IF  -  Instruction Fetch
    -- stall freezes PC (sig_stall = '1' holds sig_pc)
    ---------------------------------------------------------------------------
    add_pc1 : adder_8b
        port map (
            src_a     => sig_pc,
            src_b     => sig_one_8b,
            sum       => sig_pc_plus_1,
            carry_out => sig_pc_carry
        );

    -- PC next-value selection:
    --   1. Branch taken redirect to branch target(highest priority)
    --   2. Load-use stall hold current PC(freeze)
    --   3. Normal PC + 1
    sig_pc_next <= sig_pc            when sig_transfer_done = '0' else
                id_ex_jump_target when id_ex_jump = '1' else
                sig_branch_target when sig_branch_taken = '1' else
                sig_pc            when sig_stall = '1' else
                sig_pc_plus_1;

    pc_register : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            sig_pc <= (others => '0');
        elsif rising_edge(sig_slow_clk) then
            sig_pc <= sig_pc_next;
        end if;
    end process;

    -- IMEM
    insn_mem : instruction_memory_pipelined
        port map (
            addr_in  => sig_pc,
            insn_out => sig_insn_if,

            transfer_addr => sig_transfer_imem_addr,
            transfer_data => sig_transfer_imem_data  );
    
    -- data transfer from IMEM to DMEM
    transfer_mem : memory_transfer
        port map ( clk             => sig_slow_clk,
            reset           => reset,
            start           => '1',
            transfer_size   => "0000110000", -- temp value for test purpose
        
            imem_addr       => sig_transfer_imem_addr,
            imem_data       => sig_transfer_imem_data,
        
            dmem_addr         => sig_transfer_addr,
            dmem_write_data   => sig_transfer_write_data,
            dmem_write_enable => sig_transfer_write_enable,
        
            busy            => sig_transfer_busy,
            done            => sig_transfer_done );

    ---------------------------------------------------------------------------
    -- IF/ID Pipeline Register
    -- stall freezes the register (holds current values)
    ---------------------------------------------------------------------------
    if_id_register : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            if_id_insn      <= (others => '0');
            if_id_pc_plus_1 <= (others => '0');
        elsif rising_edge(sig_slow_clk) then
            if sig_control_redirect = '1' then
                -- SQUASH: branch taken, discard fetched instruction NOP
                if_id_insn      <= (others => '0');
                if_id_pc_plus_1 <= (others => '0');
            elsif sig_stall = '1' then
                -- STALL: freeze IF/ID (do not update - hold current values)
                if_id_insn      <= if_id_insn;
                if_id_pc_plus_1 <= if_id_pc_plus_1;
            else
                -- NORMAL: latch new instruction
                if_id_insn      <= sig_insn_if;
                if_id_pc_plus_1 <= sig_pc_plus_1;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- STAGE 2 : ID  -  Decode and Register Read
    ---------------------------------------------------------------------------

    -- Convenience aliases for forwarding comparisons
    sig_rs_idx <= if_id_insn(11 downto 8);
    sig_rt_idx <= if_id_insn(7 downto 4);

    -- Control unit: reads bits [15:12]
    ctrl_unit : control_unit
        port map (
            opcode     => if_id_insn(15 downto 12),
            reg_dst    => sig_reg_dst,    reg_write  => sig_reg_write,
            alu_src    => sig_alu_src,    mem_write  => sig_mem_write,
            mem_to_reg => sig_mem_to_reg, in_to_reg  => sig_in_to_reg,
            out_enable => sig_out_enable, alu_mode   => sig_alu_mode,
            branch     => sig_branch,     dis_enable => sig_dis_enable,
            sub_enable => sig_sub_enable,
            slt_enable => sig_slt_enable,
            jump       => sig_jump
        );

    
    sig_read_reg_a <= "0011"
        when if_id_insn(15 downto 12) = OP_SPECIAL
        else if_id_insn(11 downto 8);

    sig_read_reg_b <= "0001"
        when if_id_insn(15 downto 12) = OP_SPECIAL
        else if_id_insn(7 downto 4);

    -- Register file
    reg_file : register_file
        port map (
            reset           => reset,
            clk             => sig_slow_clk,

            read_register_a => sig_read_reg_a,
            read_register_b => sig_read_reg_b,
            read_register_c => "0010",
            read_register_d => "0100",

            write_enable    => mem_wb_reg_write,
            write_register  => mem_wb_wreg,
            write_data      => sig_wb_data,
            read_data_a     => sig_rd_a,
            read_data_b     => sig_rd_b,
            read_data_c     => sig_rd_c,
            read_data_d     => sig_rd_d
        );

    -- Sign extend
    sign_extend : sign_extend_4to16
        port map (
            data_in  => if_id_insn(3 downto 0),
            data_out => sig_sign_ext
        );

    -- Destination register select
    sig_wreg_id <= if_id_insn(3 downto 0) when sig_reg_dst = '1'
                   else if_id_insn(7 downto 4);

    ---------------------------------------------------------------------------
    -- ID/EX Pipeline Register
    ---------------------------------------------------------------------------
    id_ex_register : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            id_ex_pc_plus_1  <= (others => '0');
            id_ex_rd_a       <= (others => '0');
            id_ex_rd_b       <= (others => '0');
            id_ex_sign_ext   <= (others => '0');
            id_ex_imme       <= (others => '0');
            id_ex_wreg       <= (others => '0');
            id_ex_rs_idx     <= (others => '0'); 
            id_ex_rt_idx     <= (others => '0'); 
            id_ex_switches   <= (others => '0');
            id_ex_jump_target <= (others => '0');
            id_ex_reg_write  <= '0'; id_ex_alu_src    <= '0';
            id_ex_alu_mode   <= '0'; id_ex_mem_write  <= '0';
            id_ex_mem_to_reg <= '0'; id_ex_in_to_reg  <= '0';
            id_ex_out_enable <= '0'; id_ex_branch     <= '0';
            id_ex_dis_enable <= '0'; id_ex_is_poll    <= '0';
            id_ex_sub_enable <= '0';
            id_ex_slt_enable <= '0';
            id_ex_jump       <= '0';
            

        elsif rising_edge(sig_slow_clk) then

            if sig_control_redirect = '1' then
                ---------------------------------------------------------------
                -- SQUASH: branch taken
                -- Clear all control signals instruction becomes a bubble.
                ---------------------------------------------------------------
                id_ex_reg_write  <= '0'; id_ex_alu_src    <= '0';
                id_ex_alu_mode   <= '0'; id_ex_mem_write  <= '0';
                id_ex_mem_to_reg <= '0'; id_ex_in_to_reg  <= '0';
                id_ex_out_enable <= '0'; id_ex_branch     <= '0';
                id_ex_dis_enable <= '0'; id_ex_is_poll    <= '0';
                id_ex_rd_a       <= (others => '0');
                id_ex_rd_b       <= (others => '0');
                id_ex_wreg       <= (others => '0');
                id_ex_rs_idx     <= (others => '0');
                id_ex_rt_idx     <= (others => '0');
                id_ex_jump_target <= (others => '0');
                id_ex_sub_enable <= '0';
                id_ex_slt_enable <= '0';
                id_ex_jump       <= '0';

            elsif sig_stall = '1' then
                ---------------------------------------------------------------
                -- STALL: load-use hazard detected
                -- Insert a bubble: zero control signals.
                -- IF/ID is frozen (held above), so the same instruction will
                -- be decoded again next cycle once the stall is cleared.
                ---------------------------------------------------------------
                id_ex_reg_write  <= '0'; id_ex_alu_src    <= '0';
                id_ex_alu_mode   <= '0'; id_ex_mem_write  <= '0';
                id_ex_mem_to_reg <= '0'; id_ex_in_to_reg  <= '0';
                id_ex_out_enable <= '0'; id_ex_branch     <= '0';
                id_ex_dis_enable <= '0'; id_ex_is_poll    <= '0';
                id_ex_rd_a       <= (others => '0');
                id_ex_rd_b       <= (others => '0');
                id_ex_wreg       <= (others => '0');
                id_ex_rs_idx     <= (others => '0');
                id_ex_rt_idx     <= (others => '0');
                id_ex_jump_target <= (others => '0');
                id_ex_sub_enable <= '0';
                id_ex_slt_enable <= '0';
                id_ex_jump       <= '0';

            else
                ---------------------------------------------------------------
                -- NORMAL latch
                ---------------------------------------------------------------
                id_ex_pc_plus_1  <= if_id_pc_plus_1;
                id_ex_rd_a       <= sig_rd_a;
                id_ex_rd_b       <= sig_rd_b;
                id_ex_sign_ext   <= sig_sign_ext;
                id_ex_imme       <= if_id_insn(3 downto 0);
                id_ex_jump_target <= if_id_insn(7 downto 0);
                id_ex_wreg       <= sig_wreg_id;
                id_ex_rs_idx     <= sig_rs_idx; 
                id_ex_rt_idx     <= sig_rt_idx; 
                id_ex_switches   <= switches;
                id_ex_reg_write  <= sig_reg_write;
                id_ex_alu_src    <= sig_alu_src;
                id_ex_alu_mode   <= sig_alu_mode;
                id_ex_mem_write  <= sig_mem_write;
                id_ex_mem_to_reg <= sig_mem_to_reg;
                id_ex_in_to_reg  <= sig_in_to_reg;
                id_ex_out_enable <= sig_out_enable;
                id_ex_branch     <= sig_branch;
                id_ex_dis_enable <= sig_dis_enable;
                id_ex_sub_enable <= sig_sub_enable;
                id_ex_slt_enable <= sig_slt_enable;
                id_ex_jump       <= sig_jump;
                -- flag POLL instruction (if/else required inside a process)
                if if_id_insn(15 downto 12) = OP_POLL then
                    id_ex_is_poll <= '1';
                else
                    id_ex_is_poll <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Coprocessor dispatch
    -- When OP_SPECIAL is decoded and no stall/squash is active:
    --   - pulse cop_start for 1 cycle
    --   - latch the calling-convention registers (R1=srcB, R2=srcC,
    --     R3=dst, R4=size) into the coprocessor control outputs
    --   - cop_op comes from insn[29:28] (upper instruction bits)
    ---------------------------------------------------------------------------
    cop_start <= '1' when (if_id_insn(15 downto 12) = OP_SPECIAL
                           and sig_stall = '0'
                           and sig_control_redirect = '0'
                           and cop_busy = '0')
                 else '0';

    cop_op   <= if_id_insn(29 downto 28);          -- from upper 16 bits

    -- The register file outputs sig_rd_a (Rs=R1..R4) during the SAME cycle
    -- as decode.  We use combinational reads from the reg file to get all
    -- four calling-convention registers.  For simplicity we read them via
    -- For OP_SPECIAL, the four register file read ports provide:
    -- R1 = srcB, R2 = srcC, R3 = dst, R4 = size.
    cop_dst  <= sig_rd_a(7 downto 0);   -- R3 (port A reads Rs = insn[11:8])
    cop_srcB <= sig_rd_b(7 downto 0);   -- R1 (port B reads Rt = insn[7:4])
    cop_srcC <= sig_rd_c(7 downto 0);         -- R2: would need a 3rd read port
    cop_size <= sig_rd_d(7 downto 0);         -- R4: would need a 4th read port
    
    ---------------------------------------------------------------------------
    -- STAGE 3 : EX  -  ALU Operation and Branch Resolution
    --
    -- FORWARDING UNIT
    -- 
    -- Checks whether the instruction currently in EX needs a value that is
    -- still "in flight" in the pipeline (not yet written back to the register
    -- file).  Two forward paths exist:
    --
    --   EX/MEM - EX  ("01"):  the instruction just ahead wrote a result that
    --                          is now sitting in ex_mem_alu_result.
    --
    --   MEM/WB - EX  ("10"):  two instructions ahead; result is in sig_wb_data
    --                          (which is the WB mux output - already accounts
    --                          for LW: uses dmem_out if mem_to_reg='1').
    --
    -- Priority: EX/MEM wins over MEM/WB when both match (can't happen for
    --           data that is correctly in-order, but the priority is needed
    --           if both stages happen to write the same register).
    --
    -- Special case: register "0000" is never forwarded (it is hardwired 0
    --               in most ISAs; in this ISA R0 is not special, but wreg
    --               initialises to "0000" on reset so we exclude it to avoid
    --               spurious forwards during the pipeline fill).
    ---------------------------------------------------------------------------

    -- fwd_a: select for ALU input A (Rs)
    fwd_a <= "01" when (ex_mem_reg_write = '1'
                        and ex_mem_wreg /= "0000"
                        and ex_mem_wreg = id_ex_rs_idx) else
             "10" when (mem_wb_reg_write = '1'
                        and mem_wb_wreg /= "0000"
                        and mem_wb_wreg = id_ex_rs_idx) else
             "00";

    -- fwd_b: select for ALU input B (Rt before immediate MUX)
    fwd_b <= "01" when (ex_mem_reg_write = '1'
                        and ex_mem_wreg /= "0000"
                        and ex_mem_wreg = id_ex_rt_idx) else
             "10" when (mem_wb_reg_write = '1'
                        and mem_wb_wreg /= "0000"
                        and mem_wb_wreg = id_ex_rt_idx) else
             "00";

    -- ALU input A MUX (NEW)
    sig_alu_a <= ex_mem_alu_result when fwd_a = "01" else
                 sig_wb_data       when fwd_a = "10" else
                 id_ex_rd_a;           -- no hazard: use register file value

    -- ALU input B MUX - forwarding first, then immediate select 
    -- In Lab 3 this was just:
    --   sig_alu_b <= id_ex_sign_ext when id_ex_alu_src='1' else id_ex_rd_b;
    -- Now we add the forwarding MUX on the register-file path only:
    sig_alu_b_fwd <= ex_mem_alu_result when fwd_b = "01" else
                     sig_wb_data       when fwd_b = "10" else
                     id_ex_rd_b;           -- no hazard

    sig_alu_b <= id_ex_sign_ext when id_ex_alu_src = '1' else
                 sig_alu_b_fwd;    -- forwarded Rt (or original if no hazard)

    -- ALU
    alu : adder_16b_saturating
        port map (
            src_a     => sig_alu_a,
            src_b     => sig_alu_b,
            sat_mode  => id_ex_alu_mode,
            sum       => sig_alu_result,
            carry_out => sig_alu_carry
        );

    simplealu : simple_alu
        port map(
            src_a  => sig_alu_a,
            src_b  => sig_alu_b_fwd,
            is_slt => id_ex_slt_enable,
            result => sig_simple_result
        );

    -- Select the result from the correct ALU
    sig_final_result <= sig_simple_result
                        when (id_ex_sub_enable = '1' or
                            id_ex_slt_enable = '1')
                        else sig_alu_result;

    ---------------------------------------------------------------------------
    -- LOAD-USE HAZARD DETECTION 
    -- Condition:
    --   (a) The instruction currently in EX is a LOAD  (id_ex_mem_to_reg='1')
    --   (b) The instruction currently in ID reads the same destination
    --       register that the LOAD will write.
    --
    -- We check both Rs (insn[11:8]) and Rt (insn[7:4]) of the ID instruction
    -- against id_ex_wreg (the LOAD's destination).
    --
    -- Forwarding CANNOT resolve this because the loaded value does not exist
    -- until the end of the MEM stage - one cycle too late for EX forwarding.
    --
    -- Action when sig_stall = '1':
    --   - PC is held (handled in IF stage above)
    --   - IF/ID register is held (handled in IF/ID register process above)
    --   - ID/EX register is filled with a bubble (handled in ID/EX process)
    ---------------------------------------------------------------------------
    sig_stall <= '1' when (
                     id_ex_mem_to_reg = '1'              -- EX is a LOAD
                     and id_ex_wreg /= "0000"            -- and it writes somewhere
                     and (   id_ex_wreg = sig_rs_idx     -- ID reads that register (Rs)
                          or id_ex_wreg = sig_rt_idx)    -- ID reads that register (Rt)
                 ) else '0';

    ---------------------------------------------------------------------------
    -- Branch logic 
    -- Branch target is now 8-bit to match the widened PC.
    -- sig_imme_ext zero-extends the 4-bit immediate to 8-bit so it can be
    -- passed into the adder_8b port map as a named signal
    ---------------------------------------------------------------------------
    -- sig_imme_ext <= "0000" & id_ex_imme; 
    sig_imme_ext <= "1111" & id_ex_imme
    when id_ex_imme(3) = '1'
    else "0000" & id_ex_imme;

    sig_control_redirect <= sig_branch_taken or id_ex_jump;

    add_branch : adder_8b
        port map (
            src_a     => id_ex_pc_plus_1,
            src_b     => sig_imme_ext,
            sum       => sig_branch_target,
            carry_out => sig_br_carry
        );

    -- BNE comparator:
    sig_not_equal   <= '1' when (sig_alu_a /= sig_alu_b_fwd) else '0';
    sig_branch_taken <= id_ex_branch and sig_not_equal;

    ---------------------------------------------------------------------------
    -- EX/MEM Pipeline Register
    ---------------------------------------------------------------------------
    ex_mem_register : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            ex_mem_alu_result <= (others => '0');
            ex_mem_rd_b       <= (others => '0');
            ex_mem_wreg       <= (others => '0');
            ex_mem_switches   <= (others => '0');
            ex_mem_reg_write  <= '0'; ex_mem_mem_write  <= '0';
            ex_mem_mem_to_reg <= '0'; ex_mem_in_to_reg  <= '0';
            ex_mem_out_enable <= '0'; ex_mem_dis_enable <= '0';
        elsif rising_edge(sig_slow_clk) then
        
        -------------#######################
            -- For POLL instruction: write cop_done status into alu_result
            -- so it flows through to WB and into the register file.
                                         -------------#######################
                                         
            if id_ex_is_poll = '1' then
                ex_mem_alu_result <= "000000000000000" & cop_done;
            else
                ex_mem_alu_result <= sig_final_result;
            end if;
            ex_mem_rd_b       <= sig_alu_b_fwd;
            ex_mem_wreg       <= id_ex_wreg;
            ex_mem_switches   <= id_ex_switches;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_in_to_reg  <= id_ex_in_to_reg;
            ex_mem_out_enable <= id_ex_out_enable;
            ex_mem_dis_enable <= id_ex_dis_enable;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- STAGE 4 : MEM  -  Data Memory Access, OUT, DIS
    ---------------------------------------------------------------------------
    data_mem : data_memory
        port map (
            reset        => reset,
            clk          => sig_slow_clk,
            write_enable => ex_mem_mem_write,
            write_data   => ex_mem_rd_b,
            addr_in      => ex_mem_alu_result(9 downto 0),
            data_out     => sig_dmem_out,

            -- co-processor
            cop_busy    => cop_busy,
            cop_write_enable => cop_write_enable,
            cop_write_data  => cop_write_data,
            cop_addr_in => cop_addr_in,
            
            -- IMEM to DMEM transfer
            transfer_busy   => sig_transfer_busy,
            transfer_write_enable => sig_transfer_write_enable,
            transfer_write_data => sig_transfer_write_data,
            transfer_addr_in    => sig_transfer_addr        
        );

    output_register : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            sig_output_register <= (others => '0');
        elsif rising_edge(sig_slow_clk) then
            if ex_mem_out_enable = '1' then
                sig_output_register <= ex_mem_rd_b;
            end if;
        end if;
    end process;

    dis_registers : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            sig_cop1 <= (others => '0');
            sig_cop2 <= (others => '0');
            sig_flag <= '0';
        elsif rising_edge(sig_slow_clk) then
            if ex_mem_dis_enable = '1' then
                sig_cop1 <= ex_mem_alu_result;
                sig_cop2 <= ex_mem_rd_b;
                sig_flag <= '1';
            end if;
        end if;
    end process;

    mem_wb_register : process(reset, sig_slow_clk)
    begin
        if reset = '1' then
            mem_wb_alu_result <= (others => '0');
            mem_wb_dmem_out   <= (others => '0');
            mem_wb_switches   <= (others => '0');
            mem_wb_wreg       <= (others => '0');
            mem_wb_reg_write  <= '0';
            mem_wb_mem_to_reg <= '0';
            mem_wb_in_to_reg  <= '0';
        elsif rising_edge(sig_slow_clk) then
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_dmem_out   <= sig_dmem_out;
            mem_wb_switches   <= ex_mem_switches;
            mem_wb_wreg       <= ex_mem_wreg;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_in_to_reg  <= ex_mem_in_to_reg;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- STAGE 5 : WB  -  Write Back
    ---------------------------------------------------------------------------
    sig_wb_data <= mem_wb_switches   when mem_wb_in_to_reg  = '1' else
                   mem_wb_dmem_out   when mem_wb_mem_to_reg = '1' else
                   mem_wb_alu_result;


    -- Data read from the shared DMEM for the coprocessor
    cop_read_data <= sig_dmem_out;

    -- Use the same clock for the CPU, DMEM and coprocessor
    cop_clk_out <= sig_slow_clk;

    ---------------------------------------------------------------------------
    -- Board output signals - display output logic MOVED to board_wrapper
    ---------------------------------------------------------------------------
    output_reg_out <= sig_output_register;
    cop1_out       <= sig_cop1;
    cop2_out       <= sig_cop2;
    flag_out       <= sig_flag;

end pipelined;
