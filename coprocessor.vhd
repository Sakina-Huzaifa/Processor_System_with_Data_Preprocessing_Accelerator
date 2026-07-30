---------------------------------------------------------------------------
-- coprocessor.vhd
-- vector coprocessor (VADD / VSCALE / VCLIP)
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity coprocessor is
    generic (
        G_ADDR_W   : integer := 8;    -- DMEM address width ( dst/srcB/srcC/size width)
        G_DATA_W   : integer := 16;   -- DMEM data bus width
        G_ELEM_W   : integer := 8;    -- vector element width
        G_CLIP_MAX : integer := 100  
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;

        -- CPU interface
        cop_start  : in  std_logic;
        cop_op     : in  std_logic_vector(1 downto 0);
        cop_dst    : in  std_logic_vector(G_ADDR_W-1 downto 0);
        cop_srcB   : in  std_logic_vector(G_ADDR_W-1 downto 0);
        cop_srcC   : in  std_logic_vector(G_ADDR_W-1 downto 0);
        cop_size   : in  std_logic_vector(G_ADDR_W-1 downto 0);
        cop_done   : out std_logic;
        cop_busy   : out std_logic;

        -- DMEM interface
        dmem_addr  : out std_logic_vector(G_ADDR_W-1 downto 0);
        dmem_wdata : out std_logic_vector(G_DATA_W-1 downto 0);
        dmem_we    : out std_logic;
        dmem_rdata : in  std_logic_vector(G_DATA_W-1 downto 0)
    );
end coprocessor;


architecture behavioral of coprocessor is

    -- State 
    type state_type is (ST_IDLE, ST_RD_B, ST_RD_C, ST_COMPUTE, ST_WR, ST_DONE);
    signal current_state : state_type;

    -- Operation codes 
    constant OP_VADD   : std_logic_vector(1 downto 0) := "00";
    constant OP_VSCALE : std_logic_vector(1 downto 0) := "01";
    constant OP_VCLIP  : std_logic_vector(1 downto 0) := "10";

    -- constant
    constant CLIP_MAX_V : std_logic_vector(G_ELEM_W-1 downto 0)
                          := conv_std_logic_vector(G_CLIP_MAX, G_ELEM_W);  --  CLIP_MAX_V = (std_logic_vector) 100
    constant SAT_MAX_V  : std_logic_vector(G_ELEM_W-1 downto 0)
                          := (others => '1');
    constant ADDR_ZERO  : std_logic_vector(G_ADDR_W-1 downto 0)
                          := (others => '0');

    -- Registers
    signal reg_op   : std_logic_vector(1 downto 0)        := (others => '0');
    signal reg_dst  : std_logic_vector(G_ADDR_W-1 downto 0) := (others => '0');
    signal reg_srcB : std_logic_vector(G_ADDR_W-1 downto 0) := (others => '0');
    signal reg_srcC : std_logic_vector(G_ADDR_W-1 downto 0) := (others => '0');
    signal reg_size : std_logic_vector(G_ADDR_W-1 downto 0) := (others => '0');

    -- element index 
    signal reg_i    : std_logic_vector(G_ADDR_W-1 downto 0) := (others => '0');

    -- Registers
    --  B[i],C[i]
    signal reg_b      : std_logic_vector(G_ELEM_W-1 downto 0) := (others => '0');
    signal reg_c      : std_logic_vector(G_ELEM_W-1 downto 0) := (others => '0');
    -- The result calculated
    signal reg_result : std_logic_vector(G_ELEM_W-1 downto 0) := (others => '0');


    signal sig_k    : std_logic_vector(G_ELEM_W-1 downto 0);
    signal sig_sum  : std_logic_vector(G_ELEM_W downto 0);      -- 1 extra carry bit
    signal sig_prod : std_logic_vector(2*G_ELEM_W-1 downto 0); 

    signal sig_done : std_logic := '0';  -- internal done signal(can be read)

    -- N-bit register with enable 
    component reg_en is
        generic ( N : integer := 8 );
        port ( D     : in  std_logic_vector(N-1 downto 0);
               E     : in  std_logic;
               reset : in  std_logic;
               clk   : in  std_logic;
               Q     : out std_logic_vector(N-1 downto 0) );
    end component;

    -- Control signals
    signal LD_PARAM : std_logic;                     -- load op/dst/srcB/srcC/size
    signal LD_I     : std_logic;                     -- load element index
    signal SEL_I    : std_logic;                     -- 0: i<=0, 1: i<=i+1
    signal LD_B     : std_logic;
    signal LD_C     : std_logic;
    signal LD_RES   : std_logic;
    signal LD_DONE  : std_logic;                     -- load done flag
    signal SEL_DONE : std_logic;                     -- 0: clear, 1: set
    signal SEL_ADDR : std_logic_vector(1 downto 0);  -- 00:srcB, 01:srcC, 10:dst, 11: no DMEM access

    -- Datapath signals
    signal sig_i_plus1   : std_logic_vector(G_ADDR_W-1 downto 0); --- reg_i + 1
    signal reg_i_in      : std_logic_vector(G_ADDR_W-1 downto 0);
    signal sig_addr_srcB : std_logic_vector(G_ADDR_W-1 downto 0);
    signal sig_addr_srcC : std_logic_vector(G_ADDR_W-1 downto 0);
    signal sig_addr_dst  : std_logic_vector(G_ADDR_W-1 downto 0);
    signal dmem_elem     : std_logic_vector(G_ELEM_W-1 downto 0);
    signal sig_add_sat   : std_logic_vector(G_ELEM_W-1 downto 0); -- The saturation result
    signal sig_mul_sat   : std_logic_vector(G_ELEM_W-1 downto 0);
    signal sig_clip      : std_logic_vector(G_ELEM_W-1 downto 0);
    signal sig_alu_out   : std_logic_vector(G_ELEM_W-1 downto 0);
    signal sig_done_in   : std_logic_vector(0 downto 0);
    signal sig_done_q    : std_logic_vector(0 downto 0);

