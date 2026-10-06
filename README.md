# SRAM MBIST Controller

A Verilog RTL implementation of a **Memory Built-In Self-Test (MBIST)** controller for a single-port synchronous SRAM. The project implements three March-based memory test algorithms as independent RTL variants:

- **March C-**
- **March X**
- **March Y**

All three implementations use a common MBIST datapath consisting of an FSM controller, address generator, data generator, and comparator. The algorithm-specific FSM determines the sequence of memory operations required by each March algorithm.

The three implementations are also synthesized using **Cadence Genus** to compare their area, power, timing, and control complexity.

---

## 1. Overview

Memory Built-In Self-Test (MBIST) integrates dedicated test logic around an embedded memory so that the memory can be tested using internally generated addresses, data patterns, read/write operations, and comparison logic.

This project implements three March algorithms at RTL and evaluates their behavior through simulation, fault injection, and synthesis.

### Architecture

The overall MBIST architecture is organized around four main control and datapath components:

1. **FSM Controller** — controls the March algorithm sequence and determines the required memory operation.
2. **Address Generator** — generates and updates the SRAM address according to the current March direction.
3. **Data Generator** — generates write data and the expected data used for read comparison.
4. **Comparator** — compares SRAM read data with the expected value and detects memory failures.

These blocks interface with a **single-port synchronous SRAM**.

![SRAM MBIST Controller Architecture](docs/sram_mbist_architecture.svg)

### Architecture Flow

```text
                    +--------------------------------+
                    |        MBIST Controller       |
                    |                                |
 bist_start ------->|       +----------------+       |
                    |       | FSM Controller |       |
                    |       +-------+--------+       |
                    |               |                |
                    |       +-------v--------+       |
                    |       | Address        |       |
                    |       | Generator      |       |
                    |       +-------+--------+       |
                    |               |                |
                    |       +-------v--------+       |
                    |       | Data Generator |       |
                    |       +-------+--------+       |
                    |               |                |
                    |       +-------v--------+       |
                    |       | Comparator     |<------+
                    |       +----------------+       |
                    +---------------+----------------+
                                    |
                                    | SRAM interface
                                    v
                         +-----------------------+
                         |    Single-Port SRAM   |
                         +-----------------------+
                                    |
                                    |
                              mem_dout
                                    |
                                    +------> Comparator
```

The control flow begins when `bist_start` is asserted. The FSM selects the current March operation, controls the address direction, selects the required data pattern, and determines whether the SRAM should perform a read or write operation.

During a read operation, the SRAM output is compared with the expected value. A mismatch is recorded as a test failure. When all March elements are completed, the controller asserts the completion and final test-status signals.

The architecture diagram is stored in:

```text
docs/sram_mbist_architecture.svg
```

---

## 2. Algorithms

The project implements three different March algorithms using the same overall MBIST datapath.

| Algorithm | Operations | FSM States | Main Characteristics |
|---|---:|---:|---|
| **March C-** | 10N | 12 | Broadest fault coverage among the three |
| **March X** | 6N | 8 | Lowest hardware cost and shortest critical path |
| **March Y** | 8N | 12 | Adds read-back verification after writes |

### March C-

```text
↑(w0)
↑(r0,w1)
↑(r1,w0)
↓(r0,w1)
↓(r1,w0)
↑(r0)
```

March C- uses six March elements and provides the broadest coverage of the three implementations evaluated in this project.

### March X

```text
↑(w0)
↑(r0,w1)
↓(r1,w0)
↓(r0)
```

March X uses fewer memory operations and fewer FSM states, resulting in a smaller and faster implementation.

### March Y

```text
↑(w0)
↑(r0,w1,r1)
↓(r1,w0,r0)
↓(r0)
```

March Y adds an additional read-back after the write operation in its middle March elements. This increases the amount of control and comparison logic compared with March X.

---

## 3. RTL Architecture

Each algorithm uses the same fundamental MBIST datapath, while the FSM controller changes according to the selected March algorithm.

### 3.1 FSM Controller

The FSM controller is the main control block of the MBIST design.

It determines:

- Current March element
- Read/write operation
- Address direction
- Address initialization
- Data-pattern selection
- Expected-data selection
- Test progression
- Test completion
- Pass/fail status

