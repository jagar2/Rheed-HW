--------------------------------------------------------------------------------
-- Project: CustomLogic
--------------------------------------------------------------------------------
--  Module: CustomLogic
--    File: CustomLogic.vhd
--    Date: 2023-03-07
--     Rev: 0.5
--  Author: PP
--------------------------------------------------------------------------------
-- CustomLogic wrapper for the user design
--------------------------------------------------------------------------------
-- 0.1, 2017-12-15, PP, Initial release
-- 0.2, 2019-07-12, PP, Updated CustomLogic interfaces
-- 0.3, 2019-10-24, PP, Added General Purpose I/O Interface
-- 0.4, 2021-02-25, PP, Added *mem_base and *mem_size ports into the On-Board
--                      Memory interface
-- 0.5, 2023-03-07, MH, Added CustomLogic output control
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CustomLogic is
    generic (
        STREAM_DATA_WIDTH : natural := 128;
        MEMORY_DATA_WIDTH : natural := 128
    );
    port (
        ---- CustomLogic Common Interfaces -------------------------------------
        -- Clock/Reset
        clk250                   : in  std_logic; -- Clock 250 MHz
        srst250                  : in  std_logic; -- Global reset (PCIe reset)
        -- General Purpose I/O Interface
        user_output_ctrl         : out std_logic_vector(15 downto 0);
        user_output_status       : in  std_logic_vector(7 downto 0);
        standard_io_set1_status  : in  std_logic_vector(9 downto 0);
        standard_io_set2_status  : in  std_logic_vector(9 downto 0);
        module_io_set_status     : in  std_logic_vector(39 downto 0);
        qdc1_position_status     : in  std_logic_vector(31 downto 0);
        custom_logic_output_ctrl : out std_logic_vector(31 downto 0);
        reserved                 : in  std_logic_vector(511 downto 0) := (others => '0');
        -- Control Slave Interface
        s_ctrl_addr              : in  std_logic_vector(15 downto 0);
        s_ctrl_data_wr_en        : in  std_logic;
        s_ctrl_data_wr           : in  std_logic_vector(31 downto 0);
        s_ctrl_data_rd           : out std_logic_vector(31 downto 0);
        -- On-Board Memory - Parameters
        onboard_mem_base         : in  std_logic_vector(31 downto 0); -- Base address of the CustomLogic partition in the On-Board Memory
        onboard_mem_size         : in  std_logic_vector(31 downto 0); -- Size in bytes of the CustomLogic partition in the On-Board Memory
        -- On-Board Memory - AXI 4 Master Interface
        m_axi_resetn             : in  std_logic; -- AXI 4 Interface reset
        m_axi_awaddr             : out std_logic_vector(31 downto 0);
        m_axi_awlen              : out std_logic_vector(7 downto 0);
        m_axi_awsize             : out std_logic_vector(2 downto 0);
        m_axi_awburst            : out std_logic_vector(1 downto 0);
        m_axi_awlock             : out std_logic;
        m_axi_awcache            : out std_logic_vector(3 downto 0);
        m_axi_awprot             : out std_logic_vector(2 downto 0);
        m_axi_awqos              : out std_logic_vector(3 downto 0);
        m_axi_awvalid            : out std_logic;
        m_axi_awready            : in  std_logic;
        m_axi_wdata              : out std_logic_vector(MEMORY_DATA_WIDTH - 1 downto 0);
        m_axi_wstrb              : out std_logic_vector(MEMORY_DATA_WIDTH / 8 - 1 downto 0);
        m_axi_wlast              : out std_logic;
        m_axi_wvalid             : out std_logic;
        m_axi_wready             : in  std_logic;
        m_axi_bresp              : in  std_logic_vector(1 downto 0);
        m_axi_bvalid             : in  std_logic;
        m_axi_bready             : out std_logic;
        m_axi_araddr             : out std_logic_vector(31 downto 0);
        m_axi_arlen              : out std_logic_vector(7 downto 0);
        m_axi_arsize             : out std_logic_vector(2 downto 0);
        m_axi_arburst            : out std_logic_vector(1 downto 0);
        m_axi_arlock             : out std_logic;
        m_axi_arcache            : out std_logic_vector(3 downto 0);
        m_axi_arprot             : out std_logic_vector(2 downto 0);
        m_axi_arqos              : out std_logic_vector(3 downto 0);
        m_axi_arvalid            : out std_logic;
        m_axi_arready            : in  std_logic;
        m_axi_rdata              : in  std_logic_vector(MEMORY_DATA_WIDTH - 1 downto 0);
        m_axi_rresp              : in  std_logic_vector(1 downto 0);
        m_axi_rlast              : in  std_logic;
        m_axi_rvalid             : in  std_logic;
        m_axi_rready             : out std_logic;
        ---- CustomLogic Device/Channel Interfaces -----------------------------
        -- AXI Stream Slave Interface
        s_axis_resetn            : in  std_logic; -- AXI Stream Interface reset
        s_axis_tvalid            : in  std_logic;
        s_axis_tready            : out std_logic;
        s_axis_tdata             : in  std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0);
        s_axis_tuser             : in  std_logic_vector(3 downto 0);
        -- Metadata Slave Interface
        s_mdata_StreamId         : in  std_logic_vector(7 downto 0);
        s_mdata_SourceTag        : in  std_logic_vector(15 downto 0);
        s_mdata_Xsize            : in  std_logic_vector(23 downto 0);
        s_mdata_Xoffs            : in  std_logic_vector(23 downto 0);
        s_mdata_Ysize            : in  std_logic_vector(23 downto 0);
        s_mdata_Yoffs            : in  std_logic_vector(23 downto 0);
        s_mdata_DsizeL           : in  std_logic_vector(23 downto 0);
        s_mdata_PixelF           : in  std_logic_vector(15 downto 0);
        s_mdata_TapG             : in  std_logic_vector(15 downto 0);
        s_mdata_Flags            : in  std_logic_vector(7 downto 0);
        s_mdata_Timestamp        : in  std_logic_vector(31 downto 0);
        s_mdata_PixProcFlgs      : in  std_logic_vector(7 downto 0);
        s_mdata_Status           : in  std_logic_vector(31 downto 0);
        -- AXI Stream Master Interface
        m_axis_tvalid            : out std_logic;
        m_axis_tready            : in  std_logic;
        m_axis_tdata             : out std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0);
        m_axis_tuser             : out std_logic_vector(3 downto 0);
        -- Metadata Master Interface
        m_mdata_StreamId         : out std_logic_vector(7 downto 0);
        m_mdata_SourceTag        : out std_logic_vector(15 downto 0);
        m_mdata_Xsize            : out std_logic_vector(23 downto 0);
        m_mdata_Xoffs            : out std_logic_vector(23 downto 0);
        m_mdata_Ysize            : out std_logic_vector(23 downto 0);
        m_mdata_Yoffs            : out std_logic_vector(23 downto 0);
        m_mdata_DsizeL           : out std_logic_vector(23 downto 0);
        m_mdata_PixelF           : out std_logic_vector(15 downto 0);
        m_mdata_TapG             : out std_logic_vector(15 downto 0);
        m_mdata_Flags            : out std_logic_vector(7 downto 0);
        m_mdata_Timestamp        : out std_logic_vector(31 downto 0);
        m_mdata_PixProcFlgs      : out std_logic_vector(7 downto 0);
        m_mdata_Status           : out std_logic_vector(31 downto 0);
        -- Memento Master Interface
        m_memento_event          : out std_logic;
        m_memento_arg0           : out std_logic_vector(31 downto 0);
        m_memento_arg1           : out std_logic_vector(31 downto 0)
    );
