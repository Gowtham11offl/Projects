# APB-to-I2C Bridge Controller & SystemVerilog Verification IP

A fully documented, synthesizable **APB-to-I2C Master Bridge Core** implemented in Verilog HDL and verified using an object-oriented **SystemVerilog Layered Testbench Architecture**.

---

## Table of Contents
1. [Project Overview](#1-project-overview)
2. [AMBA APB Protocol Theory](#2-amba-apb-protocol-theory)
   - [2.1 APB Bus Signals](#21-apb-bus-signals)
   - [2.2 APB State Machine & Transfer Phases](#22-apb-state-machine--transfer-phases)
   - [2.3 Write and Read Timing](#23-write-and-read-timing)
3. [I2C Protocol Theory](#3-i2c-protocol-theory)
   - [3.1 Physical Layer & Open-Drain Architecture](#31-physical-layer--open-drain-architecture)
   - [3.2 Bus Conditions (START, STOP, Repeated START)](#32-bus-conditions-start-stop-repeated-start)
   - [3.3 Bit Transmission & Data Validity](#33-bit-transmission--data-validity)
   - [3.4 Acknowledge (ACK / NACK) Timing](#34-acknowledge-ack--nack-timing)
   - [3.5 Clock Stretching Mechanism](#35-clock-stretching-mechanism)
   - [3.6 7-Bit Frame Format](#36-7-bit-frame-format)
4. [Hardware Architecture & Theory of Operation](#4-hardware-architecture--theory-of-operation)
   - [4.1 Block Diagram](#41-block-diagram)
   - [4.2 Register Map (OpenCores Specification)](#42-register-map-opencores-specification)
   - [4.3 Sub-Module: Clock Generator (`i2c_clk_gen.v`)](#43-sub-module-clock-generator-i2c_clk_genv)
   - [4.4 Sub-Module: Bit-Level Controller (`i2c_bit_cnt.v`)](#44-sub-module-bit-level-controller-i2c_bit_cntv)
   - [4.5 Sub-Module: Byte-Level Controller (`i2c_byte_cntr.v`)](#45-sub-module-byte-level-controller-i2c_byte_cntrv)
   - [4.6 Top-Level Bridge Wrapper (`apb_i2c_core.v`)](#46-top-level-bridge-wrapper-apb_i2c_corev)
   - [4.7 Behavioral Slave Device (`i2c_slave.v`)](#47-behavioral-slave-device-i2c_slavev)
5. [SystemVerilog Verification Architecture](#5-systemverilog-verification-architecture)
   - [5.1 Layered Verification Topology](#51-layered-verification-topology)
   - [5.2 Transaction Object (`apb_i2c_transaction.sv`)](#52-transaction-object-apb_i2c_transactionsv)
   - [5.3 Physical Interface (`apb_i2c_if.sv`)](#53-physical-interface-apb_i2c_ifsv)
   - [5.4 Generator (`apb_i2c_generator.sv`)](#54-generator-apb_i2c_generatorsv)
   - [5.5 Driver (`apb_i2c_driver.sv`)](#55-driver-apb_i2c_driversv)
   - [5.6 Monitor (`apb_i2c_monitor.sv`)](#56-monitor-apb_i2c_monitorsv)
   - [5.7 Scoreboard & Reference Model (`apb_i2c_scoreboard.sv`)](#57-scoreboard--reference-model-apb_i2c_scoreboardsv)
   - [5.8 Environment & Test (`apb_i2c_environment.sv`, `apb_i2c_test.sv`)](#58-environment--test-apb_i2c_environmentsv-apb_i2c_testsv)
   - [5.9 Top Testbench Module (`apb_i2c_top_tb.sv`)](#59-top-testbench-module-apb_i2c_top_tbsv)
6. [Compilation & Simulation Guide](#6-compilation--simulation-guide)

---

## 1. Project Overview

Modern SoCs frequently use ARM's **AMBA APB** (Advanced Peripheral Bus) for connecting low-bandwidth, register-mapped control peripherals. Meanwhile, the **I2C** (Inter-Integrated Circuit) bus is the industry-standard two-wire protocol used for board-level chip-to-chip communications (sensors, RTCs, EEPROMs, power management ICs).

This project designs and verifies an **APB-to-I2C Master Bridge Core**.
- **Upstream Interface:** APB3 Slave (connects to CPU memory map).
- **Downstream Interface:** I2C Master with open-drain bidirectional `SCL` and `SDA` lines.
- **Key Functions:** Prescaled clock generation, automatic START/STOP generation, serial byte serialization/deserialization, slave acknowledge capture, dynamic clock stretching detection, and auto-clearing command registers.

---

## 2. AMBA APB Protocol Theory

The Advanced Peripheral Bus (APB) is optimized for minimal power consumption and reduced interface complexity.

### 2.1 APB Bus Signals
| Signal Name | Width | Direction | Function |
|:---|:---:|:---:|:---|
| `PCLK` | 1 | Input | Rising-edge system clock synchronizing all transfers. |
| `PRESETn` | 1 | Input | Active-low asynchronous/synchronous system reset. |
| `PADDR` | 32 | Input | APB address bus driven by the Master (Host CPU). |
| `PSEL` | 1 | Input | Slave Select indicating the bridge is targeted. |
| `PENABLE` | 1 | Input | Access Phase indicator; asserted in cycle 2 of transfer. |
| `PWRITE` | 1 | Input | Transfer direction: `1` = Write (Master to Slave), `0` = Read (Slave to Master). |
| `PWDATA` | 32 | Input | Write data bus driven by the Master during writes. |
| `PRDATA` | 32 | Output | Read data bus driven by the bridge to the CPU during reads. |
| `PREADY` | 1 | Output | Handshake flag indicating slave readiness (no wait states = `1'b1`). |

### 2.2 APB State Machine & Transfer Phases
An APB transfer sequence progresses through three fundamental states:

```
  +---------+
  |  IDLE   | <---------------+
  +---------+                 |
       | (Transfer requested) |
       v                      |
  +---------+                 |
  |  SETUP  |                 |
  +---------+                 |
       | (Next clock cycle)   |
       v                      |
  +---------+                 |
  | ACCESS  | ----------------+
  +---------+ (PREADY == 1)
```

1. **IDLE:** Bus is quiescent (`PSEL = 0`, `PENABLE = 0`).
2. **SETUP Phase (Cycle 1):**
   - The master places the address on `PADDR`, write data on `PWDATA` (if write), and sets `PWRITE`.
   - `PSEL` is asserted High while `PENABLE` remains Low.
   - The bus remains in SETUP for exactly **one clock cycle**.
3. **ACCESS Phase (Cycle 2):**
   - `PENABLE` is asserted High.
   - The slave samples write data or drives read data onto `PRDATA`.
   - When the slave asserts `PREADY = 1`, the transfer completes on the rising edge of `PCLK`, returning the bus to IDLE or entering SETUP for the next transfer.

### 2.3 Write and Read Timing
- **Write:** `apb_write = PSEL & PENABLE & PWRITE & PREADY;`
- **Read:**  `apb_read  = PSEL & PENABLE & ~PWRITE & PREADY;`

Because the internal registers respond immediately without wait states, `PREADY` is tied permanently to `1'b1`.

---

## 3. I2C Protocol Theory

I2C is a multi-master, multi-slave, single-ended, serial computer bus invented by Philips Semiconductors (NXP).

### 3.1 Physical Layer & Open-Drain Architecture
- I2C utilizes only **two bidirectional lines**:
  - `SCL` (Serial Clock)
  - `SDA` (Serial Data)
- Both lines are configured as **Open-Drain (or Open-Collector)** with external pull-up resistors ($R_p \approx 1.5\text{ k}\Omega \text{ to } 4.7\text{ k}\Omega$) connected to $V_{DD}$.
- **Wired-AND property:**
  - A device can only pull the wire **Low** (drive `0` to GND).
  - A device **cannot** actively drive High (`1`). To output a `1`, it releases the line into high-impedance (`1'bz`), and the pull-up resistor pulls the voltage up to $V_{DD}$.
  - This eliminates direct bus contention/short-circuits when multiple devices drive the lines simultaneously.

```verilog
assign scl = (scl_oen == 1'b0) ? 1'b0 : 1'bz;
assign sda = (sda_oen == 1'b0) ? 1'b0 : 1'bz;
```

### 3.2 Bus Conditions (START, STOP, Repeated START)
Under normal data transmission, **SDA must remain stable while SCL is High**. Transitions on SDA while SCL is High are reserved exclusively for control conditions:

1. **START Condition (S):**
   - High-to-Low transition on `SDA` while `SCL` is **High**.
   - Signals to all slaves on the bus that a transmission is beginning.
2. **STOP Condition (P):**
   - Low-to-High transition on `SDA` while `SCL` is **High**.
   - Releases the bus back to the idle state.
3. **Repeated START Condition (Sr):**
   - A new START condition generated without an intermediate STOP condition.
   - Allows the master to switch transfer directions (e.g., from write-address to read-data) while retaining bus ownership.

```
SCL:  ~~~~~~~\______/~~~~~~~\______/~~~~~~~~~~~~~~~~~~~~
SDA:  ~~~\________________________________/~~~~~~~~~~~~~
         ^ START                       ^ STOP
      (SDA falls while              (SDA rises while
         SCL is High)                  SCL is High)
```

### 3.3 Bit Transmission & Data Validity
- **Setup Window (SCL Low):** SDA is permitted to change state.
- **Sample Window (SCL High):** SDA must remain stable. Slaves and masters sample the bit value.

### 3.4 Acknowledge (ACK / NACK) Timing
Every byte transferred across the I2C bus consists of **8 data bits followed by a 9th Acknowledge clock pulse**:
- The transmitter releases the `SDA` line (`1'bz`).
- The receiver pulls `SDA` **Low** to send an **ACK** (`0`).
- If the receiver leaves `SDA` **High**, it indicates a **NACK** (`1`) (e.g., slave address not matched, device busy, or end of read stream).

### 3.5 Clock Stretching Mechanism
If a slave device needs extra time to process data (or service an interrupt before sending the next byte):
- The slave pulls `SCL` **Low**.
- When the master Bit Controller releases `SCL` to float High (`scl_out == 1'b1`), the sampled feedback voltage (`scl_in`) remains `0`.
- The Clock Generator detects this stretch (`clk_stretch_active = scl_out & ~scl_in`), pauses its internal down-counter, and halts `clk_en` pulses until the slave releases `SCL`.

### 3.6 7-Bit Frame Format
A complete I2C byte frame consists of:
```
+---+--------------------+-----+-----+--------------------+-----+---+
| S | Slave Address[6:0] | R/W | ACK |    Data Byte[7:0]  | ACK | P |
+---+--------------------+-----+-----+--------------------+-----+---+
```
- `R/W = 0`: Master writes data to Slave.
- `R/W = 1`: Master reads data from Slave.

---

## 4. Hardware Architecture & Theory of Operation

### 4.1 Block Diagram

```
                 +-------------------------------------------------------+
                 |                     apb_i2c_core                      |
                 |                                                       |
APB Master ----> | APB Address Decoder & Registers                       |
(PCLK, PRESETn,  | (PRER_LO, PRER_HI, CTR, TXR, RXR, CR, SR)             |
 PADDR, PWDATA,  +-------------------------------------------------------+
 PRDATA, etc.)        |              |                      |
                      |              |                      |
                      v              v                      v
               +-------------+ +---------------+ +--------------------+
               | i2c_clk_gen | | i2c_byte_cntr | |    i2c_bit_cntr    |
               | (Prescaler) | | (Byte FSM &   | | (4-Phase Bit FSM & |
               |             | |  Shift Regs)  | |  Pin Controllers)  |
               +-------------+ +---------------+ +--------------------+
                      | clk_en       | bit_cmd              | scl_oen
                      +--------------+                      | sda_oen
                                                            v
                                                   Physical SCL / SDA (Open-Drain)
```

### 4.2 Register Map (OpenCores Specification)
The core maps into 5 distinct 8-bit register locations:

| Offset | Name | Access | Reset | Description |
|:---|:---|:---:|:---:|:---|
| `0x00` | `PRER_LO` | R/W | `0xFF` | Clock Prescaler Low-Byte (Divisor bits [7:0]) |
| `0x01` | `PRER_HI` | R/W | `0xFF` | Clock Prescaler High-Byte (Divisor bits [15:8]) |
| `0x02` | `CTR` | R/W | `0x00` | Core Control Register (`Bit 7`: Core Enable `EN`, `Bit 6`: Interrupt Enable `IEN`) |
| `0x03` | `TXR` | Write | `0x00` | Transmit Data Register (holds byte to serialize onto bus) |
| `0x03` | `RXR` | Read | `0x00` | Receive Data Register (holds byte received from bus) |
| `0x04` | `CR` | Write | `0x00` | Command Register (`STA`, `STO`, `RD`, `WR`, `ACK`) |
| `0x04` | `SR` | Read | `0x00` | Status Register (`RxACK`, `Busy`, `TIP`, `IF`) |

#### Command Register (`CR`) Bit Mapping (Write Only):
- `CR[7]` = **STA**: Generate START condition.
- `CR[6]` = **STO**: Generate STOP condition.
- `CR[5]` = **RD**: Read from slave.
- `CR[4]` = **WR**: Write to slave.
- `CR[3]` = **ACK**: Master ACK control when reading (`0` = send ACK, `1` = send NACK).
- **Auto-Clearing Feature:** Once the Byte Controller executes the transfer, `byte_ack` pulses High for 1 cycle, and the core hardware resets `CR[7:4]` back to `4'b0000` to prevent unintended repetitive execution.

#### Status Register (`SR`) Bit Mapping (Read Only):
- `SR[7]` = **RxACK**: Received ACK status from slave (`0` = ACK received, `1` = NACK received).
- `SR[6]` = **Busy**: I2C bus busy (`1` = active transfer on bus, `0` = bus idle).
- `SR[5:2]` = **Reserved**: Reads back `4'b0000`.
- `SR[1]` = **TIP**: Transfer In Progress (`1` = active serialization/deserialization).
- `SR[0]` = **IF**: Interrupt Flag (pulsed `1` when byte transfer completes).

---

### 4.3 Sub-Module: Clock Generator (`i2c_clk_gen.v`)
- Divides the high-frequency system clock (`PCLK`) down to an enable tick (`clk_en`).
- **Timing Tick Formula:**
  $$\text{Period}(clk\_en) = (prescale + 1) \times T_{PCLK}$$
  Since an I2C bit clock cycle requires 4 phases (A, B, C, D), the actual generated I2C bus clock frequency is:
  $$F_{SCL} = \frac{F_{PCLK}}{4 \times (prescale + 1)}$$
- **Clock Stretching Support:**
  Continuously monitors `clk_stretch_active = (scl_out == 1'b1) && (scl_in == 1'b0)`. If true, the down-counter stalls and `clk_en` remains Low.

---

### 4.4 Sub-Module: Bit-Level Controller (`i2c_bit_cnt.v`)
Executes individual physical bit operations using a **4-Phase State Machine**:
- **Phase A (Setup):** `SCL` pulled Low (`scl_oen = 0`). `SDA` placed with command value (`din` for Write, `High-Z` for Read/START).
- **Phase B (Delay):** `SCL` released High (`scl_oen = 1`). START/STOP conditions setup.
- **Phase C (Sample):** `SCL` held High. For READ operations, `dout <= sda_in` samples the line.
- **Phase D (Hold):** Bit terminates, `cmd_ack` pulses High, `SCL` pulled Low to prepare for next bit.

---

### 4.5 Sub-Module: Byte-Level Controller (`i2c_byte_cntr.v`)
Manages the end-to-end byte transfer through a **6-State FSM**:
1. `state_idle`: Waits for CPU to write to Command Register (`CR`).
2. `state_start`: Commands Bit Controller to execute a START condition.
3. `state_data`: Counts 8 bit iterations (MSB first, bit 7 down to 0). Shifts outgoing bits or shifts in incoming bits.
4. `state_ack`: Exchanges the 9th bit. Writes slave ACK or samples master ACK.
5. `state_stop`: Commands Bit Controller to generate STOP condition (if `CR[6] == 1`).
6. `state_done`: Generates `cmd_ack` pulse to clear command bits in top-level register.

---

### 4.6 Top-Level Bridge Wrapper (`apb_i2c_core.v`)
- Interconnects the register map, Clock Generator, Byte Controller, and Bit Controller.
- Manages bidirectional open-drain driving and voltage sampling for `scl` and `sda`.
- Implements synchronous address decoding and read multiplexing for zero-wait APB transfers.

---

### 4.7 Behavioral Slave Device (`i2c_slave.v`)
Emulates an external hardware peripheral on the I2C bus:
- **Metastability Protection:** 3-stage shift register synchronizers (`scl_sync`, `sda_sync`) sample the asynchronous wires into the 50 MHz domain.
- **Asynchronous Edge & Condition Detectors:**
  - `scl_rising`, `scl_falling`
  - `start_detect`: `SCL` High while `SDA` falls.
  - `stop_detect`: `SCL` High while `SDA` rises.
- **Address Filter:** Compares received address against configured parameter `MY_ADDR` (`7'h5A`). Automatically drives `SDA` Low (ACK) when matched.

---

## 5. SystemVerilog Verification Architecture

The testbench is structured following modern **Universal Verification Methodology (UVM) / Layered Testbench Principles**:

```
+-------------------------------------------------------------------------+
|                              apb_i2c_test                               |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  |                          apb_environment                          |  |
|  |                                                                   |  |
|  |  +-----------------+                +--------------------------+  |  |
|  |  |  apb_generator  |                |      apb_scoreboard      |  |  |
|  |  +-----------------+                | (Golden Reference Model) |  |  |
|  |           | gen2drv                 +--------------------------+  |  |
|  |           v                                      ^ mon2scb        |  |
|  |  +-----------------+                             |                |  |
|  |  |   apb_driver    |                    +------------------+      |  |
|  |  +-----------------+                    |   apb_monitor    |      |  |
|  |           | vif                                  | vif            |  |
|  +-----------|--------------------------------------|----------------+  |
|              |                                      |                   |
+--------------|--------------------------------------|-------------------+
               v                                      ^
    ======================================================
               apb_i2c_if (SystemVerilog Interface)
    ======================================================
               |                                      |
               v                                      v
        +--------------+                       +--------------+
        |     DUT      | <=== SCL / SDA =====> |   SLAVE      |
        | apb_i2c_core |                       |  i2c_slave   |
        +--------------+                       +--------------+
```

### 5.1 Layered Verification Topology
- **Transaction-Level Modeling (TLM):** Components communicate via SystemVerilog `mailbox #(apb_transaction)` rather than physical pins.
- **Pin Wiggling Isolation:** Only the Driver and Monitor interface with the physical wires through the `virtual apb_i2c_if`.

### 5.2 Transaction Object (`apb_i2c_transaction.sv`)
- Data container encapsulating APB stimulus fields:
  - `rand bit [2:0] addr;`
  - `rand bit [7:0] data;`
  - `rand bit       write;`
- **Constraint Solver Rule:**
  ```systemverilog
  constraint valid_address { addr inside {[3'd0:3'd4]}; }
  ```
- Contains formatted display method `display()` for transcript logging.

### 5.3 Physical Interface (`apb_i2c_if.sv`)
- Bundles all APB synchronous signals (`PCLK`, `PRESETn`, `PADDR`, `PSEL`, `PENABLE`, `PWRITE`, `PWDATA`, `PRDATA`, `PREADY`).
- Declares open-drain pull-up bus wires using SystemVerilog net type `tri1 scl; tri1 sda;` (automatically resolves to logic High when un-driven).

### 5.4 Generator (`apb_i2c_generator.sv`)
- Creates transaction objects in a controlled loop (`count = 10`).
- Invokes `.randomize()` to solve constraints and pushes items into the `gen2drv` mailbox.

### 5.5 Driver (`apb_i2c_driver.sv`)
- Retrieves transactions from `gen2drv` mailbox.
- Emulates an APB Master:
  1. Drives Address, Data, and Control with `PSEL = 1, PENABLE = 0` (**Setup Phase**).
  2. Asserts `PENABLE = 1` (**Access Phase**) on the subsequent cycle and polls `PREADY`.
  3. Captures read response (`PRDATA`) on reads.
  4. De-asserts controls back to IDLE.

### 5.6 Monitor (`apb_i2c_monitor.sv`)
- Passively watches the interface on every `posedge PCLK`.
- Samples transfer attributes whenever `PSEL & PENABLE & PREADY` are active.
- Forwards observed transactions to the Scoreboard via `mon2scb` mailbox.

### 5.7 Scoreboard & Reference Model (`apb_i2c_scoreboard.sv`)
- Implements an independent golden memory model:
  ```systemverilog
  bit [7:0] expected_regs [0:2];
  ```
- **Reset State Verification:** Preloaded with reset defaults (`0xFF`, `0xFF`, `0x00`).
- **Dynamic Check:**
  - On **Write**: Updates reference model entry `expected_regs[addr] <= data`.
  - On **Read**: Compares actual `tr.data` returned from DUT against golden entry `expected_regs[addr]`.
  - Automatically increments `pass_count` or reports `$error` and increments `fail_count`.
- Generates comprehensive end-of-test summary report.

### 5.8 Environment & Test (`apb_i2c_environment.sv`, `apb_i2c_test.sv`)
- **Environment:** Instantiates mailboxes, components, and executes them concurrently using `fork...join_none`. Waits for `driver.done`, synchronizes trailing cycles, and disables background tasks (`disable fork`).
- **Test:** Top-level class instantiating the environment and invoking `run_test()`.

### 5.9 Top Testbench Module (`apb_i2c_top_tb.sv`)
- Generates 50 MHz clock (`always #10 apb.PCLK = ~apb.PCLK;`).
- Manages 5-cycle reset assertion and release sequence.
- Instantiates `apb_i2c_if`, `apb_i2c_core` (DUT), and `i2c_slave` (Slave Model).
- Launches the test class and handles `$finish`.

---
