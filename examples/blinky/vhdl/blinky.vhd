library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000
    );
    port (
        clk  : in  std_logic;
        led  : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of blinky is
    constant MAX_COUNT : integer := CLK_FREQ_HZ / 2;
    signal counter : integer range 0 to MAX_COUNT := 0;
    signal led_state : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if counter = MAX_COUNT then
                counter <= 0;
                led_state <= not led_state;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;

    led <= (others => led_state);
end architecture;