end entity CustomLogic;

architecture behav of CustomLogic is
begin

    -- AXI Stream passthrough
    s_axis_tready <= m_axis_tready;
    m_axis_tvalid <= s_axis_tvalid;
    m_axis_tdata  <= s_axis_tdata;
    m_axis_tuser  <= s_axis_tuser;

    -- Metadata passthrough
    m_mdata_StreamId    <= s_mdata_StreamId;
    m_mdata_SourceTag   <= s_mdata_SourceTag;
    m_mdata_Xsize       <= s_mdata_Xsize;
    m_mdata_Xoffs       <= s_mdata_Xoffs;
    m_mdata_Ysize       <= s_mdata_Ysize;
    m_mdata_Yoffs       <= s_mdata_Yoffs;
    m_mdata_DsizeL      <= s_mdata_DsizeL;
    m_mdata_PixelF      <= s_mdata_PixelF;
    m_mdata_TapG        <= s_mdata_TapG;
    m_mdata_Flags       <= s_mdata_Flags;
    m_mdata_Timestamp   <= s_mdata_Timestamp;
    m_mdata_PixProcFlgs <= s_mdata_PixProcFlgs;
    m_mdata_Status      <= s_mdata_Status;

    -- Control register reads (no user registers)
    s_ctrl_data_rd <= (others => '0');

    -- GP I/O outputs (inactive)
    user_output_ctrl         <= (others => '0');
    custom_logic_output_ctrl <= (others => '0');

    -- AXI4 master (idle — no memory access)
    m_axi_awaddr  <= (others => '0');
    m_axi_awlen   <= (others => '0');
    m_axi_awsize  <= (others => '0');
    m_axi_awburst <= (others => '0');
    m_axi_awlock  <= '0';
    m_axi_awcache <= (others => '0');
    m_axi_awprot  <= (others => '0');
    m_axi_awqos   <= (others => '0');
    m_axi_awvalid <= '0';
    m_axi_wdata   <= (others => '0');
    m_axi_wstrb   <= (others => '0');
    m_axi_wlast   <= '0';
    m_axi_wvalid  <= '0';
    m_axi_bready  <= '1';
    m_axi_araddr  <= (others => '0');
    m_axi_arlen   <= (others => '0');
    m_axi_arsize  <= (others => '0');
    m_axi_arburst <= (others => '0');
    m_axi_arlock  <= '0';
    m_axi_arcache <= (others => '0');
    m_axi_arprot  <= (others => '0');
    m_axi_arqos   <= (others => '0');
    m_axi_arvalid <= '0';
    m_axi_rready  <= '0';

    -- Memento (inactive)
    m_memento_event <= '0';
    m_memento_arg0  <= (others => '0');
    m_memento_arg1  <= (others => '0');

end behav;
