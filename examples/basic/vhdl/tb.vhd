library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library lib;

entity tb is
end entity;

architecture sim of tb is
    signal clk : bit := '0';
    signal q   : bit;
begin
    dut: entity lib.dummy
        port map (
            clk => clk,
            q   => q
        );
    
    process
    begin
        clk <= '1';
        wait for 10 ns;
        clk <= '0';
        wait for 10 ns;
        assert false report "End of simulation" severity note;
        wait;
    end process;
end architecture;
