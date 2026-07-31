library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_processor_system is
end tb_processor_system;

architecture simulation of tb_processor_system is

    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal switches : std_logic_vector(15 downto 0) := (others => '0');
    signal btn_disp : std_logic := '0';

    signal leds : std_logic_vector(15 downto 0);
    signal seg  : std_logic_vector(6 downto 0);
    signal an   : std_logic_vector(3 downto 0);

    signal cop_busy_out : std_logic;
    signal cop_done_out : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Unit under test
    ---------------------------------------------------------------------------
    uut : entity work.processor_system
        generic map (
            -- Use a small divider during simulation.
            -- The real FPGA value is much larger.
            g_CLK_DIV => 1
        )
        port map (
            clk          => clk,
            reset        => reset,
            switches     => switches,
            btn_disp     => btn_disp,
            leds         => leds,
            seg          => seg,
            an           => an,
            cop_busy_out => cop_busy_out,
            cop_done_out => cop_done_out
        );

    ---------------------------------------------------------------------------
    -- 100 MHz input clock
    ---------------------------------------------------------------------------
    clock_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;

            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    ---------------------------------------------------------------------------
    -- Test process
    ---------------------------------------------------------------------------
    stimulus_process : process
    begin
        -- Hold the system in reset.
        reset <= '1';
        switches <= (others => '0');
        btn_disp <= '0';

        wait for 50 ns;

        -- Release reset and allow the CPU to run.
        reset <= '0';

        wait for 2 us;

        -- Basic checks for the empty NOOP program.
        assert cop_busy_out = '0'
            report "Unexpected: coprocessor is busy during the NOOP program."
            severity error;

        assert cop_done_out = '0'
            report "Unexpected: coprocessor done is high during the NOOP program."
            severity error;

        report "Basic processor_system simulation completed."
            severity note;

        wait;
    end process;

end simulation;