The FSM therefore defines the algorithmic behavior of each MBIST variant.

### 3.2 Address Generator

The address generator produces the SRAM address required by the current March operation.

It supports:

- Address initialization
- Address increment
- Address decrement
- Ascending address traversal
- Descending address traversal
- End-of-range detection

The FSM controls the direction and operation of the address generator.

### 3.3 Data Generator

The data generator produces the data pattern required by the current memory operation.

It provides:

- Write data for SRAM write operations
- Expected data for SRAM read operations

The generated pattern is selected according to the current March element.

### 3.4 Comparator

The comparator checks the SRAM output against the expected data generated by the MBIST datapath.

```text
SRAM Read Data
      |
      v
+-------------+
| Comparator  |<----- Expected Data
+------+------+
       |
       v
   Error Flag
```

If the actual SRAM data differs from the expected value, the MBIST controller records a memory failure.

### 3.5 SRAM Interface

The MBIST controller interfaces with a single-port synchronous SRAM through address, data, enable, and write-control signals.

The behavioral SRAM model is used for simulation and fault-injection experiments. It is not included in the synthesized MBIST controller logic.

---

## 4. MBIST Interface

The top-level module is:

```text
mbist_top
```

| Signal | Direction | Description |
|---|---|---|
| `clk` | Input | System clock |
| `rst_n` | Input | Active-low reset |
| `bist_start` | Input | Starts the MBIST operation |
| `bist_done` | Output | Indicates completion of the test |
| `bist_pass` | Output | Indicates the final pass/fail result |
| `mem_addr` | Output | SRAM address |
| `mem_din` | Output | Data written to SRAM |
| `mem_dout` | Input | Data read from SRAM |
| `mem_we` | Output | SRAM write enable |
| `mem_en` | Output | SRAM enable |

The general operation is:

```text
             bist_start
                  |
                  v
           +-------------+
           | MBIST FSM   |
           +------+------+
                  |
          Memory Operations
                  |
                  v
            +---------+
            |  SRAM   |
            +----+----+
                 |
              Read Data
                 |
                 v
           +-------------+
           | Comparator  |
           +------+------+
                  |
             Error Status
                  |
                  v
          bist_pass / bist_done
```

---

## 5. Repository Structure

```text
SRAM-MBIST-Controller/
│
├── march_c-/
│   ├── rtl/
│   │   ├── address_generator.v
│   │   ├── comparator.v
│   │   ├── data_generator.v
│   │   ├── fsm_controller.v
│   │   └── mbist_top.v
│   ├── sim_models/
│   │   └── memory_model.v
│   ├── tb/
│   │   └── tb_mbist.v
│   └── sim/
│       └── run.bat
│
├── march_x/
│   ├── rtl/
│   ├── sim_models/
│   ├── tb/
│   └── sim/
│
├── march_y/
│   ├── rtl/
│   ├── sim_models/
│   ├── tb/
│   └── sim/
│
├── docs/
│   ├── sram_mbist_architecture.svg
│   └── genus_reports/
│       ├── march_c-/
│       ├── march_x/
│       └── march_y/
│
├── .gitignore
└── README.md
```

The three algorithm directories follow the same organization so that their RTL, simulation models, testbenches, and simulation scripts can be evaluated consistently.

---

## 6. Simulation

Each algorithm has an independent simulation environment.

The testbench is:

```text
tb/tb_mbist.v
```

The behavioral SRAM model is:

```text
sim_models/memory_model.v
```

Simulation can be launched using:

```text
sim/run.bat
```

For example, for March C-:

```cmd
cd march_c-\sim
run.bat
```

The corresponding scripts are also available for:

```text
march_x/sim/run.bat
march_y/sim/run.bat
```

The simulation environment verifies normal MBIST operation as well as fault-injected memory behavior.

---

## 7. Fault-Injection Verification

The behavioral SRAM model provides fault-injection mechanisms for evaluating the ability of the MBIST algorithms to detect memory faults.

The verification sequence includes:

| Test | Condition | Expected Result |
|---|---|---|
| T1 | Fault-free memory | Pass |
| T2 | Mid-test stuck-at fault | Fail |
| T3 | Multiple stuck-at faults | Fail |
| T4 | Faults present before test start | Fail |
| T5 | Two consecutive fault-free runs | Pass, Pass |

