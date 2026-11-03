// =============================================================================
// gpio_pad_model.sv — Bidirectional Tri-State Pad and Contention Model
// =============================================================================
`timescale 1ns/1ps

module gpio_pad_model (
    gpio_if.monitor_mp vif,
    output logic [31:0] resolved_gpio_i,
    input  logic [31:0] ext_drive_val,
    input  logic [31:0] ext_drive_en
);
    import vip_types_pkg::*;
    import gpio_pkg::*;

    gpio_config_t cfg;
    int contention_count = 0;

    initial begin
        cfg = get_default_gpio_config();
    end

    function void set_config(gpio_config_t new_cfg);
        cfg = new_cfg;
    endfunction

    // Tri-state resolution per bit
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : gen_pads
            wire pull_val = (cfg.default_pull == GPIO_PULL_UP)   ? 1'b1 :
                            (cfg.default_pull == GPIO_PULL_DOWN) ? 1'b0 : 1'bz;

            // DUT driver
            assign vif.gpio_pad[i] = vif.gpio_oe[i] ? vif.gpio_o[i] : 1'bz;

            // External driver
            assign vif.gpio_pad[i] = ext_drive_en[i] ? ext_drive_val[i] : pull_val;

            // Resolved input back to DUT
            assign resolved_gpio_i[i] = (vif.gpio_pad[i] === 1'b1) ? 1'b1 :
                                        (vif.gpio_pad[i] === 1'b0) ? 1'b0 : 1'b0;
        end
    endgenerate

    // Contention Monitor
    always @(posedge vif.clk) begin
        if (vif.rst_n && cfg.enable_contention_check) begin
            for (int pin = 0; pin < 32; pin++) begin
                if (vif.gpio_oe[pin] && ext_drive_en[pin]) begin
                    if (vif.gpio_o[pin] !== ext_drive_val[pin]) begin
                        contention_count <= contention_count + 1;
                        $display("[%0t ns] [GPIO VIP WARNING] Bus contention detected on Pin %0d! DUT drives %b, External drives %b",
                                 $time, pin, vif.gpio_o[pin], ext_drive_val[pin]);
                    end
                end
            end
        end
    end

endmodule: gpio_pad_model

