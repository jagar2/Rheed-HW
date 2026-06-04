--------------------------------------------------------------------------------
-- Project: CustomLogic
--------------------------------------------------------------------------------
--  Module: CustomLogic
--    File: CustomLogic.vhd
--    Date: 2025-XX-XX
--     Rev: 0.6
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
-- 0.6, 2025-XX-XX, --, FOLO capture/feed/collect/overlay pipeline:
--                      - live AXI-Stream passthrough is never stalled
--                      - whole 320x320 frames captured into ping-pong BRAM
--                      - frames fed to FOLO at 1 px/cycle, chained (no flush)
--                      - 1600x16b outputs packed into double-buffered result RAM
--                      - results spliced into the tail (bottom 10 rows) of a
--                        later passthrough frame
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity CustomLogic is
  generic (
    STREAM_DATA_WIDTH        :     natural                        := 128;
    MEMORY_DATA_WIDTH        :     natural                        := 128
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

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Image
  constant BITS_PER_PIXEL     : natural                                          := 8;
  constant WORDS_PER_STREAM   : natural                                          := STREAM_DATA_WIDTH / BITS_PER_PIXEL;            -- 16 pixels per 128b word
  constant PIXELS_PER_FRAME   : natural                                          := 320 * 320;                                     -- 102400
  constant WORDS_PER_FRAME    : natural                                          := PIXELS_PER_FRAME / WORDS_PER_STREAM;           -- 6400

  -- Sequentializer
  constant SEQ_CNT_WIDTH      : natural                                          := integer(ceil(log2(real(WORDS_PER_STREAM))));   -- 4

  -- FOLO
  constant FOLO_OUT_WIDTH     : natural                                          := 16;
  constant FOLO_OUTS_PER_WORD : natural                                          := STREAM_DATA_WIDTH / FOLO_OUT_WIDTH;            -- 8 outputs per 128b word
  constant FOLO_OUT_VALUES    : natural                                          := 40 * 40;                                       -- 1600 outputs per frame
  constant OVERLAY_WORDS      : natural                                          := FOLO_OUT_VALUES / FOLO_OUTS_PER_WORD;          -- 200 words per result
  constant OVERLAY_START      : natural                                          := WORDS_PER_FRAME - OVERLAY_WORDS;               -- 6200 (bottom 10 rows)

  -- Derived address widths
  constant FB_AWORD           : natural                                          := integer(ceil(log2(real(WORDS_PER_FRAME))));    -- 13
  constant RB_AWORD           : natural                                          := integer(ceil(log2(real(OVERLAY_WORDS))));      -- 8
  constant VAL_CNT_WIDTH      : natural                                          := integer(ceil(log2(real(FOLO_OUT_VALUES))));    -- 11
  constant SLOT_BITS          : natural                                          := integer(ceil(log2(real(FOLO_OUTS_PER_WORD)))); -- 3

  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------
  type frame_buf_t is array (0 to WORDS_PER_FRAME - 1) of std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0);
  type res_buf_t is array (0 to OVERLAY_WORDS - 1) of std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0);

  type cap_state_t is (C_IDLE, C_ARM, C_WRITE);
  type feed_state_t is (F_IDLE, F_WAIT, F_LOAD, F_RUN);

  ----------------------------------------------------------------------------
  -- Components
  ----------------------------------------------------------------------------
  component folo_0 is
    port (
      input_3_TDATA      : in  std_logic_vector(FOLO_OUT_WIDTH - 1 downto 0);
      layer16_out_TDATA  : out std_logic_vector(FOLO_OUT_WIDTH - 1 downto 0);
      ap_clk             : in  std_logic;
      ap_rst_n           : in  std_logic;
      input_3_TVALID     : in  std_logic;
      input_3_TREADY     : out std_logic;
      ap_start           : in  std_logic;
      layer16_out_TVALID : out std_logic;
      layer16_out_TREADY : in  std_logic;
      ap_done            : out std_logic;
      ap_ready           : out std_logic;
      ap_idle            : out std_logic
    );
  end component folo_0;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  -- Buffer manager (2-deep ping-pong frame FIFO)
  signal cap_ptr              : std_logic                                        := '0';                                           -- frame buffer capture writes next
  signal feed_ptr             : std_logic                                        := '0';                                           -- frame buffer feed reads next
  signal buf_full             : std_logic_vector(1 downto 0)                     := "00";                                          -- per-buffer "has a frame" flag
  signal cap_commit           : std_logic                                        := '0';                                           -- 1-cyc: capture committed buf cap_ptr
  signal feed_release         : std_logic                                        := '0';                                           -- 1-cyc: feed finished reading buf feed_ptr
  signal cap_buf_free         : std_logic;                                                                                         -- buf cap_ptr is empty
  signal feed_buf_rdy         : std_logic;                                                                                         -- buf feed_ptr is full

  -- Frame buffers (block RAM, ping-pong) + ports
  signal frame_buf0           : frame_buf_t;
  signal frame_buf1           : frame_buf_t;
  signal fb_wr_en             : std_logic                                        := '0';
  signal fb_wr_idx            : unsigned(FB_AWORD - 1 downto 0)                  := (others => '0');
  signal fb_wr_data           : std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal fb_rd_idx            : unsigned(FB_AWORD - 1 downto 0)                  := (others => '0');
  signal fb_rd_data           : std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- Capture engine
  signal cap_state            : cap_state_t                                      := C_IDLE;
  signal cap_word_cnt         : unsigned(FB_AWORD - 1 downto 0)                  := (others => '0');

  -- Feed engine
  signal feed_state           : feed_state_t                                     := F_IDLE;
  signal feed_word_idx        : unsigned(FB_AWORD - 1 downto 0)                  := (others => '0');
  signal feed_pix_cnt         : unsigned(SEQ_CNT_WIDTH - 1 downto 0)             := (others => '0');
  signal cur_word             : std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- FOLO handshake
  signal folo_in_tdata        : std_logic_vector(FOLO_OUT_WIDTH - 1 downto 0)    := (others => '0');
  signal folo_out_tdata       : std_logic_vector(FOLO_OUT_WIDTH - 1 downto 0)    := (others => '0');
  signal folo_in_tvalid       : std_logic                                        := '0';
  signal folo_out_tvalid      : std_logic                                        := '0';
  signal folo_in_tready       : std_logic                                        := '0';

  -- Collector + result buffers (distributed RAM, double-buffered)
  signal res_buf0             : res_buf_t;
  signal res_buf1             : res_buf_t;
  signal res_val_cnt          : unsigned(VAL_CNT_WIDTH - 1 downto 0)             := (others => '0');                               -- 0..1599 within group
  signal pack_word            : std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal res_wptr             : std_logic                                        := '0';                                           -- result buffer collector writes
  signal res_wr_en            : std_logic                                        := '0';
  signal res_wr_idx           : unsigned(RB_AWORD - 1 downto 0)                  := (others => '0');
  signal res_wr_data          : std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal res_ready_pulse      : std_logic                                        := '0';                                           -- 1-cyc: a 1600-value group completed
  signal res_ready_buf        : std_logic                                        := '0';                                           -- which result buffer just completed

  -- Overlay mux
  signal ovl_idx              : unsigned(FB_AWORD - 1 downto 0)                  := (others => '0');                               -- next output word index
  signal cur_idx              : unsigned(FB_AWORD - 1 downto 0);                                                                   -- word index on the bus now
  signal ovl_armed            : std_logic                                        := '0';                                           -- a result is available to splice
  signal ovl_rd_ptr           : std_logic                                        := '0';                                           -- result buffer the mux reads
  signal pending_valid        : std_logic                                        := '0';                                           -- a newer result is waiting for SOF
  signal pending_buf          : std_logic                                        := '0';
  signal overlay_sel          : std_logic;
  signal res_rd_idx           : unsigned(RB_AWORD - 1 downto 0);
  signal res_rd_data          : std_logic_vector(STREAM_DATA_WIDTH - 1 downto 0);

  ----------------------------------------------------------------------------
  -- Attributes (RAM inference hints)
  ----------------------------------------------------------------------------
  attribute ram_style         : string;
  attribute ram_style of frame_buf0 : signal is "block";                                                                           -- ~0.82 Mb each; use "ultra" if BRAM is tight
  attribute ram_style of frame_buf1 : signal is "block";
  attribute ram_style of res_buf0 : signal is "distributed";                                                                       -- small, async read for the overlay mux
  attribute ram_style of res_buf1 : signal is "distributed";

