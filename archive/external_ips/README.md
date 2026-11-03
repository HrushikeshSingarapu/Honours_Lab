# Archived External IP Repositories

This directory preserves upstream and unintegrated third-party IP repositories for license compliance, attribution, and reference:

1. **`aes_core-master/`**:
   - Upstream OpenCores/GitHub 128-bit AES cipher core.
   - Preserved with original BSD-style license (`LICENSE`/comments) and documentation.
   - Status: Unused by the active compression SoC (0 instantiations).

2. **`I2C/`**:
   - Upstream OpenCores/GitHub I2C master controller.
   - Preserved with original LGPL license and specification docs.
   - Status: Unused by the active compression SoC (0 instantiations).

3. **`axi-lite_uart-ipcore-develop/`**:
   - Upstream unparameterized AXI-Lite UART IP core clone.
   - Preserved with original MIT license (`LICENSE`).
   - Note: The active, parameterized, bug-fixed version with independent AW/W handshaking and `rlast` support is integrated in `Reliable_Data_Transport_System/rtl/ip/uart/` (and the SoC RTL).