begin

    FSM_transitions : process ( clk, reset )
    begin
        if (reset = '1') then
            current_state <= ST_IDLE;
        elsif (clk'event and clk = '1') then
            case current_state is

                when ST_IDLE =>
                    if (cop_start = '1') then
                        if (cop_size = 0) then           -- empty vector
                            current_state <= ST_DONE;
                        else
                            current_state <= ST_RD_B;
                        end if;
                    else
                        current_state <= ST_IDLE;
                    end if;

                when ST_RD_B =>
                    -- single-port DMEM: the second source needs its own cycle
                    if (reg_op = OP_VADD) then
                        current_state <= ST_RD_C;
                    else
                        current_state <= ST_COMPUTE;
                    end if;

                when ST_RD_C =>
                    current_state <= ST_COMPUTE;

                when ST_COMPUTE =>
                    current_state <= ST_WR;

                when ST_WR =>
                    if ((reg_i + 1) = reg_size) then
                        current_state <= ST_DONE;
                    else
                        current_state <= ST_RD_B;
                    end if;

                when ST_DONE =>
                    current_state <= ST_IDLE;

            end case;
        end if;
    end process;


    FSM_outputs : process ( current_state, cop_start )
    begin
        LD_PARAM <= '0';
        LD_I     <= '0';
        SEL_I    <= '0';
        LD_B     <= '0';
        LD_C     <= '0';
        LD_RES   <= '0';
        LD_DONE  <= '0';
        SEL_DONE <= '0';
        SEL_ADDR <= "11";   -- no DMEM access
        dmem_we  <= '0';
        cop_busy <= '0';

        case current_state is

            when ST_IDLE =>
                if (cop_start = '1') then
                    LD_PARAM <= '1';           -- latch operands
                    LD_I     <= '1';
                    SEL_I    <= '0';           -- i <= 0
                    LD_DONE  <= '1';
                    SEL_DONE <= '0';           -- done <= 0
                end if;

            when ST_RD_B =>
                cop_busy <= '1';
                SEL_ADDR <= "00";              -- srcB + i
                LD_B     <= '1';

            when ST_RD_C =>
                cop_busy <= '1';
                SEL_ADDR <= "01";              -- srcC + i
                LD_C     <= '1';

            when ST_COMPUTE =>
                cop_busy <= '1';
                LD_RES   <= '1';              -- save the ALU output into reg_result

            when ST_WR =>
                cop_busy <= '1';
                SEL_ADDR <= "10";              -- dst + i
                dmem_we  <= '1';               -- enable write
                LD_I     <= '1';
                SEL_I    <= '1';               -- i <= i + 1

            when ST_DONE =>
                cop_busy <= '0';
                LD_DONE  <= '1';
                SEL_DONE <= '1';               -- done <= 1, then held

        end case;
    end process;

    ---------------------------------------------------------------------
    -- Datapath 
    ---------------------------------------------------------------------
    -- parameter registers
    OPreg : reg_en
        generic map ( N => 2 ) port map (
            D => cop_op,   E => LD_PARAM, reset => reset, clk => clk, Q => reg_op );

    DSTreg : reg_en
        generic map ( N => G_ADDR_W ) port map (
            D => cop_dst,  E => LD_PARAM, reset => reset, clk => clk, Q => reg_dst );

    SRCBreg : reg_en
        generic map ( N => G_ADDR_W ) port map (
            D => cop_srcB, E => LD_PARAM, reset => reset, clk => clk, Q => reg_srcB );

    SRCCreg : reg_en
        generic map ( N => G_ADDR_W ) port map (
            D => cop_srcC, E => LD_PARAM, reset => reset, clk => clk, Q => reg_srcC );

    SIZEreg : reg_en
        generic map ( N => G_ADDR_W ) port map (
            D => cop_size, E => LD_PARAM, reset => reset, clk => clk, Q => reg_size );

    -- element index counter
    Incr_i : sig_i_plus1 <= reg_i + 1;
    MUX_i  : reg_i_in    <= ADDR_ZERO when SEL_I = '0' else sig_i_plus1;

    Ireg : reg_en
        generic map ( N => G_ADDR_W ) port map (
            D => reg_i_in, E => LD_I, reset => reset, clk => clk, Q => reg_i );

    -- address generation
    Add_srcB : sig_addr_srcB <= reg_srcB + reg_i;
    Add_srcC : sig_addr_srcC <= reg_srcC + reg_i;
    Add_dst  : sig_addr_dst  <= reg_dst  + reg_i;

    MUX_addr : dmem_addr <= sig_addr_srcB when SEL_ADDR = "00" else
                            sig_addr_srcC when SEL_ADDR = "01" else
                            sig_addr_dst  when SEL_ADDR = "10" else
                            ADDR_ZERO;

    -- operand registers (take the lower 8 bits)
    dmem_elem <= dmem_rdata(G_ELEM_W-1 downto 0);     

    Breg : reg_en
        generic map ( N => G_ELEM_W ) port map (
            D => dmem_elem, E => LD_B, reset => reset, clk => clk, Q => reg_b );

    Creg : reg_en
        generic map ( N => G_ELEM_W ) port map (
            D => dmem_elem, E => LD_C, reset => reset, clk => clk, Q => reg_c );

    -- vector ALU
    -- k use the lower 8 bits
    sig_k <= reg_srcC(G_ELEM_W-1 downto 0);

    Adder_bc : sig_sum  <= ('0' & reg_b) + ('0' & reg_c);
    Mult_bk  : sig_prod <= reg_b * sig_k;

    SAT_add  : sig_add_sat <= SAT_MAX_V when sig_sum(G_ELEM_W) = '1'
                              else sig_sum(G_ELEM_W-1 downto 0);

    SAT_mult : sig_mul_sat <= SAT_MAX_V
                              when sig_prod(2*G_ELEM_W-1 downto G_ELEM_W) /= 0
                              else sig_prod(G_ELEM_W-1 downto 0);

    Clipper  : sig_clip    <= CLIP_MAX_V when reg_b > CLIP_MAX_V else reg_b;

    MUX_alu  : sig_alu_out <= sig_add_sat when reg_op = OP_VADD   else
                              sig_mul_sat when reg_op = OP_VSCALE else
                              sig_clip;

    RESreg : reg_en
        generic map ( N => G_ELEM_W ) port map (
            D => sig_alu_out, E => LD_RES, reset => reset, clk => clk, Q => reg_result );


    -- done register (level, held for CPU polling)
    MUX_done : sig_done_in <= "1" when SEL_DONE = '1' else "0";

    DONEreg : reg_en
        generic map ( N => 1 ) port map (
            D => sig_done_in, E => LD_DONE, reset => reset, clk => clk, Q => sig_done_q );

    sig_done <= sig_done_q(0);

    -- Outputs
    dmem_wdata <= EXT(reg_result, G_DATA_W);          -- zero-extend to bus width
    cop_done   <= sig_done;

end behavioral;


---------------------------------------------------------------------------
-- N-bit register with enable and asynchronous active-high reset
---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity reg_en is
    generic ( N : integer := 8 );
    port ( D     : in  std_logic_vector(N-1 downto 0);
           E     : in  std_logic;
           reset : in  std_logic;
           clk   : in  std_logic;
           Q     : out std_logic_vector(N-1 downto 0) );
end reg_en;

architecture behavioral of reg_en is
begin
    process ( clk, reset )
    begin
        if (reset = '1') then
            Q <= (others => '0');
        elsif (clk'event and clk = '1') then
            if (E = '1') then
                Q <= D;
            end if;
        end if;
    end process;
end behavioral;