The fault-injection tests are applied consistently across the three algorithm variants so that their behavior can be compared under equivalent simulation conditions.

The memory model also contains an `inject_corruption` mechanism for arbitrary single-shot corruption experiments. This mechanism is available for additional experiments but is not part of the standard verification sequence.

---

## 8. FSM Organization

The three controllers use different FSM organizations according to their March sequences.

### March C-

March C- uses 12 states, including the idle and completion states.

```text
ST_IDLE
   |
ST_M0_WR
   |
ST_M1_RD → ST_M1_WR
   |
ST_M2_RD → ST_M2_WR
   |
ST_M3_RD → ST_M3_WR
   |
ST_M4_RD → ST_M4_WR
   |
ST_M5_RD
   |
ST_DONE
```

### March X

March X uses 8 states:

```text
ST_IDLE
   |
ST_M0_WR
   |
ST_M1_RD → ST_M1_WR
   |
ST_M2_RD → ST_M2_WR
   |
ST_M3_RD
   |
ST_DONE
```

### March Y

March Y uses additional states for the read-back verification operations:

```text
ST_IDLE
   |
ST_M0_WR
   |
ST_M1_RD1 → ST_M1_WR → ST_M1_RD2 → ST_M1_CMP
   |
ST_M2_RD1 → ST_M2_WR → ST_M2_RD2 → ST_M2_CMP
   |
ST_M3_RD
   |
ST_DONE
```

The additional read-back and comparison phases are an important architectural difference between March Y and March X.

---

## 9. Cadence Genus Synthesis

The three MBIST controllers were synthesized using **Cadence Genus** with:

- `mbist_top` as the synthesis top
- 2.0 ns clock constraint
- 500 MHz target clock
- Slow process corner

The synthesized design contains the MBIST RTL datapath and controller logic. The behavioral SRAM model and simulation testbench are not part of the synthesized design.

Synthesis outputs are organized under:

```text
docs/genus_reports/
```

Each algorithm directory contains:

```text
<variant>_area.rep
<variant>_power.rep
<variant>_timing.rep
<variant>_messages.rep
<variant>_netlist.v
<variant>.sdc
mbist.sdc
run.tcl
```

---

## 10. Synthesis Results

| Metric | March C- | March X | March Y |
|---|---:|---:|---:|
| Cell Count | 94 | 82 | 118 |
| Total Area | 532.86 | 466.25 | 578.27 |
| Total Power | 85.2 µW | 77.0 µW | 171.0 µW |
| Critical Path Delay | 1721 ps | 1425 ps | 1466 ps |
| Setup Slack @ 2.0 ns | 70 ps | 416 ps | 358 ps |
| Max. Theoretical Fmax | ~581 MHz | ~702 MHz | ~682 MHz |
| Operations | 10N | 6N | 8N |
| FSM States | 12 | 8 | 12 |

### Comparison

**March X** provides the lowest implementation cost in this comparison:

- Lowest cell count
- Lowest area
- Lowest power
- Shortest critical path
- Highest theoretical Fmax

**March C-** provides broader fault coverage at the cost of additional operations and control complexity.

**March Y** performs fewer operations than March C-, but its additional read-back and comparison logic increases hardware cost and power.

These results demonstrate that the number of March operations alone does not determine hardware cost. The type of memory operation and the control logic required to implement it also affect area, power, and timing.

---

## 11. Design Scope

This repository focuses on the RTL implementation, simulation-based fault injection, and synthesis comparison of three March-based MBIST controllers for a single-port synchronous SRAM.

The SRAM used during verification is a behavioral model. The Genus results represent the synthesized MBIST controller logic rather than a physical SRAM macro.

The fault-injection experiments represent logical fault models applied to the behavioral memory model and should not be interpreted as direct measurements of physical SRAM defect coverage.

---

## 12. Tools

- **Verilog HDL** — RTL implementation
- **Cadence Genus** — logic synthesis and PPA analysis
- **Batch simulation scripts** — simulation automation
- **Behavioral SRAM model** — fault-injection verification
- **Git / GitHub** — version control and project management
