library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ip_crc;

entity crc_top_wrapper is
    generic (
        G_AXIS_DATA_WIDTH  : integer range 8 to 8  := 8;                                  -- AXI Stream data path width
        G_CRC_WIDTH        : integer range 16 to 16 := 16;                                 -- CRC checksum width
        G_CRC_SEED         : std_logic_vector(15 downto 0) := x"FFFF";                     -- CRC initialization seed
        C_S_AXI_DATA_WIDTH : integer := 32;                                               -- AXI-Lite data width
        C_S_AXI_ADDR_WIDTH : integer := 7                                                 -- AXI-Lite address width
    );
    port (
        -- AXI Stream Data Input Interface
        s_axis_aclk_i   : in  std_logic;
        s_axis_tdata_i  : in  std_logic_vector(G_AXIS_DATA_WIDTH - 1 downto 0);
        s_axis_tvalid_i : in  std_logic;
        s_axis_tlast_i  : in  std_logic;
        s_axis_tready_o : out std_logic;

        -- AXI4-Lite Slave Interface
        s_axi_aclk_i    : in  std_logic;
        s_axi_aresetn_i : in  std_logic;
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
end entity crc_top_wrapper;

architecture rtl of crc_top_wrapper is

    -- Xilinx IP Interconnect Attributes for Block Design Integration
    attribute X_INTERFACE_INFO      : string;
    attribute X_INTERFACE_PARAMETER : string;

    attribute X_INTERFACE_INFO of s_axi_awaddr_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi AWADDR";
    attribute X_INTERFACE_INFO of s_axi_awprot_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi AWPROT";
    attribute X_INTERFACE_INFO of s_axi_awvalid_i : signal is "xilinx.com:interface:aximm:1.0 s_axi AWVALID";
    attribute X_INTERFACE_INFO of s_axi_awready_o : signal is "xilinx.com:interface:aximm:1.0 s_axi AWREADY";
    attribute X_INTERFACE_INFO of s_axi_wdata_i   : signal is "xilinx.com:interface:aximm:1.0 s_axi WDATA";
    attribute X_INTERFACE_INFO of s_axi_wstrb_i   : signal is "xilinx.com:interface:aximm:1.0 s_axi WSTRB";
    attribute X_INTERFACE_INFO of s_axi_wvalid_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi WVALID";
    attribute X_INTERFACE_INFO of s_axi_wready_o  : signal is "xilinx.com:interface:aximm:1.0 s_axi WREADY";
    attribute X_INTERFACE_INFO of s_axi_bresp_o   : signal is "xilinx.com:interface:aximm:1.0 s_axi BRESP";
    attribute X_INTERFACE_INFO of s_axi_bvalid_o  : signal is "xilinx.com:interface:aximm:1.0 s_axi BVALID";
    attribute X_INTERFACE_INFO of s_axi_bready_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi BREADY";
    attribute X_INTERFACE_INFO of s_axi_araddr_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi ARADDR";
    attribute X_INTERFACE_INFO of s_axi_arprot_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi ARPROT";
    attribute X_INTERFACE_INFO of s_axi_arvalid_i : signal is "xilinx.com:interface:aximm:1.0 s_axi ARVALID";
    attribute X_INTERFACE_INFO of s_axi_arready_o : signal is "xilinx.com:interface:aximm:1.0 s_axi ARREADY";
    attribute X_INTERFACE_INFO of s_axi_rdata_o   : signal is "xilinx.com:interface:aximm:1.0 s_axi RDATA";
    attribute X_INTERFACE_INFO of s_axi_rresp_o   : signal is "xilinx.com:interface:aximm:1.0 s_axi RRESP";
    attribute X_INTERFACE_INFO of s_axi_rvalid_o  : signal is "xilinx.com:interface:aximm:1.0 s_axi RVALID";
    attribute X_INTERFACE_INFO of s_axi_rready_i  : signal is "xilinx.com:interface:aximm:1.0 s_axi RREADY";

    attribute X_INTERFACE_PARAMETER of s_axi_awaddr_i : signal is
        "XIL_INTERFACENAME s_axi, DATA_WIDTH 32, PROTOCOL AXI4LITE, FREQ_HZ g_FREQ, " &
        "ID_WIDTH 0, ADDR_WIDTH 7, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, " &
        "RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, " &
        "HAS_LOCK 0, HAS_PROT 1, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 1, " &
        "HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 8, " &
        "NUM_WRITE_OUTSTANDING 8, MAX_BURST_LENGTH 1, PHASE 0.000, " &
        "CLK_DOMAIN Zynq_processing_system7_0_0_FCLK_CLK0, NUM_READ_THREADS 1, " &
        "NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0";

    -- Internal reset signal mapping active-low AXI reset to active-high IP reset
    signal s_reset : std_logic;

begin

  s_reset <= not(S_AXI_ARESETN);

  crc_top_inst : entity ip_crc.crc_top
    generic map(
      G_AXIS_DATA_WIDTH  => G_AXIS_DATA_WIDTH,
      G_CRC_WIDTH        => G_CRC_WIDTH,
      G_CRC_SEED         => G_CRC_SEED,
      C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
    )
    port map
    (
      clk_i => S_AXI_ACLK,
      rst_i => s_reset,
      -- AXI Stream mapping
      s_axis_tdata_i  => S_AXIS_TDATA,
      s_axis_tvalid_i => S_AXIS_TVALID,
      s_axis_tlast_i  => S_AXIS_TLAST,
      s_axis_tready_o => S_AXIS_TREADY,
      -- AXI4-Lite mapping
      s_axi_awaddr_i  => S_AXI_AWADDR,
      s_axi_awprot_i  => S_AXI_AWPROT,
      s_axi_awvalid_i => S_AXI_AWVALID,
      s_axi_awready_o => S_AXI_AWREADY,
      s_axi_wdata_i   => S_AXI_WDATA,
      s_axi_wstrb_i   => S_AXI_WSTRB,
      s_axi_wvalid_i  => S_AXI_WVALID,
      s_axi_wready_o  => S_AXI_WREADY,
      s_axi_bresp_o   => S_AXI_BRESP,
      s_axi_bvalid_o  => S_AXI_BVALID,
      s_axi_bready_i  => S_AXI_BREADY,
      s_axi_araddr_i  => S_AXI_ARADDR,
      s_axi_arprot_i  => S_AXI_ARPROT,
      s_axi_arvalid_i => S_AXI_ARVALID,
      s_axi_arready_o => S_AXI_ARREADY,
      s_axi_rdata_o   => S_AXI_RDATA,
      s_axi_rresp_o   => S_AXI_RRESP,
      s_axi_rvalid_o  => S_AXI_RVALID,
      s_axi_rready_i  => S_AXI_RREADY
    );

end architecture;
