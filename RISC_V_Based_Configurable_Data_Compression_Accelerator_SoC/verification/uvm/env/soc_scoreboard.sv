// =============================================================================
// soc_scoreboard.sv — Unified Self-Checking Scoreboard for SoC UVM
// Performs active VIP checking (UART, GPIO, Reset, IRQ) AND passive internal
// bus/accelerator/memory checking via soc_obs_if against software golden
// reference models (RLE compression/decompression, IEEE 802.3 CRC-32, DMA
// boundary/data integrity, GPIO MMIO->pin match, and DECERR/protocol audit).
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_SCOREBOARD_SV
`define SOC_SCOREBOARD_SV

`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_reset)
`uvm_analysis_imp_decl(_irq)

class soc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_scoreboard)

  // Analysis implementation exports for the 4 VIP agents (UART, GPIO, Reset, IRQ)
  uvm_analysis_imp_uart  #(uart_seq_item,  soc_scoreboard) uart_export;
  uvm_analysis_imp_gpio  #(gpio_seq_item,  soc_scoreboard) gpio_export;
  uvm_analysis_imp_reset #(reset_seq_item, soc_scoreboard) reset_export;
  uvm_analysis_imp_irq   #(irq_seq_item,   soc_scoreboard) irq_export;

  soc_env_cfg    cfg;
  virtual soc_obs_if obs_vif;
  bit            has_obs_vif = 1'b0;

  // Authoritative Address Map Constants
  localparam [31:0] ADDR_DMEM_START = 32'h0001_0000;
  localparam [31:0] ADDR_DMEM_END   = 32'h0002_FFFF;
  localparam [31:0] ADDR_GPIO_OUT   = 32'h0006_0004;
  localparam [31:0] ADDR_GPIO_DIR   = 32'h0006_0008;
  localparam [31:0] ADDR_GPIO_SET   = 32'h0006_001C;
  localparam [31:0] ADDR_GPIO_CLR   = 32'h0006_0020;
  localparam [31:0] ADDR_GPIO_TOG   = 32'h0006_0024;
  localparam [31:0] ADDR_CRC_DATA   = 32'h000A_0000;
  localparam [31:0] ADDR_CRC_RESULT = 32'h000A_0004;
  localparam [31:0] ADDR_CRC_CTRL   = 32'h000A_0008;
  localparam [31:0] ADDR_DMA_CTRL   = 32'h000B_0000;
  localparam [31:0] ADDR_DMA_STATUS = 32'h000B_0004;
  localparam [31:0] ADDR_DMA_SRC    = 32'h000B_0008;
  localparam [31:0] ADDR_DMA_DST    = 32'h000B_000C;
  localparam [31:0] ADDR_DMA_INLEN  = 32'h000B_0010;
  localparam [31:0] ADDR_DMA_OUTLEN = 32'h000B_0014;
  localparam [31:0] ADDR_DMA_ERRC   = 32'h000B_0020;
  localparam [31:0] ADDR_RLE_CTRL   = 32'h000D_0000;
  localparam [31:0] ADDR_RLE_STATUS = 32'h000D_0004;
  localparam [31:0] ADDR_RLE_INLEN  = 32'h000D_0008;
  localparam [31:0] ADDR_RLE_OUTLEN = 32'h000D_000C;
  localparam [31:0] ADDR_RLE_INDATA = 32'h000D_0010;
  localparam [31:0] ADDR_RLE_OUTDAT = 32'h000D_0014;

  // UART Verification tracking state
  string expected_str       = "HI";
  string received_str       = "";
  int    uart_chars_matched = 0;
  int    uart_frame_errors  = 0;
  int    total_uart_rx      = 0;
  bit    uart_test_passed   = 1'b0;

  // Peripheral & Bus Reference Model State
  int    gpio_transitions   = 0;
  int    gpio_pin_checks    = 0;
  int    reset_assertions   = 0;
  int    reset_quiesc_errs  = 0;
  int    irq_events         = 0;
  bit    seen_timer_irq     = 1'b0;
  bit    seen_gpio_irq      = 1'b0;
  bit    seen_rle_irq       = 1'b0;
  bit    seen_dma_irq       = 1'b0;

  // Shadow DMEM mirror updated passively from M01 bus writes
  logic [7:0] shadow_dmem [logic [31:0]];

  // LSU transaction trackers
  typedef struct {
    logic [31:0] addr;
    logic [31:0] data;
    logic [ 3:0] strb;
  } wr_req_t;

  logic [31:0] lsu_aw_q[$];
  wr_req_t     lsu_w_q[$];
  logic [31:0] lsu_b_addr_q[$];
  logic [31:0] lsu_ar_addr_q[$];

  // Expected GPIO state
  logic [31:0] exp_gpio_o  = 32'h0;
  logic [31:0] exp_gpio_oe = 32'h0;
  typedef struct {
    bit          check_pin;
    logic [31:0] gpio_o;
    logic [31:0] gpio_oe;
  } gpio_chk_t;
  gpio_chk_t   lsu_gpio_chk_q[$];

  // IEEE 802.3 CRC-32 Reference Model state
  logic [31:0] sw_crc_state = 32'hFFFF_FFFF;
  int          crc_checks_passed = 0;

  // Direct RLE Reference Model state
  logic [ 7:0] rle_in_q[$];
  int          rle_cfg_len = 0;
  logic [ 7:0] rle_gold_out[];
  int          rle_gold_len = 0;
  bit          rle_gold_err = 1'b0;
  int          rle_out_rd_idx = 0;
  bit          rle_check_active = 1'b0;
  int          rle_ops_passed = 0;

  // DMA Reference Model state
  logic [31:0] dma_cfg_src = 32'h0001_0000;
  logic [31:0] dma_cfg_dst = 32'h0001_0100;
  int          dma_cfg_len = 0;
  bit          dma_cfg_mode = 1'b0;
  bit          dma_active = 1'b0;
  bit          dma_status_checked = 1'b0;
  bit          dma_exp_err = 1'b0;
  logic [ 7:0] dma_exp_err_code = 8'h00;
  logic [ 7:0] dma_gold_out[];
  int          dma_gold_len = 0;
  logic [ 7:0] dma_dst_bytes [logic [31:0]];
  int          dma_dst_wr_count = 0;
  int          dma_xfers_passed = 0;

  // Bus Error Tracking
  int          expected_decerr_hits   = 0;
  int          unexpected_bus_errors  = 0;
  int          scb_failures           = 0;

  function new(string name = "soc_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    uart_export  = new("uart_export", this);
    gpio_export  = new("gpio_export", this);
    reset_export = new("reset_export", this);
    irq_export   = new("irq_export", this);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (uvm_config_db#(soc_env_cfg)::get(this, "", "cfg", cfg)) begin
      expected_str = cfg.expected_uart_string;
      `uvm_info("SOC_SCB", $sformatf("Configured expected_str = \"%s\" from soc_env_cfg", expected_str), UVM_LOW)
    end
    has_obs_vif = uvm_config_db#(virtual soc_obs_if)::get(this, "", "obs_vif", obs_vif);
    if (has_obs_vif) begin
      `uvm_info("SOC_SCB", "Bound passive soc_obs_if for SoC MMIO/Accelerator/Bus reference checking", UVM_LOW)
    end
  endfunction : build_phase

  function void set_expected_string(string s);
    expected_str = s;
  endfunction : set_expected_string

  function void reset_uart_tracking(string new_expected = "");
    if (new_expected != "") expected_str = new_expected;
    received_str       = "";
    uart_chars_matched = 0;
    uart_frame_errors  = 0;
    total_uart_rx      = 0;
    uart_test_passed   = 1'b0;
  endfunction : reset_uart_tracking

  // ---------------------------------------------------------------------------
  // Golden Reference Model: IEEE 802.3 CRC-32 Byte Step (0xEDB88320)
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] crc32_step_byte(input logic [31:0] crc_in, input logic [7:0] data_byte);
    logic [31:0] c = crc_in ^ {24'h0, data_byte};
    for (int k = 0; k < 8; k++) begin
      if (c[0]) c = (c >> 1) ^ 32'hEDB8_8320;
      else      c = (c >> 1);
    end
    return c;
  endfunction : crc32_step_byte

  // ---------------------------------------------------------------------------
  // Golden Reference Model: RLE Compress / Decompress Prediction
  // ---------------------------------------------------------------------------
  function automatic void rle_predict(
    input  bit          mode,
    input  logic [7:0]  in_data[],
    input  int          in_len,
    input  int          buf_depth,
    output logic [7:0]  out_data[],
    output int          out_len,
    output bit          err_flag
  );
    err_flag = 1'b0;
    if (in_len == 0) begin
      out_len  = 0;
      out_data = new[0];
      return;
    end
    if (mode == 1'b0) begin
      int idx = 0;
      logic [7:0] q[$];
      while (idx < in_len) begin
        logic [7:0] sym = in_data[idx];
        int run = 1;
        idx++;
        while (idx < in_len && in_data[idx] == sym && run < 255) begin
          run++;
          idx++;
        end
        q.push_back(run[7:0]);
        q.push_back(sym);
      end
      if (q.size() > buf_depth) begin
        err_flag = 1'b1;
        out_len  = 0;
        out_data = new[0];
        return;
      end
      out_len  = q.size();
      out_data = new[out_len];
      for (int i = 0; i < out_len; i++) out_data[i] = q[i];
    end else begin
      logic [7:0] eq[$];
      if ((in_len % 2) != 0) begin
        err_flag = 1'b1;
        out_len  = 0;
        out_data = new[0];
        return;
      end
      for (int i = 0; i < in_len; i += 2) begin
        int cnt = in_data[i];
        logic [7:0] sym = in_data[i+1];
        if (cnt == 0 || (eq.size() + cnt > buf_depth)) begin
          err_flag = 1'b1;
          out_len  = 0;
          out_data = new[0];
          return;
        end
        for (int c = 0; c < cnt; c++) eq.push_back(sym);
      end
      out_len  = eq.size();
      out_data = new[out_len];
      for (int i = 0; i < out_len; i++) out_data[i] = eq[i];
    end
  endfunction : rle_predict

  // ---------------------------------------------------------------------------
  // UART Analysis Port Implementation
  // ---------------------------------------------------------------------------
  virtual function void write_uart(uart_seq_item item);
    byte ch = item.data;
    total_uart_rx++;

    if (item.framing_err || item.parity_err) begin
      uart_frame_errors++;
      scb_failures++;
      `uvm_error("UART_SCB",
                 $sformatf("[UART_SCB] Protocol frame error detected on char #%0d! framing_err=%0b, parity_err=%0b",
                           total_uart_rx, item.framing_err, item.parity_err))
      return;
    end

    received_str = {received_str, string'(ch)};
    `uvm_info("UART_SCB",
              $sformatf("[UART_SCB] Received character #%0d: '%c' (0x%02h) [Cumulative: \"%s\"] at %0t ps",
                        total_uart_rx, ch, ch, received_str, $time),
              UVM_LOW)

    if (cfg == null || cfg.enable_uart_str_check) begin
      if (total_uart_rx <= expected_str.len()) begin
        byte exp_ch = expected_str[total_uart_rx - 1];
        if (ch == exp_ch) begin
          uart_chars_matched++;
          `uvm_info("UART_SCB",
                    $sformatf("[UART_SCB] Character match #%0d PASS: expected '%c', got '%c'",
                              total_uart_rx, exp_ch, ch),
                    UVM_LOW)
        end else begin
          scb_failures++;
          `uvm_error("UART_SCB",
                     $sformatf("[UART_SCB] Character mismatch at pos #%0d: expected '%c' (0x%02h), got '%c' (0x%02h)",
                               total_uart_rx, exp_ch, exp_ch, ch, ch))
        end
      end else begin
        `uvm_warning("UART_SCB",
                     $sformatf("[UART_SCB] Received character beyond expected length (%0d): '%c'",
                               expected_str.len(), ch))
      end

      if (total_uart_rx == expected_str.len() && uart_chars_matched == expected_str.len()) begin
        uart_test_passed = 1'b1;
        `uvm_info("UART_SCB",
                  $sformatf("[UART_SCB] COMPLETE MATCH! Fully received expected string \"%s\" with 0 errors.",
                            expected_str),
                  UVM_NONE)
      end
    end
  endfunction : write_uart

  // ---------------------------------------------------------------------------
  // GPIO / Reset / IRQ VIP Analysis Ports
  // ---------------------------------------------------------------------------
  virtual function void write_gpio(gpio_seq_item item);
    gpio_transitions++;
    `uvm_info("GPIO_SCB",
              $sformatf("[GPIO_SCB] Observation #%0d: gpio_o=0x%08h, gpio_oe=0x%08h at %0t ps",
                        gpio_transitions, item.gpio_o, item.gpio_oe, item.timestamp),
              UVM_MEDIUM)
  endfunction : write_gpio

  virtual function void write_reset(reset_seq_item item);
    reset_assertions++;
    `uvm_info("RST_SCB",
              $sformatf("[RST_SCB] Reset event #%0d: kind=%s, duration=%0d cycles at %0t ps",
                        reset_assertions, item.kind.name(), item.duration_cycles, item.timestamp),
              UVM_LOW)
  endfunction : write_reset

  virtual function void write_irq(irq_seq_item item);
    irq_events++;
    if (item.is_assertion) begin
      case (item.irq_channel)
        0: seen_gpio_irq  = 1'b1;
        1: seen_timer_irq = 1'b1;
        2: seen_rle_irq   = 1'b1;
        3: seen_dma_irq   = 1'b1;
        default: ;
      endcase
    end
    `uvm_info("IRQ_SCB",
              $sformatf("[IRQ_SCB] Interrupt event #%0d: channel=%0d, asserted=%0b, irq_status=4'b%04b at %0t ps",
                        irq_events, item.irq_channel, item.is_assertion, item.irq_status, item.timestamp),
              UVM_MEDIUM)
  endfunction : write_irq

  // ---------------------------------------------------------------------------
  // Internal Helper: Process Completed LSU Write Pair against Golden Models
  // ---------------------------------------------------------------------------
  function void process_lsu_write(input logic [31:0] addr, input logic [31:0] data, input logic [3:0] strb);
    gpio_chk_t gchk;
    gchk.check_pin = 1'b0;
    gchk.gpio_o    = exp_gpio_o;
    gchk.gpio_oe   = exp_gpio_oe;

    // 1. GPIO Pin Model
    if (addr == ADDR_GPIO_OUT) begin
      for (int b = 0; b < 4; b++) if (strb[b]) exp_gpio_o[b*8 +: 8] = data[b*8 +: 8];
      gchk.check_pin = 1'b1;
      gchk.gpio_o    = exp_gpio_o;
    end else if (addr == ADDR_GPIO_DIR) begin
      for (int b = 0; b < 4; b++) if (strb[b]) exp_gpio_oe[b*8 +: 8] = data[b*8 +: 8];
      gchk.check_pin = 1'b1;
      gchk.gpio_oe   = exp_gpio_oe;
    end else if (addr == ADDR_GPIO_SET) begin
      exp_gpio_o    |= data;
      gchk.check_pin = 1'b1;
      gchk.gpio_o    = exp_gpio_o;
    end else if (addr == ADDR_GPIO_CLR) begin
      exp_gpio_o    &= ~data;
      gchk.check_pin = 1'b1;
      gchk.gpio_o    = exp_gpio_o;
    end else if (addr == ADDR_GPIO_TOG) begin
      exp_gpio_o    ^= data;
      gchk.check_pin = 1'b1;
      gchk.gpio_o    = exp_gpio_o;
    end
    lsu_gpio_chk_q.push_back(gchk);
    lsu_b_addr_q.push_back(addr);

    if (cfg != null && !cfg.enable_bus_ref_check) return;

    // 2. CRC-32 Software Model
    if (addr == ADDR_CRC_CTRL && strb[0] && data[0]) begin
      sw_crc_state = 32'hFFFF_FFFF;
    end else if (addr == ADDR_CRC_DATA) begin
      for (int b = 0; b < 4; b++) begin
        if (strb[b]) sw_crc_state = crc32_step_byte(sw_crc_state, data[b*8 +: 8]);
      end
    end

    // 3. Direct RLE Reference Model
    if (addr == ADDR_RLE_INLEN) begin
      rle_cfg_len = data[15:0];
      rle_in_q.delete();
      rle_out_rd_idx   = 0;
      rle_check_active = 1'b0;
    end else if (addr == ADDR_RLE_INDATA) begin
      for (int b = 0; b < 4; b++) begin
        if (strb[b]) rle_in_q.push_back(data[b*8 +: 8]);
      end
    end else if (addr == ADDR_RLE_CTRL && strb[0] && data[0]) begin
      automatic logic [7:0] in_arr[];
      in_arr = new[rle_cfg_len];
      for (int i = 0; i < rle_cfg_len; i++) begin
        in_arr[i] = (i < rle_in_q.size()) ? rle_in_q[i] : 8'h00;
      end
      rle_predict(data[1], in_arr, rle_cfg_len, 256, rle_gold_out, rle_gold_len, rle_gold_err);
      rle_out_rd_idx   = 0;
      rle_check_active = 1'b1;
    end

    // 4. DMA End-to-End Reference Model
    if (addr == ADDR_DMA_SRC)        dma_cfg_src = data;
    else if (addr == ADDR_DMA_DST)   dma_cfg_dst = data;
    else if (addr == ADDR_DMA_INLEN) dma_cfg_len = data[15:0];
    else if (addr == ADDR_DMA_CTRL && strb[0] && data[0] && !dma_active) begin
      dma_cfg_mode       = data[1];
      dma_active         = 1'b1;
      dma_status_checked = 1'b0;
      dma_dst_bytes.delete();
      dma_dst_wr_count   = 0;
      dma_exp_err        = 1'b0;
      dma_exp_err_code   = 8'h00;

      if (dma_cfg_len == 0 || dma_cfg_len > 256) begin
        dma_exp_err      = 1'b1;
        dma_exp_err_code = 8'h03;
      end else if (dma_cfg_src < ADDR_DMEM_START || dma_cfg_src > ADDR_DMEM_END ||
                   ((longint'(dma_cfg_src) + dma_cfg_len - 1) > longint'(ADDR_DMEM_END))) begin
        dma_exp_err      = 1'b1;
        dma_exp_err_code = 8'h01;
      end else if (dma_cfg_dst < ADDR_DMEM_START || dma_cfg_dst > ADDR_DMEM_END) begin
        dma_exp_err      = 1'b1;
        dma_exp_err_code = 8'h02;
      end else begin
        automatic logic [7:0] src_arr[];
        automatic bit r_err;
        src_arr = new[dma_cfg_len];
        for (int i = 0; i < dma_cfg_len; i++) begin
          src_arr[i] = shadow_dmem.exists(dma_cfg_src + i) ? shadow_dmem[dma_cfg_src + i] : 8'h00;
        end
        rle_predict(dma_cfg_mode, src_arr, dma_cfg_len, 256, dma_gold_out, dma_gold_len, r_err);
        if (r_err || dma_gold_len > 256) begin
          dma_exp_err      = 1'b1;
          dma_exp_err_code = 8'h06;
        end else if (dma_gold_len > 0 && ((longint'(dma_cfg_dst) + dma_gold_len - 1) > longint'(ADDR_DMEM_END))) begin
          dma_exp_err      = 1'b1;
          dma_exp_err_code = 8'h02;
        end
      end
    end
  endfunction : process_lsu_write

  // ---------------------------------------------------------------------------
  // Passive Bus & Pin Monitor Task (runs automatically when obs_vif present)
  // ---------------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    if (!has_obs_vif) return;

    fork
      monitor_obs_bus();
    join_none
  endtask : run_phase

  virtual task monitor_obs_bus();
    bit          m01_wr_active = 1'b0;
    logic [31:0] m01_wr_addr   = 32'h0;
    bit          dma_wr_active = 1'b0;
    logic [31:0] dma_wr_addr   = 32'h0;
    int          rst_low_cnt   = 0;
    bit          prev_rst_n    = 1'b0;

    forever begin
      @(posedge obs_vif.clk);

      // Handle reset assertion & quiescence check
      if (!obs_vif.rst_n) begin
        if (prev_rst_n == 1'b1) begin
          // Warm reset entered after normal operation
          if (cfg != null && cfg.clear_uart_on_warm_reset) begin
            reset_uart_tracking(expected_str);
          end
        end
        prev_rst_n = 1'b0;
        rst_low_cnt++;
        if (rst_low_cnt >= 2) begin
          if (obs_vif.timer_irq !== 1'b0 || obs_vif.gpio_irq !== 1'b0 ||
              obs_vif.rle_irq   !== 1'b0 || obs_vif.dma_irq  !== 1'b0 ||
              obs_vif.gpio_oe   !== 32'h0 || obs_vif.uart_tx !== 1'b1) begin
            reset_quiesc_errs++;
            scb_failures++;
            `uvm_error("RST_SCB", "Reset quiescence violation detected on external IRQs/GPIO_OE/UART_TX!")
          end
        end
        lsu_aw_q.delete();
        lsu_w_q.delete();
        lsu_b_addr_q.delete();
        lsu_ar_addr_q.delete();
        lsu_gpio_chk_q.delete();
        exp_gpio_o    = 32'h0;
        exp_gpio_oe   = 32'h0;
        sw_crc_state  = 32'hFFFF_FFFF;
        rle_check_active = 1'b0;
        rle_in_q.delete();
        dma_active    = 1'b0;
        dma_status_checked = 1'b0;
        m01_wr_active = 1'b0;
        dma_wr_active = 1'b0;
        continue;
      end
      prev_rst_n  = 1'b1;
      rst_low_cnt = 0;

      // IRQ state observation directly (also tracked via irq_agnt)
      if (obs_vif.timer_irq) seen_timer_irq = 1'b1;
      if (obs_vif.gpio_irq)  seen_gpio_irq  = 1'b1;
      if (obs_vif.rle_irq)   seen_rle_irq   = 1'b1;
      if (obs_vif.dma_irq)   seen_dma_irq   = 1'b1;

      // 1. Passive M01 DMEM Write Mirroring
      if (obs_vif.m01_awvalid && obs_vif.m01_awready) begin
        m01_wr_addr   = obs_vif.m01_awaddr;
        m01_wr_active = 1'b1;
      end
      if (obs_vif.m01_wvalid && obs_vif.m01_wready) begin
        automatic logic [31:0] ba = (obs_vif.m01_awvalid && obs_vif.m01_awready) ? obs_vif.m01_awaddr : m01_wr_addr;
        automatic logic [31:0] wa = {ba[31:2], 2'b00};
        for (int b = 0; b < 4; b++) begin
          if (obs_vif.m01_wstrb[b]) shadow_dmem[wa + b] = obs_vif.m01_wdata[b*8 +: 8];
        end
        m01_wr_addr = wa + 32'd4;
        if (obs_vif.m01_wlast) m01_wr_active = 1'b0;
      end

      // 2. Passive DMA Master Write Snoop (DMEM destination verification)
      if (obs_vif.dma_awvalid && obs_vif.dma_awready) begin
        dma_wr_addr   = obs_vif.dma_awaddr;
        dma_wr_active = 1'b1;
      end
      if (obs_vif.dma_wvalid && obs_vif.dma_wready) begin
        automatic logic [31:0] da = (obs_vif.dma_awvalid && obs_vif.dma_awready) ? obs_vif.dma_awaddr : dma_wr_addr;
        automatic logic [31:0] dwa = {da[31:2], 2'b00};
        if (dma_active && dwa >= ADDR_DMEM_START && dwa <= ADDR_DMEM_END) begin
          for (int b = 0; b < 4; b++) begin
            if (obs_vif.dma_wstrb[b]) begin
              dma_dst_bytes[dwa + b] = obs_vif.dma_wdata[b*8 +: 8];
              dma_dst_wr_count++;
            end
          end
        end
        dma_wr_addr = dwa + 32'd4;
        if (obs_vif.dma_wlast) dma_wr_active = 1'b0;
      end
      if (obs_vif.dma_bvalid && obs_vif.dma_bready) begin
        if (obs_vif.dma_bresp !== 2'b00) begin
          unexpected_bus_errors++;
          scb_failures++;
          `uvm_error("BUS_SCB", $sformatf("Unexpected DMA Master BRESP=%b!", obs_vif.dma_bresp))
        end
      end
      if (obs_vif.dma_rvalid && obs_vif.dma_rready) begin
        if (obs_vif.dma_rresp !== 2'b00) begin
          unexpected_bus_errors++;
          scb_failures++;
          `uvm_error("BUS_SCB", $sformatf("Unexpected DMA Master RRESP=%b!", obs_vif.dma_rresp))
        end
      end

      // 3. Passive LSU32 Write Pair Assembly & Response Verification
      if (obs_vif.lsu32_awvalid && obs_vif.lsu32_awready) begin
        lsu_aw_q.push_back(obs_vif.lsu32_awaddr);
      end
      if (obs_vif.lsu32_wvalid && obs_vif.lsu32_wready) begin
        wr_req_t witem;
        witem.data = obs_vif.lsu32_wdata;
        witem.strb = obs_vif.lsu32_wstrb;
        lsu_w_q.push_back(witem);
      end
      while (lsu_aw_q.size() > 0 && lsu_w_q.size() > 0) begin
        automatic logic [31:0] waddr = lsu_aw_q.pop_front();
        automatic wr_req_t witem = lsu_w_q.pop_front();
        process_lsu_write(waddr, witem.data, witem.strb);
      end

      if (obs_vif.lsu32_bvalid && obs_vif.lsu32_bready) begin
        automatic logic [31:0] baddr = (lsu_b_addr_q.size() > 0) ? lsu_b_addr_q.pop_front() : 32'h0;
        automatic gpio_chk_t gchk;
        if (lsu_gpio_chk_q.size() > 0) begin
          gchk = lsu_gpio_chk_q.pop_front();
          if (gchk.check_pin && (cfg == null || cfg.enable_bus_ref_check)) begin
            gpio_pin_checks++;
            if (obs_vif.gpio_o !== gchk.gpio_o || obs_vif.gpio_oe !== gchk.gpio_oe) begin
              scb_failures++;
              `uvm_error("GPIO_SCB", $sformatf("GPIO pin mismatch after MMIO @0x%08h! Exp o=0x%08h oe=0x%08h, Got o=0x%08h oe=0x%08h",
                                               baddr, gchk.gpio_o, gchk.gpio_oe, obs_vif.gpio_o, obs_vif.gpio_oe))
            end
          end
        end
        if (obs_vif.lsu32_bresp == 2'b11 && cfg != null && cfg.allow_expected_decerr &&
            baddr == cfg.expected_decerr_addr) begin
          expected_decerr_hits++;
        end else if (obs_vif.lsu32_bresp !== 2'b00) begin
          unexpected_bus_errors++;
          scb_failures++;
          `uvm_error("BUS_SCB", $sformatf("Unexpected LSU BRESP=%b at addr=0x%08h!", obs_vif.lsu32_bresp, baddr))
        end
      end

      // 4. Passive LSU32 Read Request & Readback Golden Model Check
      if (obs_vif.lsu32_arvalid && obs_vif.lsu32_arready) begin
        lsu_ar_addr_q.push_back(obs_vif.lsu32_araddr);
      end
      if (obs_vif.lsu32_rvalid && obs_vif.lsu32_rready) begin
        automatic logic [31:0] raddr = (lsu_ar_addr_q.size() > 0) ? lsu_ar_addr_q.pop_front() : 32'h0;
        automatic logic [31:0] rdata = obs_vif.lsu32_rdata;

        if (obs_vif.lsu32_rresp == 2'b11 && cfg != null && cfg.allow_expected_decerr &&
            raddr == cfg.expected_decerr_addr) begin
          expected_decerr_hits++;
          `uvm_info("BUS_SCB", $sformatf("Observed expected DECERR on reserved read @0x%08h", raddr), UVM_LOW)
        end else if (obs_vif.lsu32_rresp !== 2'b00) begin
          unexpected_bus_errors++;
          scb_failures++;
          `uvm_error("BUS_SCB", $sformatf("Unexpected LSU RRESP=%b at addr=0x%08h!", obs_vif.lsu32_rresp, raddr))
        end else if (cfg == null || cfg.enable_bus_ref_check) begin
          // CRC-32 result verification
          if (raddr == ADDR_CRC_RESULT) begin
            automatic logic [31:0] exp_crc = ~sw_crc_state;
            if (rdata === exp_crc) begin
              crc_checks_passed++;
              `uvm_info("CRC_SCB", $sformatf("[PASS] CRC_RESULT verified == 0x%08h", rdata), UVM_LOW)
            end else begin
              scb_failures++;
              `uvm_error("CRC_SCB", $sformatf("CRC_RESULT mismatch! HW=0x%08h, SW=0x%08h", rdata, exp_crc))
            end
          end

          // Direct RLE verification
          if (rle_check_active && raddr == ADDR_RLE_OUTLEN) begin
            if (rdata[15:0] === rle_gold_len[15:0]) begin
              if (rle_gold_len == 0) begin
                rle_ops_passed++;
                rle_check_active = 1'b0;
              end
            end else begin
              scb_failures++;
              `uvm_error("RLE_SCB", $sformatf("RLE_OUTLEN mismatch! HW=%0d, Gold=%0d", rdata[15:0], rle_gold_len))
            end
          end else if (rle_check_active && raddr == ADDR_RLE_OUTDAT) begin
            if (rle_out_rd_idx < rle_gold_len && rdata[7:0] === rle_gold_out[rle_out_rd_idx]) begin
              rle_out_rd_idx++;
              if (rle_out_rd_idx == rle_gold_len) begin
                rle_ops_passed++;
                rle_check_active = 1'b0;
                `uvm_info("RLE_SCB", $sformatf("[PASS] Direct RLE %0d-byte output verified against golden model", rle_gold_len), UVM_LOW)
              end
            end else begin
              scb_failures++;
              `uvm_error("RLE_SCB", $sformatf("RLE_OUTDAT[%0d] mismatch! HW=0x%02h", rle_out_rd_idx, rdata[7:0]))
            end
          end

          // DMA completion & DMEM byte-by-byte verification
          if (dma_active && !dma_status_checked && raddr == ADDR_DMA_STATUS && (rdata[0] == 1'b0) && (rdata[1] || rdata[2])) begin
            automatic bit xfer_ok = 1'b1;
            dma_status_checked = 1'b1;
            if (rdata[2] !== dma_exp_err || rdata[1] !== !dma_exp_err) begin
              `uvm_error("DMA_SCB", $sformatf("DMA STATUS mismatch! HW=0x%02h, exp_err=%b", rdata[7:0], dma_exp_err))
              xfer_ok = 1'b0;
            end
            if (dma_exp_err) begin
              if (dma_dst_wr_count != 0) begin
                `uvm_error("DMA_SCB", $sformatf("DMA wrote %0d bytes on expected error transfer!", dma_dst_wr_count))
                xfer_ok = 1'b0;
              end
            end else begin
              for (int i = 0; i < dma_gold_len; i++) begin
                automatic logic [31:0] ta = dma_cfg_dst + i;
                if (!dma_dst_bytes.exists(ta) || dma_dst_bytes[ta] !== dma_gold_out[i]) begin
                  `uvm_error("DMA_SCB", $sformatf("DMA dst byte mismatch @0x%08h: exp=0x%02h", ta, dma_gold_out[i]))
                  xfer_ok = 1'b0;
                  break;
                end
              end
              foreach (dma_dst_bytes[a]) begin
                if (a < dma_cfg_dst || a >= dma_cfg_dst + dma_gold_len) begin
                  `uvm_error("DMA_SCB", $sformatf("DMA out-of-range dst write @0x%08h!", a))
                  xfer_ok = 1'b0;
                end
              end
            end
            if (xfer_ok) dma_xfers_passed++;
            else         scb_failures++;
          end else if (dma_active && dma_status_checked && raddr == ADDR_DMA_OUTLEN) begin
            automatic int exp_l = dma_exp_err ? 0 : dma_gold_len;
            if (rdata[15:0] !== exp_l[15:0]) begin
              scb_failures++;
              `uvm_error("DMA_SCB", $sformatf("DMA_OUTPUT_LEN mismatch! HW=%0d, Gold=%0d", rdata[15:0], exp_l))
            end
            if (!dma_exp_err) dma_active = 1'b0;
          end else if (dma_active && dma_status_checked && raddr == ADDR_DMA_ERRC) begin
            if (rdata[7:0] !== dma_exp_err_code) begin
              scb_failures++;
              `uvm_error("DMA_SCB", $sformatf("DMA_ERROR_CODE mismatch! HW=0x%02h, Gold=0x%02h", rdata[7:0], dma_exp_err_code))
            end
            dma_active = 1'b0;
          end
        end
      end
    end
  endtask : monitor_obs_bus

  // ---------------------------------------------------------------------------
  // Final Evaluation and Checks
  // ---------------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    bit all_ok = 1'b1;
    super.check_phase(phase);

    `uvm_info("SCB_FINAL", "==========================================================", UVM_NONE)
    `uvm_info("SCB_FINAL", "           SOC SCOREBOARD FINAL SUMMARY REPORT            ", UVM_NONE)
    `uvm_info("SCB_FINAL", "==========================================================", UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Expected UART String                 : \"%s\"", expected_str), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Received UART String                 : \"%s\"", received_str), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Matching UART Characters             : %0d / %0d", uart_chars_matched, expected_str.len()), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" UART Protocol Framing Errors         : %0d", uart_frame_errors), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" System Reset Assertions / QuiescErr  : %0d / %0d", reset_assertions, reset_quiesc_errs), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" GPIO Pin Checks / Transitions        : %0d / %0d", gpio_pin_checks, gpio_transitions), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Interrupts Seen (T/G/R/D)            : %0b/%0b/%0b/%0b (VIP events=%0d)",
              seen_timer_irq, seen_gpio_irq, seen_rle_irq, seen_dma_irq, irq_events), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Verified DMA / RLE / CRC Checks      : %0d / %0d / %0d",
              dma_xfers_passed, rle_ops_passed, crc_checks_passed), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Expected DECERR / Unexpected BusErr  : %0d / %0d",
              expected_decerr_hits, unexpected_bus_errors), UVM_NONE)
    `uvm_info("SCB_FINAL", "==========================================================", UVM_NONE)

    if (cfg == null || cfg.enable_uart_str_check) begin
      if (uart_chars_matched != expected_str.len() || total_uart_rx != expected_str.len() || uart_frame_errors != 0) begin
        all_ok = 1'b0;
        `uvm_error("UART_SCB",
                   $sformatf("[UART_SCB] Scoreboard UART check failed! Expected \"%s\" (len=%0d), received \"%s\" (total_rx=%0d, err=%0d)",
                             expected_str, expected_str.len(), received_str, total_uart_rx, uart_frame_errors))
      end
    end

    if (cfg != null) begin
      if (cfg.expect_timer_irq && !seen_timer_irq) begin all_ok = 1'b0; `uvm_error("IRQ_SCB", "Expected timer_irq was never observed!") end
      if (cfg.expect_gpio_irq  && !seen_gpio_irq)  begin all_ok = 1'b0; `uvm_error("IRQ_SCB", "Expected gpio_irq was never observed!")  end
      if (cfg.expect_rle_irq   && !seen_rle_irq)   begin all_ok = 1'b0; `uvm_error("IRQ_SCB", "Expected rle_irq was never observed!")   end
      if (cfg.expect_dma_irq   && !seen_dma_irq)   begin all_ok = 1'b0; `uvm_error("IRQ_SCB", "Expected dma_irq was never observed!")   end
      if (cfg.expect_gpio_pin_check && gpio_pin_checks == 0) begin all_ok = 1'b0; `uvm_error("GPIO_SCB", "No GPIO MMIO pin checks executed!") end
      if (dma_xfers_passed < cfg.min_expected_dma_xfers) begin
        all_ok = 1'b0;
        `uvm_error("DMA_SCB", $sformatf("Expected >=%0d DMA transfers verified, got %0d", cfg.min_expected_dma_xfers, dma_xfers_passed))
      end
      if (rle_ops_passed < cfg.min_expected_rle_ops) begin
        all_ok = 1'b0;
        `uvm_error("RLE_SCB", $sformatf("Expected >=%0d RLE ops verified, got %0d", cfg.min_expected_rle_ops, rle_ops_passed))
      end
      if (crc_checks_passed < cfg.min_expected_crc_checks) begin
        all_ok = 1'b0;
        `uvm_error("CRC_SCB", $sformatf("Expected >=%0d CRC checks verified, got %0d", cfg.min_expected_crc_checks, crc_checks_passed))
      end
      if (expected_decerr_hits < cfg.min_expected_decerr_hits) begin
        all_ok = 1'b0;
        `uvm_error("BUS_SCB", $sformatf("Expected >=%0d DECERR responses, got %0d", cfg.min_expected_decerr_hits, expected_decerr_hits))
      end
      if (cfg.allow_expected_cpu_fault && has_obs_vif && obs_vif.expected_cpu_faults_seen == 0) begin
        all_ok = 1'b0;
        `uvm_error("BUS_SCB", "Expected CPU DECERR Load Fault trap was never observed!")
      end
    end

    if (scb_failures > 0 || unexpected_bus_errors > 0 || reset_quiesc_errs > 0) begin
      all_ok = 1'b0;
      `uvm_error("SOC_SCB", $sformatf("Scoreboard detected %0d internal errors!", scb_failures))
    end

    if (all_ok) begin
      `uvm_info("SOC_SCB", "[SOC_SCB] OVERALL SOC SCOREBOARD VERDICT: [ALL CHECKS PASSED]", UVM_NONE)
    end
  endfunction : check_phase

endclass : soc_scoreboard

`endif // SOC_SCOREBOARD_SV
