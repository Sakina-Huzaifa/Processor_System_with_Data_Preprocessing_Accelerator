library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity processor_system is
    generic (
        g_CLK_DIV : integer := 8000000
    );
    port (
        reset    : in  std_logic;
        clk      : in  std_logic;
        switches : in  std_logic_vector(15 downto 0);
        btn_disp : in  std_logic;

        -- board output signals
        output_reg_out : out std_logic_vector(15 downto 0);
        cop1_out       : out std_logic_vector(15 downto 0);
        cop2_out       : out std_logic_vector(15 downto 0);
        flag_out       : out std_logic;

        -- Useful system status signals for simulation
        cop_busy_out : out std_logic;
        cop_done_out : out std_logic
    );
end processor_system;

architecture structural of processor_system is

    ---------------------------------------------------------------------------
    -- Signals from CPU to coprocessor
    ---------------------------------------------------------------------------
    signal sig_cop_start : std_logic;
    signal sig_cop_op    : std_logic_vector(1 downto 0);
    signal sig_cop_dst   : std_logic_vector(7 downto 0);
    signal sig_cop_srcB  : std_logic_vector(7 downto 0);
    signal sig_cop_srcC  : std_logic_vector(7 downto 0);
    signal sig_cop_size  : std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------------
    -- Signals from coprocessor to CPU
    ---------------------------------------------------------------------------
    signal sig_cop_busy : std_logic;
    signal sig_cop_done : std_logic;

    ---------------------------------------------------------------------------
    -- Shared DMEM interface
    ---------------------------------------------------------------------------
    signal sig_cop_addr_8  : std_logic_vector(7 downto 0);
    signal sig_cop_addr_10 : std_logic_vector(9 downto 0);
    signal sig_cop_wdata   : std_logic_vector(15 downto 0);
    signal sig_cop_we      : std_logic;
    signal sig_cop_rdata   : std_logic_vector(15 downto 0);

    ---------------------------------------------------------------------------
    -- Shared clock
    ---------------------------------------------------------------------------
    signal sig_cop_clk : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Address conversion
    --
    -- The coprocessor currently produces an 8-bit address, while the DMEM
    -- inside pipelined_core uses a 10-bit address.
    ---------------------------------------------------------------------------
    sig_cop_addr_10 <= "00" & sig_cop_addr_8;

    ---------------------------------------------------------------------------
    -- CPU and memory system
    ---------------------------------------------------------------------------
    cpu_inst : entity work.pipelined_core
        generic map (
            g_CLK_DIV => g_CLK_DIV
        )
        port map (
            reset    => reset,
            clk      => clk,
            switches => switches,

            output_reg_out => output_reg_out,
            cop1_out => cop1_out,
            cop2_out => cop2_out,
            flag_out => flag_out,

            cop_start => sig_cop_start,
            cop_op    => sig_cop_op,
            cop_dst   => sig_cop_dst,
            cop_srcB  => sig_cop_srcB,
            cop_srcC  => sig_cop_srcC,
            cop_size  => sig_cop_size,

            cop_done => sig_cop_done,
            cop_busy => sig_cop_busy,

            cop_addr_in      => sig_cop_addr_10,
            cop_write_data   => sig_cop_wdata,
            cop_write_enable => sig_cop_we,

            cop_read_data => sig_cop_rdata,
            cop_clk_out   => sig_cop_clk
        );

    ---------------------------------------------------------------------------
    -- Vector coprocessor
    ---------------------------------------------------------------------------
    cop_inst : entity work.coprocessor
        generic map (
            G_ADDR_W   => 8,
            G_DATA_W   => 16,
            G_ELEM_W   => 8,
            G_CLIP_MAX => 100
        )
        port map (
            clk   => sig_cop_clk,
            reset => reset,

            cop_start => sig_cop_start,
            cop_op    => sig_cop_op,
            cop_dst   => sig_cop_dst,
            cop_srcB  => sig_cop_srcB,
            cop_srcC  => sig_cop_srcC,
            cop_size  => sig_cop_size,

            cop_done => sig_cop_done,
            cop_busy => sig_cop_busy,

            dmem_addr  => sig_cop_addr_8,
            dmem_wdata => sig_cop_wdata,
            dmem_we    => sig_cop_we,
            dmem_rdata => sig_cop_rdata
        );

    ---------------------------------------------------------------------------
    -- Export status signals for the testbench
    ---------------------------------------------------------------------------
    cop_busy_out <= sig_cop_busy;
    cop_done_out <= sig_cop_done;

end structural;
