// =============================================================================
// axi_seq_item.sv — Sequence Item Representing Complete AXI Transaction
// =============================================================================
`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

class axi_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axi_seq_item)

  string                 port_name;
  axi_xact_type_e        xact_type;
  bit [31:0]             addr;
  bit [7:0]              id;
  bit [7:0]              len;
  bit [2:0]              size;
  bit [1:0]              burst;
  bit                    lock;
  bit [3:0]              cache;
  bit [2:0]              prot;
  bit [3:0]              qos;
  bit [3:0]              region;
  bit [0:0]              user;

  bit [31:0]             data[];
  bit [3:0]              strb[];
  bit [1:0]              resp[];
  bit [1:0]              bresp;
  bit [7:0]              bid;

  time                   start_time;
  time                   end_time;
  int                    num_beats;
  bit                    completed;
  bit                    has_error;

  function new(string name = "axi_seq_item");
    super.new(name);
    xact_type = AXI_READ;
    completed = 1'b0;
    has_error = 1'b0;
    num_beats = 0;
  endfunction

  function string convert2string();
    string s;
    string type_str = (xact_type == AXI_READ) ? "READ" : "WRITE";
    string resp_str;
    case (xact_type == AXI_READ ? (resp.size() > 0 ? resp[0] : 2'b00) : bresp)
      2'b00: resp_str = "OKAY";
      2'b01: resp_str = "EXOKAY";
      2'b10: resp_str = "SLVERR";
      2'b11: resp_str = "DECERR";
    endcase

    s = $sformatf("[%s] %s ID=0x%02h Addr=0x%08h Len=%0d Size=%0d Burst=%0d Resp=%s Beats=%0d",
                  port_name, type_str, id, addr, len, size, burst, resp_str, num_beats);
    if (data.size() > 0) begin
      s = {s, $sformatf(" Data[0]=0x%08h", data[0])};
      if (xact_type == AXI_WRITE && strb.size() > 0)
        s = {s, $sformatf(" Strb[0]=0x%1h", strb[0])};
    end
    return s;
  endfunction

  function void do_copy(uvm_object rhs);
    axi_seq_item rhs_;
    if (!$cast(rhs_, rhs)) return;
    super.do_copy(rhs);
    port_name  = rhs_.port_name;
    xact_type  = rhs_.xact_type;
    addr       = rhs_.addr;
    id         = rhs_.id;
    len        = rhs_.len;
    size       = rhs_.size;
    burst      = rhs_.burst;
    lock       = rhs_.lock;
    cache      = rhs_.cache;
    prot       = rhs_.prot;
    qos        = rhs_.qos;
    region     = rhs_.region;
    user       = rhs_.user;
    data       = rhs_.data;
    strb       = rhs_.strb;
    resp       = rhs_.resp;
    bresp      = rhs_.bresp;
    bid        = rhs_.bid;
    start_time = rhs_.start_time;
    end_time   = rhs_.end_time;
    num_beats  = rhs_.num_beats;
    completed  = rhs_.completed;
    has_error  = rhs_.has_error;
  endfunction

endclass : axi_seq_item

`endif // AXI_SEQ_ITEM_SV
