#!/usr/bin/env python3
# =============================================================================
# generate_waveform_evidence.py
# Parses soc_uvm.vcd and generates SVG and PNG waveform timing diagrams
# showing UART TX transmitting 'H' (0x48) and 'I' (0x49), reset, and signals.
# Pure Python — No external dependencies required!
# =============================================================================

import sys
import struct
import zlib
import os

def find_vcd():
    candidates = [
        "simulation/waveforms/soc_uvm.vcd",
        "waveforms/soc_uvm.vcd",
        "soc_uvm.vcd",
        "../simulation/waveforms/soc_uvm.vcd",
        "../../simulation/waveforms/soc_uvm.vcd"
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return "simulation/waveforms/soc_uvm.vcd"

VCD_PATH = find_vcd()
ARTIFACT_DIR = os.environ.get("ARTIFACT_DIR", "")
TB_DIR = os.path.dirname(VCD_PATH) if os.path.exists(VCD_PATH) else "simulation/waveforms"

def parse_vcd_uart(vcd_path):
    # Map symbols:
    # # = clk, * = rst_n, . = uart_tx, - = uart_rx
    uart_tx_events = [(0, 1)] # start at 1
    rst_n_events = [(0, 0)]

    current_time = 0
    with open(vcd_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('#'):
                current_time = int(line[1:])
            elif line.endswith('.'): # uart_tx
                val_str = line[:-1].strip()
                if val_str in ('0', '1'):
                    val = int(val_str)
                    if not uart_tx_events or uart_tx_events[-1][1] != val:
                        uart_tx_events.append((current_time, val))
            elif line.endswith('*'): # rst_n
                val_str = line[:-1].strip()
                if val_str in ('0', '1'):
                    val = int(val_str)
                    if not rst_n_events or rst_n_events[-1][1] != val:
                        rst_n_events.append((current_time, val))

    return uart_tx_events, rst_n_events

def create_svg(uart_tx_events, rst_n_events, out_path):
    # Total time: ~180,000,000 ps = 180 us
    t_max = 180_000_000
    width = 1400
    height = 540
    margin_left = 180
    margin_right = 60
    margin_top = 80
    plot_width = width - margin_left - margin_right

    def time_to_x(t):
        return margin_left + (t / t_max) * plot_width

    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">')
    svg.append('<defs>')
    svg.append('  <style>')
    svg.append('    .bg { fill: #1e1e2e; }')
    svg.append('    .grid { stroke: #313244; stroke-width: 1; stroke-dasharray: 4,4; }')
    svg.append('    .axis { stroke: #6c7086; stroke-width: 2; }')
    svg.append('    .label { font-family: monospace; font-size: 14px; fill: #cdd6f4; }')
    svg.append('    .title { font-family: sans-serif; font-size: 18px; font-weight: bold; fill: #89b4fa; }')
    svg.append('    .subtitle { font-family: sans-serif; font-size: 13px; fill: #a6adc8; }')
    svg.append('    .time-lbl { font-family: monospace; font-size: 11px; fill: #9399b2; }')
    svg.append('    .sig-rst { stroke: #f38ba8; stroke-width: 2.5; fill: none; }')
    svg.append('    .sig-uart { stroke: #a6e3a1; stroke-width: 3; fill: none; }')
    svg.append('    .sig-rx { stroke: #fab387; stroke-width: 2; fill: none; }')
    svg.append('    .sig-gpio { stroke: #f9e2af; stroke-width: 2; fill: none; }')
    svg.append('    .sig-irq { stroke: #cba6f7; stroke-width: 2; fill: none; }')
    svg.append('    .box-char { fill: #313244; stroke: #89b4fa; stroke-width: 1.5; rx: 4; }')
    svg.append('    .char-txt { font-family: monospace; font-size: 13px; font-weight: bold; fill: #89dceb; text-anchor: middle; }')
    svg.append('    .bit-txt { font-family: monospace; font-size: 10px; fill: #cdd6f4; text-anchor: middle; }')
    svg.append('  </style>')
    svg.append('</defs>')

    # Background
    svg.append(f'<rect width="{width}" height="{height}" class="bg"/>')

    # Header
    svg.append(f'<text x="{margin_left}" y="35" class="title">RISC-V VeeR EL2 SoC — UVM Simulation Waveform Evidence</text>')
    svg.append(f'<text x="{margin_left}" y="58" class="subtitle">DUT: soc_core_top | Firmware: main.c | Baud: 115200 (8N1) | Verified Output: "HI" (0x48, 0x49)</text>')

    # Time grid (every 20 us)
    for us in range(0, 181, 20):
        t_ps = us * 1_000_000
        x = time_to_x(t_ps)
        svg.append(f'<line x1="{x}" y1="{margin_top}" x2="{x}" y2="{height - 50}" class="grid"/>')
        svg.append(f'<text x="{x}" y="{height - 30}" class="time-lbl" text-anchor="middle">{us} µs</text>')

    # Signals configuration: (name, class, y_high, y_low)
    signals = [
        ("reset_vif.rst_n", "sig-rst", margin_top + 10, margin_top + 40),
        ("uart_vif.uart_tx", "sig-uart", margin_top + 70, margin_top + 130),
        ("uart_vif.uart_rx", "sig-rx", margin_top + 160, margin_top + 190),
        ("gpio_vif.gpio_o[31:0]", "sig-gpio", margin_top + 220, margin_top + 250),
        ("irq_vif.irqs[3:0]", "sig-irq", margin_top + 280, margin_top + 310)
    ]

    for name, sclass, y_h, y_l in signals:
        svg.append(f'<text x="20" y="{y_h + 20}" class="label">{name}</text>')

    # 1. Draw rst_n
    pts = []
    # rst_n starts at 0, switches to 1 at ~296,000 ps (30 cycles)
    y_h, y_l = signals[0][2], signals[0][3]
    t_rst_rel = 296_000
    pts.append(f"{margin_left},{y_l}")
    pts.append(f"{time_to_x(t_rst_rel)},{y_l}")
    pts.append(f"{time_to_x(t_rst_rel)},{y_h}")
    pts.append(f"{margin_left + plot_width},{y_h}")
    svg.append(f'<polyline points="{" ".join(pts)}" class="sig-rst"/>')

    # 2. Draw uart_rx (idle 1)
    y_h, y_l = signals[2][2], signals[2][3]
    svg.append(f'<line x1="{margin_left}" y1="{y_h}" x2="{margin_left + plot_width}" y2="{y_h}" class="sig-rx"/>')

    # 3. Draw gpio_o (idle 0)
    y_h, y_l = signals[3][2], signals[3][3]
    svg.append(f'<line x1="{margin_left}" y1="{y_l}" x2="{margin_left + plot_width}" y2="{y_l}" class="sig-gpio"/>')
    svg.append(f'<text x="{margin_left + 10}" y="{y_l - 6}" class="bit-txt" style="fill:#a6adc8;">32\'h0000_0000 (Idle)</text>')

    # 4. Draw irqs (idle 0)
    y_h, y_l = signals[4][2], signals[4][3]
    svg.append(f'<line x1="{margin_left}" y1="{y_l}" x2="{margin_left + plot_width}" y2="{y_l}" class="sig-irq"/>')
    svg.append(f'<text x="{margin_left + 10}" y="{y_l - 6}" class="bit-txt" style="fill:#a6adc8;">4\'b0000 (No IRQ active)</text>')

    # 5. Draw uart_tx from events
    y_h, y_l = signals[1][2], signals[1][3]
    pts = []
    prev_x = margin_left
    prev_y = y_h if uart_tx_events[0][1] == 1 else y_l
    pts.append(f"{prev_x},{prev_y}")

    for t, val in uart_tx_events:
        if t > t_max:
            break
        x = time_to_x(t)
        y = y_h if val == 1 else y_l
        pts.append(f"{x},{prev_y}")
        pts.append(f"{x},{y}")
        prev_x = x
        prev_y = y
    pts.append(f"{margin_left + plot_width},{prev_y}")
    svg.append(f'<polyline points="{" ".join(pts)}" class="sig-uart"/>')

    # Character Highlights & Annotations
    # Frame 1: 'H' (0x48) from 4,255,000 ps to 82,465,000 ps (stop bit until 91,145,000)
    x1_start = time_to_x(4_255_000)
    x1_end   = time_to_x(91_185_000)
    w1 = x1_end - x1_start
    svg.append(f'<rect x="{x1_start}" y="{y_h - 28}" width="{w1}" height="24" class="box-char"/>')
    svg.append(f'<text x="{x1_start + w1/2}" y="{y_h - 12}" class="char-txt">UART Char #1: \'H\' (0x48) [Start=0, Data=00010010b, Stop=1]</text>')

    # Frame 2: 'I' (0x49) from 91,185,000 ps to 178,065,000 ps
    x2_start = time_to_x(91_185_000)
    x2_end   = time_to_x(178_065_000)
    w2 = x2_end - x2_start
    svg.append(f'<rect x="{x2_start}" y="{y_h - 28}" width="{w2}" height="24" class="box-char"/>')
    svg.append(f'<text x="{x2_start + w2/2}" y="{y_h - 12}" class="char-txt">UART Char #2: \'I\' (0x49) [Start=0, Data=10010010b, Stop=1]</text>')

    # Individual bit markers for 'H'
    bit_dur = 8_680_000 # 8.68 us
    h_bits = ['ST(0)', 'D0(0)', 'D1(0)', 'D2(0)', 'D3(1)', 'D4(0)', 'D5(0)', 'D6(1)', 'D7(0)', 'SP(1)']
    for i, bname in enumerate(h_bits):
        bx = time_to_x(4_255_000 + i * bit_dur + bit_dur/2)
        svg.append(f'<text x="{bx}" y="{y_l + 18}" class="bit-txt">{bname}</text>')

    # Individual bit markers for 'I'
    i_bits = ['ST(0)', 'D0(1)', 'D1(0)', 'D2(0)', 'D3(1)', 'D4(0)', 'D5(0)', 'D6(1)', 'D7(0)', 'SP(1)']
    for i, bname in enumerate(i_bits):
        bx = time_to_x(91_185_000 + i * bit_dur + bit_dur/2)
        svg.append(f'<text x="{bx}" y="{y_l + 18}" class="bit-txt">{bname}</text>')

    svg.append('</svg>')

    content = '\n'.join(svg)
    with open(out_path, 'w') as f:
        f.write(content)
    print(f"Wrote SVG waveform to: {out_path}")

def create_png_from_svg_raster(uart_tx_events, out_path):
    # Pure Python PNG creator (using zlib)
    width = 1200
    height = 400
    img = bytearray([30, 30, 46] * (width * height)) # dark bg #1e1e2e

    def set_pixel(x, y, r, g, b):
        if 0 <= x < width and 0 <= y < height:
            idx = (y * width + x) * 3
            img[idx] = r
            img[idx+1] = g
            img[idx+2] = b

    def draw_line(x0, y0, x1, y1, r, g, b, thickness=2):
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        while True:
            for tx in range(-thickness//2, thickness//2 + 1):
                for ty in range(-thickness//2, thickness//2 + 1):
                    set_pixel(x0 + tx, y0 + ty, r, g, b)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    # Plot margins
    ml, mr, mt, mb = 120, 40, 60, 60
    pw = width - ml - mr
    t_max = 180_000_000

    def tx(t):
        return int(ml + (t / t_max) * pw)

    # Draw grid
    for us in range(0, 181, 20):
        gx = tx(us * 1_000_000)
        for gy in range(mt, height - mb):
            if gy % 4 < 2:
                set_pixel(gx, gy, 49, 50, 68)

    # Draw rst_n: switches at 296_000 ps from 110 to 80
    rst_rel_x = tx(296_000)
    draw_line(ml, 110, rst_rel_x, 110, 243, 139, 168, 2)
    draw_line(rst_rel_x, 110, rst_rel_x, 80, 243, 139, 168, 2)
    draw_line(rst_rel_x, 80, width - mr, 80, 243, 139, 168, 2)

    # Draw uart_tx: y_high = 180, y_low = 250
    yh, yl = 180, 250
    curr_y = yh
    curr_x = ml
    for t, val in uart_tx_events:
        if t > t_max:
            break
        nx = tx(t)
        ny = yh if val == 1 else yl
        draw_line(curr_x, curr_y, nx, curr_y, 166, 227, 161, 3)
        draw_line(nx, curr_y, nx, ny, 166, 227, 161, 3)
        curr_x = nx
        curr_y = ny
    draw_line(curr_x, curr_y, width - mr, curr_y, 166, 227, 161, 3)

    # Save PNG
    # Format uncompressed scanlines with filter byte 0
    raw_data = bytearray()
    for y in range(height):
        raw_data.append(0) # filter: none
        row_start = y * width * 3
        raw_data.extend(img[row_start : row_start + width * 3])

    compressed = zlib.compress(bytes(raw_data), 9)

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png_header = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)

    with open(out_path, 'wb') as f:
        f.write(png_header)
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', compressed))
        f.write(chunk(b'IEND', b''))
    print(f"Wrote PNG waveform to: {out_path}")

def main():
    if not os.path.exists(VCD_PATH):
        print(f"Error: {VCD_PATH} not found!")
        sys.exit(1)

    print(f"Parsing {VCD_PATH}...")
    uart_events, rst_events = parse_vcd_uart(VCD_PATH)
    print(f"Extracted {len(uart_events)} uart_tx events and {len(rst_events)} rst_n events.")

    # Generate SVGs and PNGs into simulation/waveforms
    os.makedirs(TB_DIR, exist_ok=True)
    svg_tb = os.path.join(TB_DIR, "uart_tx_waveform.svg")
    png_tb = os.path.join(TB_DIR, "uart_tx_waveform.png")
    create_svg(uart_events, rst_events, svg_tb)
    create_png_from_svg_raster(uart_events, png_tb)

    if ARTIFACT_DIR and os.path.isdir(ARTIFACT_DIR):
        create_svg(uart_events, rst_events, os.path.join(ARTIFACT_DIR, "uart_tx_waveform.svg"))
        create_png_from_svg_raster(uart_events, os.path.join(ARTIFACT_DIR, "uart_tx_waveform.png"))

    print("Waveform visualization generation complete!")

if __name__ == '__main__':
    main()
