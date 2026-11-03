// =============================================================================
// vip.f — Filelist for Reusable Verification IPs
// =============================================================================
+incdir+./vip/common
+incdir+./vip/uart
+incdir+./vip/gpio
+incdir+./vip/reset
+incdir+./vip/irq
+incdir+./vip/trace

./vip/common/vip_types_pkg.sv
./vip/uart/uart_pkg.sv
./vip/uart/uart_if.sv
./vip/uart/uart_driver.sv
./vip/uart/uart_monitor.sv
./vip/uart/uart_agent.sv

./vip/gpio/gpio_pkg.sv
./vip/gpio/gpio_if.sv
./vip/gpio/gpio_pad_model.sv
./vip/gpio/gpio_driver.sv
./vip/gpio/gpio_monitor.sv
./vip/gpio/gpio_agent.sv

./vip/reset/reset_pkg.sv
./vip/reset/reset_if.sv
./vip/reset/reset_driver.sv

./vip/irq/irq_pkg.sv
./vip/irq/irq_if.sv
./vip/irq/irq_monitor.sv

./vip/trace/trace_pkg.sv
./vip/trace/trace_if.sv
./vip/trace/trace_monitor.sv

