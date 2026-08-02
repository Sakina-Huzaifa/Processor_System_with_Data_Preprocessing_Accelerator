library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity board_wrapper is
    generic (
        g_CLK_DIV : integer := 8000000
    );
    port (
        clk  : in  std_logic;
        btnC : in  std_logic;
        btnU : in  std_logic;
        switches   : in  std_logic_vector(15 downto 0);

        leds  : out std_logic_vector(15 downto 0);
        seg  : out std_logic_vector(6 downto 0);
        an   : out std_logic_vector(3 downto 0)
    );
end board_wrapper;

architecture Behavioral of board_wrapper is

    component debounce is
        port(
            clk     : in  std_logic;
            btn_in  : in  std_logic;
            btn_out : out std_logic
        );
    end component;

    component processor_system is
        generic (
            g_CLK_DIV : integer := 8000000
        );
        port (
            reset    : in  std_logic;
            clk      : in  std_logic;
            switches : in  std_logic_vector(15 downto 0);
            btn_disp : in  std_logic;

            output_reg_out : out std_logic_vector(15 downto 0);
            cop1_out       : out std_logic_vector(15 downto 0);
            cop2_out       : out std_logic_vector(15 downto 0);
            flag_out       : out std_logic;

            cop_busy_out : out std_logic;
            cop_done_out : out std_logic
        );
    end component;

    signal reset_db      : std_logic;
    signal btn_disp_db   : std_logic;

    signal output_reg_out : std_logic_vector(15 downto 0);
    signal cop1_out       : std_logic_vector(15 downto 0);
    signal cop2_out       : std_logic_vector(15 downto 0);
    signal flag_out       : std_logic;

    signal cop_busy_dummy : std_logic;
    signal cop_done_dummy : std_logic;

    signal sig_refresh_counter : std_logic_vector(16 downto 0) := (others => '0');
    signal sig_digit_select    : std_logic_vector(1 downto 0);
    signal sig_digit_value     : std_logic_vector(3 downto 0);
    signal sig_display_value   : std_logic_vector(15 downto 0);

begin

    --------------------------------------------------------------------
    -- Button debouncing
    --------------------------------------------------------------------
    db_reset : debounce
        port map(
            clk     => clk,
            btn_in  => btnC,
            btn_out => reset_db
        );

    db_disp : debounce
        port map(
            clk     => clk,
            btn_in  => btnU,
            btn_out => btn_disp_db
        );

    --------------------------------------------------------------------
    -- Processor system
    --------------------------------------------------------------------
    processor : processor_system
        generic map(
            g_CLK_DIV => g_CLK_DIV
        )
        port map(
            reset          => reset_db,
            clk            => clk,
            switches       => switches,
            btn_disp       => btn_disp_db,

            output_reg_out => output_reg_out,
            cop1_out       => cop1_out,
            cop2_out       => cop2_out,
            flag_out       => flag_out,

            cop_busy_out   => cop_busy_dummy,
            cop_done_out   => cop_done_dummy
        );

    --------------------------------------------------------------------
    -- LEDs
    --------------------------------------------------------------------
    leds(15) <= flag_out;
    leds(14 downto 0) <= output_reg_out(14 downto 0);

    --------------------------------------------------------------------
    -- 7-segment refresh
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            sig_refresh_counter <= sig_refresh_counter + 1;
        end if;
    end process;

    sig_digit_select <= sig_refresh_counter(16 downto 15);

    sig_display_value <= output_reg_out
                         when btn_disp_db = '0'
                         else cop1_out(7 downto 0) & cop2_out(7 downto 0);

    with sig_digit_select select
        sig_digit_value <=
            sig_display_value(3 downto 0)   when "00",
            sig_display_value(7 downto 4)   when "01",
            sig_display_value(11 downto 8)  when "10",
            sig_display_value(15 downto 12) when others;

    with sig_digit_select select
        an <=
            "1110" when "00",
            "1101" when "01",
            "1011" when "10",
            "0111" when others;

    with sig_digit_value select
        seg <=
            "1000000" when "0000",
            "1111001" when "0001",
            "0100100" when "0010",
            "0110000" when "0011",
            "0011001" when "0100",
            "0010010" when "0101",
            "0000010" when "0110",
            "1111000" when "0111",
            "0000000" when "1000",
            "0010000" when "1001",
            "0001000" when "1010",
            "0000011" when "1011",
            "1000110" when "1100",
            "0100001" when "1101",
            "0000110" when "1110",
            "0001110" when others;

end Behavioral;