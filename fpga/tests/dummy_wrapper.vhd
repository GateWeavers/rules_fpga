library ieee;
use ieee.std_logic_1164.all;

entity {{WRAPPER_NAME}} is
    generic (
        WIDTH : integer := {{WIDTH}}
    );
    port (
        clk : in std_logic;
        rst : in std_logic
    );
end entity;

architecture rtl of {{WRAPPER_NAME}} is
    component {{OOC_SYNTH_NAME}} is
        port (
            clk : in std_logic;
            rst : in std_logic
        );
    end component;
begin
    u_ooc: {{OOC_SYNTH_NAME}}
        port map (
            clk => clk,
            rst => rst
        );
end architecture;
