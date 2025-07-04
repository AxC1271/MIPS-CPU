library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic(
        BAUD_X16_CLK_TICKS: integer := 54);
    port(
        clk       : in  std_logic;
        rst       : in  std_logic;
        rx        : in  std_logic;
        shift_reg : out std_logic_vector (7 downto 0);
        mem_wr    : out STD_LOGIC
        );
end uart_rx;

architecture Behavioral of uart_rx is
    type rx_states_t is (IDLE, START, DATA, STOP);
    signal rx_state: rx_states_t := IDLE;

    signal baud_rate_x16_clk  : std_logic := '0';
    signal rx_stored_data     : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- we want to sample faster than the normal baud clk rate
    -- to ensure that we pull a correct logic 'low' on the start bit
    -- and not some ambient noise
    baud_rate_x16_clk_generator: process(clk)
        variable baud_x16_count: integer range 0 to (BAUD_X16_CLK_TICKS - 1) := (BAUD_X16_CLK_TICKS - 1);
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                baud_rate_x16_clk <= '0';
                baud_x16_count := (BAUD_X16_CLK_TICKS - 1);
            else
                if (baud_x16_count = 0) then
                    baud_rate_x16_clk <= '1';
                    baud_x16_count := (BAUD_X16_CLK_TICKS - 1);
                else
                    baud_rate_x16_clk <= '0';
                    baud_x16_count := baud_x16_count - 1;
                end if;
            end if;
        end if;
    end process baud_rate_x16_clk_generator;


-- The UART_rx_FSM process represents a Finite State Machine which has
-- four states (IDLE, START, DATA, STOP). See inline comments for more details.

    UART_rx_FSM: process(clk)
        variable bit_duration_count : integer range 0 to 15 := 0;
        variable bit_count          : integer range 0 to 7  := 0;
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                rx_state <= IDLE;
                rx_stored_data <= (others => '0');
                shift_reg <= (others => '0');
                bit_duration_count := 0;
                bit_count := 0;
            else
                if (baud_rate_x16_clk = '1') then     -- the FSM works 16 times faster the baud rate frequency
                    case rx_state is
                        when IDLE =>
                            rx_stored_data <= (others => '0');    -- clean the received data register
                            bit_duration_count := 0;              -- reset counters
                            bit_count := 0;
                            if (rx = '0') then             -- if the start bit received
                                rx_state <= START;         -- transit to the START state
                            end if;
                        when START =>
                            if (rx = '0') then             -- verify that the start is preset
                                if (bit_duration_count = 7) then   -- wait a half of the baud rate cycle
                                    rx_state <= DATA;              -- (it puts the capture point at the middle of duration of the receiving bit)
                                    bit_duration_count := 0;
                                else
                                    bit_duration_count := bit_duration_count + 1;
                                end if;
                            else
                                rx_state <= IDLE;                  -- the start bit is not preset (false alarm)
                            end if;
                        when DATA =>
                            if (bit_duration_count = 15) then   -- wait for "one" baud rate cycle (not strictly one, about one)
                                shift_reg(bit_count) <= rx;     -- fill in the receiving register one received bit.
                                bit_duration_count := 0;
                                if (bit_count = 7) then         -- when all 8 bit received, go to the STOP state
                                    rx_state <= STOP;
                                    bit_duration_count := 0;
                                else
                                    bit_count := bit_count + 1;
                                end if;
                            else
                                bit_duration_count := bit_duration_count + 1;
                            end if;
                        when STOP =>
                            if (bit_duration_count = 15) then      -- wait for "one" baud rate cycle
                                rx_data_out <= rx_stored_data;     -- transfer the received data to the outside world
                                mem_wr <= '1';
                                rx_state <= IDLE;
                            else
                                bit_duration_count := bit_duration_count + 1;
                            end if;
                        when others =>
                            rx_state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process UART_rx_FSM;

end Behavioral;
