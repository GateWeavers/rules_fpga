
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crc_top is
    generic (
        G_AXIS_DATA_WIDTH  : integer range 8 to 8  := 8;                -- AXI Stream data path width
        G_CRC_WIDTH        : integer range 16 to 16 := 16;              -- CRC checksum width
        G_CRC_SEED         : std_logic_vector(15 downto 0) := x"FFFF";  -- CRC initialization seed
        C_S_AXI_DATA_WIDTH : integer := 32;                             -- AXI-Lite data width
        C_S_AXI_ADDR_WIDTH : integer := 7                               -- AXI-Lite address width
    );
    port (
        -- System Clock and Reset
        clk_i           : in  std_logic;
        rst_i           : in  std_logic;

        -- AXI Stream Data Input Interface (s_axis_<name>_i/o)
        s_axis_tdata_i  : in  std_logic_vector(G_AXIS_DATA_WIDTH - 1 downto 0);
        s_axis_tvalid_i : in  std_logic;
        s_axis_tlast_i  : in  std_logic;
        s_axis_tready_o : out std_logic;

        -- AXI4-Lite Slave Interface (s_axi_<name>_i/o)
        s_axi_awaddr_i  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        s_axi_awprot_i  : in  std_logic_vector(2 downto 0);
        s_axi_awvalid_i : in  std_logic;
        s_axi_awready_o : out std_logic;
        s_axi_wdata_i   : in  std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
        s_axi_wstrb_i   : in  std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
        s_axi_wvalid_i  : in  std_logic;
        s_axi_wready_o  : out std_logic;
        s_axi_bresp_o   : out std_logic_vector(1 downto 0);
        s_axi_bvalid_o  : out std_logic;
        s_axi_bready_i  : in  std_logic;
        s_axi_araddr_i  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        s_axi_arprot_i  : in  std_logic_vector(2 downto 0);
        s_axi_arvalid_i : in  std_logic;
        s_axi_arready_o : out std_logic;
        s_axi_rdata_o   : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
        s_axi_rresp_o   : out std_logic_vector(1 downto 0);
        s_axi_rvalid_o  : out std_logic;
        s_axi_rready_i  : in  std_logic
    );
end entity crc_top;

architecture rtl of crc_top is
begin
    -- dummy implementation
    s_axis_tready_o <= '1';
    s_axi_awready_o <= '1';
    s_axi_wready_o  <= '1';
    s_axi_bresp_o   <= (others => '0');
    s_axi_bvalid_o  <= s_axi_wvalid_i and s_axi_awvalid_i;
    s_axi_arready_o <= '1';
    s_axi_rdata_o   <= (others => '0');
    s_axi_rresp_o   <= (others => '0');
    s_axi_rvalid_o  <= s_axi_arvalid_i;

end architecture rtl;