begin

  ----------------------------------------------------------------------------
  -- Buffer manager : owns ping-pong pointers + full flags
  --   cap_commit / feed_release can only ever target different buffers, since
  --   feed never reads a buffer capture is still filling (full=0 until commit).
  ----------------------------------------------------------------------------
  cap_buf_free <= not buf_full(0) when cap_ptr = '0' else not buf_full(1);
  feed_buf_rdy <= buf_full(0) when feed_ptr = '0' else buf_full(1);

  pBufMgr: process (clk250) is
  begin
    if rising_edge(clk250) then
      if s_axis_resetn = '0' then
        cap_ptr                             <= '0';
        feed_ptr                            <= '0';
        buf_full                            <= "00";
      else
        if cap_commit = '1' then
          if cap_ptr = '0' then
            buf_full(0)                     <= '1';
          else
            buf_full(1)                     <= '1';
          end if;
          cap_ptr                           <= not cap_ptr;
        end if;
        if feed_release = '1' then
          if feed_ptr = '0' then
            buf_full(0)                     <= '0';
          else
            buf_full(1)                     <= '0';
          end if;
          feed_ptr                          <= not feed_ptr;
        end if;
      end if;
    end if;
  end process pBufMgr;

  ----------------------------------------------------------------------------
  -- Frame buffer memory : 1 write port (capture), 1 read port (feed)
  --   Registered read => 1-cycle latency; the feed FSM hides it with F_WAIT.
  ----------------------------------------------------------------------------
  pFrameMem: process (clk250) is
  begin
    if rising_edge(clk250) then
      if fb_wr_en = '1' then
        if cap_ptr = '0' then
          frame_buf0(to_integer(fb_wr_idx)) <= fb_wr_data;
        else
          frame_buf1(to_integer(fb_wr_idx)) <= fb_wr_data;
        end if;
      end if;
      if feed_ptr = '0' then
        fb_rd_data                          <= frame_buf0(to_integer(fb_rd_idx));
      else
        fb_rd_data                          <= frame_buf1(to_integer(fb_rd_idx));
      end if;
    end if;
  end process pFrameMem;

  ----------------------------------------------------------------------------
  -- Capture engine : snoops the live stream, lands exactly one valid frame.
  --   Guard: commit only if word 6399 carries EOF; drop short/garbled frames.
  --   Runs off s_axis_tvalid only - it never gates the bus.
  ----------------------------------------------------------------------------
  pCapture: process (clk250) is
  begin
    if rising_edge(clk250) then
      if s_axis_resetn = '0' then
        cap_state                           <= C_IDLE;
        cap_word_cnt                        <= (others => '0');
        fb_wr_en                            <= '0';
        cap_commit                          <= '0';
      else
        fb_wr_en                            <= '0';                                                                                -- default
        cap_commit                          <= '0';                                                                                -- default

        case cap_state is

          when C_IDLE =>
            if cap_buf_free = '1' then
              cap_state                     <= C_ARM;
            end if;

          when C_ARM =>
            -- wait for Start-of-Frame, then write it as word 0
            if s_axis_tvalid = '1' and s_axis_tuser(0) = '1' then
              fb_wr_en                      <= '1';
              fb_wr_idx                     <= (others => '0');
              fb_wr_data                    <= s_axis_tdata;
              cap_word_cnt                  <= to_unsigned(1, cap_word_cnt'length);
              cap_state                     <= C_WRITE;
            end if;

          when C_WRITE =>
            if s_axis_tvalid = '1' then
              if s_axis_tuser(0) = '1' then
                -- unexpected SOF mid-frame: restart capture from this beat
                fb_wr_en                    <= '1';
                fb_wr_idx                   <= (others => '0');
                fb_wr_data                  <= s_axis_tdata;
                cap_word_cnt                <= to_unsigned(1, cap_word_cnt'length);
              else
                fb_wr_en                    <= '1';
                fb_wr_idx                   <= cap_word_cnt;
                fb_wr_data                  <= s_axis_tdata;
                if cap_word_cnt = to_unsigned(WORDS_PER_FRAME - 1, cap_word_cnt'length) then
                  -- last expected word: require EOF here, else drop
                  if s_axis_tuser(3) = '1' then
                    cap_commit              <= '1';
                  end if;
                  cap_word_cnt              <= (others => '0');
                  cap_state                 <= C_IDLE;
                elsif s_axis_tuser(3) = '1' then
                  -- premature EOF (short frame): drop, do not commit
                  cap_word_cnt              <= (others => '0');
                  cap_state                 <= C_IDLE;
                else
                  cap_word_cnt              <= cap_word_cnt + 1;
                end if;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process pCapture;

  ----------------------------------------------------------------------------
  -- Feed engine : reads the ready buffer, sequentializes 128b -> 16x 8b pixels
  --   at 1 px/cycle, honoring FOLO back-pressure (input_3_TREADY) losslessly.
  --   Chains straight into the next ready buffer; if none is ready it idles
  --   with tvalid low, stalling FOLO (the previous frame's tail stays in the
  --   pipeline until the next frame arrives - the accepted "gap" behaviour).
  --   fb_rd_idx is combinational; F_WAIT burns one cycle for read latency.
  ----------------------------------------------------------------------------
  fb_rd_idx                                 <= feed_word_idx;

  pFeed: process (clk250) is
  begin
    if rising_edge(clk250) then
      if s_axis_resetn = '0' then
        feed_state                          <= F_IDLE;
        feed_word_idx                       <= (others => '0');
        feed_pix_cnt                        <= (others => '0');
        cur_word                            <= (others => '0');
        folo_in_tvalid                      <= '0';
        folo_in_tdata                       <= (others => '0');
        feed_release                        <= '0';
      else
        feed_release                        <= '0';                                                                                -- default

        case feed_state is

          when F_IDLE =>
            folo_in_tvalid                  <= '0';
            if feed_buf_rdy = '1' then
              feed_word_idx                 <= (others => '0');                                                                    -- request word 0 (via fb_rd_idx)
              feed_state                    <= F_WAIT;
            end if;

          when F_WAIT =>
            -- one cycle for the registered BRAM read to settle
            folo_in_tvalid                  <= '0';
            feed_state                      <= F_LOAD;

          when F_LOAD =>
            -- fb_rd_data now holds the requested word; present pixel 0
            cur_word                        <= fb_rd_data;
            folo_in_tdata                   <= std_logic_vector(resize(unsigned(fb_rd_data(BITS_PER_PIXEL - 1 downto 0)), FOLO_OUT_WIDTH));
            folo_in_tvalid                  <= '1';
            feed_pix_cnt                    <= to_unsigned(WORDS_PER_STREAM - 1, feed_pix_cnt'length);                             -- 15 remaining
            feed_state                      <= F_RUN;

          when F_RUN =>
            -- tdata/tvalid held stable while FOLO is not ready (lossless stall)
            if folo_in_tready = '1' then
              if feed_pix_cnt = 0 then
                -- 16th pixel of this word just accepted
                if feed_word_idx = to_unsigned(WORDS_PER_FRAME - 1, feed_word_idx'length) then
                  -- last word of the frame: hand buffer back, look for next
                  feed_release              <= '1';
                  folo_in_tvalid            <= '0';
                  feed_state                <= F_IDLE;
                else
                  feed_word_idx             <= feed_word_idx + 1;                                                                  -- fetch next word
                  folo_in_tvalid            <= '0';
                  feed_state                <= F_WAIT;
                end if;
              else
                -- present next pixel (byte above current) and shift down
                folo_in_tdata               <= std_logic_vector(resize(unsigned(cur_word(2 * BITS_PER_PIXEL - 1 downto BITS_PER_PIXEL)), FOLO_OUT_WIDTH));
                cur_word                    <= std_logic_vector(shift_right(unsigned(cur_word), BITS_PER_PIXEL));
                feed_pix_cnt                <= feed_pix_cnt - 1;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process pFeed;

  ----------------------------------------------------------------------------
  -- FOLO instance (free-running: ap_start tied high, output always accepted)
  ----------------------------------------------------------------------------
  uFolo: component folo_0
  port map (
    input_3_TDATA      => folo_in_tdata,
    input_3_TVALID     => folo_in_tvalid,
    input_3_TREADY     => folo_in_tready,
    layer16_out_TDATA  => folo_out_tdata,
    layer16_out_TVALID => folo_out_tvalid,
    layer16_out_TREADY => '1',
    ap_clk             => clk250,
    ap_rst_n           => s_axis_resetn,
    ap_start           => '1',
    ap_done            => open,
    ap_ready           => open,
    ap_idle            => open
  );

  ----------------------------------------------------------------------------
  -- Collector : counts output handshakes, packs 8 x 16b -> 128b word.
  --   Value k (0..1599) -> word k/8, slot k mod 8, slot s at bits [16s+15:16s]
  --   (value 0 in the LSBs). Every 1600 values = one result -> swap buffer.
  --   Frame-agnostic: the modulo-1600 phase IS the frame boundary, so the
  --   1457/143 latency split never needs to be handled explicitly.
  ----------------------------------------------------------------------------
  pCollect: process (clk250) is
  begin
    if rising_edge(clk250) then
      if s_axis_resetn = '0' then
        res_val_cnt                         <= (others => '0');
        pack_word                           <= (others => '0');
        res_wptr                            <= '0';
        res_wr_en                           <= '0';
        res_ready_pulse                     <= '0';
        res_ready_buf                       <= '0';
      else
        res_wr_en                           <= '0';                                                                                -- default
        res_ready_pulse                     <= '0';                                                                                -- default

        -- layer16_out_TREADY is tied '1', so a handshake == TVALID
        if folo_out_tvalid = '1' then
          -- shift the new value into the top; after 8 inserts value 0 sits in LSBs
          if res_val_cnt(SLOT_BITS - 1 downto 0) = to_unsigned(FOLO_OUTS_PER_WORD - 1, SLOT_BITS) then
            res_wr_data                     <= folo_out_tdata & pack_word(STREAM_DATA_WIDTH - 1 downto FOLO_OUT_WIDTH);
            res_wr_idx                      <= res_val_cnt(VAL_CNT_WIDTH - 1 downto SLOT_BITS);                                    -- word addr = k / 8
            res_wr_en                       <= '1';
          end if;
          pack_word                         <= folo_out_tdata & pack_word(STREAM_DATA_WIDTH - 1 downto FOLO_OUT_WIDTH);

          if res_val_cnt = to_unsigned(FOLO_OUT_VALUES - 1, res_val_cnt'length) then
            res_val_cnt                     <= (others => '0');
            res_ready_pulse                 <= '1';
            res_ready_buf                   <= res_wptr;                                                                           -- buffer just completed (pre-toggle)
            res_wptr                        <= not res_wptr;
          else
            res_val_cnt                     <= res_val_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process pCollect;

  ----------------------------------------------------------------------------
  -- Result buffer memory : 1 write port (collector). Read is async (below).
  --   Writes use res_wptr at the write edge (toggle is scheduled for next cyc),
  --   so the final word of a group lands in the buffer being reported ready.
  ----------------------------------------------------------------------------
  pResMem: process (clk250) is
  begin
    if rising_edge(clk250) then
      if res_wr_en = '1' then
        if res_wptr = '0' then
          res_buf0(to_integer(res_wr_idx))  <= res_wr_data;
        else
          res_buf1(to_integer(res_wr_idx))  <= res_wr_data;
        end if;
      end if;
    end if;
  end process pResMem;

  -- Async read for the overlay mux (distributed RAM): same-cycle, no latency,
  -- so the mux stays correct under arbitrary m_axis back-pressure.
  -- Clamp to [0, OVERLAY_WORDS-1] on BOTH bounds: cur_idx falls through to
  -- ovl_idx (which runs up to WORDS_PER_FRAME) during inter-frame blanking, and
  -- this concurrent read evaluates the index regardless of overlay_sel.
  res_rd_idx <= resize(cur_idx - to_unsigned(OVERLAY_START, FB_AWORD), RB_AWORD) when (cur_idx >= to_unsigned(OVERLAY_START, FB_AWORD) and cur_idx < to_unsigned(OVERLAY_START + OVERLAY_WORDS, FB_AWORD)) else (others => '0');
  res_rd_data <= res_buf0(to_integer(res_rd_idx)) when ovl_rd_ptr = '0' else res_buf1(to_integer(res_rd_idx));

  ----------------------------------------------------------------------------
  -- Overlay mux control : tracks the output-frame word index, arms the latest
  --   completed result at SOF (latch-at-SOF => one result per frame, no tear).
  ----------------------------------------------------------------------------
  cur_idx <= (others => '0') when (s_axis_tvalid = '1' and s_axis_tuser(0) = '1') else ovl_idx;

  pOverlay: process (clk250) is
  begin
    if rising_edge(clk250) then
      if s_axis_resetn = '0' then
        ovl_idx                             <= (others => '0');
        ovl_armed                           <= '0';
        ovl_rd_ptr                          <= '0';
        pending_valid                       <= '0';
        pending_buf                         <= '0';
      else
        -- latch a freshly completed result until the next SOF
        if res_ready_pulse = '1' then
          pending_valid                     <= '1';
          pending_buf                       <= res_ready_buf;
        end if;

        -- advance on an output beat (passthrough never stalls the bus)
        if s_axis_tvalid = '1' and m_axis_tready = '1' then
          if s_axis_tuser(0) = '1' then
            ovl_idx                         <= to_unsigned(1, ovl_idx'length);
            if res_ready_pulse = '1' then                                                                                          -- result completed this very cycle
              ovl_rd_ptr                    <= res_ready_buf;
              ovl_armed                     <= '1';
              pending_valid                 <= '0';
            elsif pending_valid = '1' then
              ovl_rd_ptr                    <= pending_buf;
              ovl_armed                     <= '1';
              pending_valid                 <= '0';
            end if;
          else
            ovl_idx                         <= ovl_idx + 1;
          end if;
        end if;
      end if;
    end if;
  end process pOverlay;

  ----------------------------------------------------------------------------
  -- Active Outputs
  ----------------------------------------------------------------------------
  -- AXI Stream passthrough (live path, never stalled by FOLO)
  s_axis_tready                             <= m_axis_tready;
  m_axis_tvalid                             <= s_axis_tvalid;
  m_axis_tuser                              <= s_axis_tuser;

  -- Overlay splice into the tail (bottom 10 rows) of the passthrough frame
  overlay_sel <= '1' when (ovl_armed = '1' and cur_idx >= to_unsigned(OVERLAY_START, FB_AWORD) and cur_idx < to_unsigned(OVERLAY_START + OVERLAY_WORDS, FB_AWORD)) else '0';
  m_axis_tdata <= res_rd_data when overlay_sel = '1' else s_axis_tdata;

  -- Metadata passthrough (describes the current output frame, as before)
  m_mdata_StreamId                          <= s_mdata_StreamId;
  m_mdata_SourceTag                         <= s_mdata_SourceTag;
  m_mdata_Xsize                             <= s_mdata_Xsize;
  m_mdata_Xoffs                             <= s_mdata_Xoffs;
  m_mdata_Ysize                             <= s_mdata_Ysize;
  m_mdata_Yoffs                             <= s_mdata_Yoffs;
  m_mdata_DsizeL                            <= s_mdata_DsizeL;
  m_mdata_PixelF                            <= s_mdata_PixelF;
  m_mdata_TapG                              <= s_mdata_TapG;
  m_mdata_Flags                             <= s_mdata_Flags;
  m_mdata_Timestamp                         <= s_mdata_Timestamp;
  m_mdata_PixProcFlgs                       <= s_mdata_PixProcFlgs;
  m_mdata_Status                            <= s_mdata_Status;

  ----------------------------------------------------------------------------
  -- Inactive outputs
  ----------------------------------------------------------------------------
  -- Control register reads (no user registers)
  s_ctrl_data_rd                            <= (others => '0');

  -- GP I/O outputs (inactive)
  user_output_ctrl                          <= (others => '0');
  custom_logic_output_ctrl                  <= (others => '0');

  -- AXI4 master (idle - no memory access)
  m_axi_awaddr                              <= (others => '0');
  m_axi_awlen                               <= (others => '0');
  m_axi_awsize                              <= (others => '0');
  m_axi_awburst                             <= (others => '0');
  m_axi_awlock                              <= '0';
  m_axi_awcache                             <= (others => '0');
  m_axi_awprot                              <= (others => '0');
  m_axi_awqos                               <= (others => '0');
  m_axi_awvalid                             <= '0';
  m_axi_wdata                               <= (others => '0');
  m_axi_wstrb                               <= (others => '0');
  m_axi_wlast                               <= '0';
  m_axi_wvalid                              <= '0';
  m_axi_bready                              <= '1';
  m_axi_araddr                              <= (others => '0');
  m_axi_arlen                               <= (others => '0');
  m_axi_arsize                              <= (others => '0');
  m_axi_arburst                             <= (others => '0');
  m_axi_arlock                              <= '0';
  m_axi_arcache                             <= (others => '0');
  m_axi_arprot                              <= (others => '0');
  m_axi_arqos                               <= (others => '0');
  m_axi_arvalid                             <= '0';
  m_axi_rready                              <= '0';

  -- Memento (inactive)
  m_memento_event                           <= '0';
  m_memento_arg0                            <= (others => '0');
  m_memento_arg1                            <= (others => '0');

end architecture behav;
