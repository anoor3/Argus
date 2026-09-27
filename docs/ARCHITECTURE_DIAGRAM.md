# ARGUS Architecture Diagram

This diagram matches the implemented RTL hierarchy under `rtl/`. The top module
is `argus_top.sv`; every box below is a real module with its own self-checking
testbench in `tb/`.

## Top-level block diagram

```
                              HOST PC
                                | UART (8-N-1)
                                v
  +--------------------------- argus_top ----------------------------------+
  |                                                                        |
  |   uart_rx ---> command_router <---> csr_bank <---> uart_tx ---> HOST   |
  |                     |  ^                ^                               |
  |                RUN_SEQ  | rd/wr         | time_now / event_count       |
  |                     v  |                |                               |
  |             test_sequencer          timebase (64-bit, shared)          |
  |                     | inject_req                                        |
  |                     v                                                   |
  |            safety_interlock --fault_active--> fault_controller --> DUT  |
  |                                                (reset/suppress/clk_en)  |
  |                                                                        |
  |   +------------------- capture_subsystem ----------------------+       |
  |   |  gpio_monitor  --\                                          |       |
  |   |  reset_monitor ---+--> event_logger --> trace_buffer -->rd  |       |
  |   |  clock_monitor --/         ^  (96b records)   (circular)    |       |
  |   |                       trigger_engine (freeze on match)      |       |
  |   +-------------------------------------------------------------+       |
  +------------------------------------------------------------------------+

  CDC primitives (cdc_sync, async_fifo) are used wherever an asynchronous DUT
  signal or a second clock domain enters the core clock domain.
```

## Module inventory (rtl/ -> tb/)

| Module               | Role                                        | Testbench                  |
|----------------------|---------------------------------------------|----------------------------|
| timebase             | shared 64-bit timestamp                     | timebase_tb                |
| csr_bank             | memory-mapped registers                     | csr_bank_tb                |
| uart_tx / uart_rx    | host serial link                            | uart_tx_tb / uart_rx_tb    |
| (loopback)           | tx<->rx integration                         | uart_loopback_tb           |
| command_router       | frame parser / dispatch                     | command_router_tb          |
| argus_core           | P1 control-plane top                        | argus_core_tb              |
| cdc_sync             | level + pulse CDC                           | cdc_sync_tb                |
| async_fifo           | dual-clock FIFO                             | async_fifo_tb              |
| gpio_monitor         | debounced edge events                       | gpio_monitor_tb            |
| reset_monitor        | reset assert/deassert + width               | reset_monitor_tb           |
| clock_monitor        | clock alive/lost                            | clock_monitor_tb           |
| trace_buffer         | circular event storage                      | trace_buffer_tb            |
| event_logger         | stamp + pack + arbitrate                    | event_logger_tb            |
| trigger_engine       | match / freeze                              | trigger_engine_tb          |
| capture_subsystem    | P2 capture integration                      | capture_subsystem_tb       |
| spi_master           | SPI exerciser                               | spi_master_tb              |
| i2c_master           | I2C exerciser                               | i2c_master_tb              |
| adc_bridge           | sensor read over SPI                        | adc_bridge_tb              |
| test_sequencer       | programmable step FSM                       | test_sequencer_tb          |
| safety_interlock     | arm/fire safety guard                       | safety_interlock_tb        |
| fault_controller     | bounded fault effects                       | fault_controller_tb        |
| argus_top            | full instrument integration                 | argus_top_tb               |

## Clock/reset domains

- One primary clock domain (`clk`) for the control plane, capture, sequencer,
  and fault subsystems.
- Asynchronous DUT inputs (`gpio_in`, `dut_rst_in`, `dut_clk_in`) enter via
  2-flop synchronizers inside their monitors; `async_fifo` is available for
  multi-bit cross-domain data.
- Reset (`rst`) is synchronous, active-high; every module returns to a defined
  benign state on reset.
