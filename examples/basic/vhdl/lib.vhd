library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dummy is
    port (
        clk : in bit;
        q   : out bit
    );
end entity;

architecture rtl of dummy is
begin
    q <= clk;
end architecture;
