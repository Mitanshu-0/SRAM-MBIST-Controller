# SRAM MBIST Controller

A Verilog RTL implementation of a Memory Built-In Self-Test (MBIST) controller for a single-port synchronous SRAM, with three March-based test algorithms implemented as independent controller variants:

- **March C-**
- **March X**
- **March Y**

The project uses a common MBIST datapath for address generation, test-data generation, and comparison, while the algorithm-specific FSM determines the sequence of memory operations. The three implementations are also synthesized using Cadence Genus to compare their hardware cost and timing.

---

## 1. Overview

Memory Built-In Self-Test (MBIST) provides on-chip logic for testing embedded memories without requiring an external tester to generate every memory operation.

This project implements three March algorithms at RTL and evaluates them using the same basic MBIST datapath:

```text
                +----------------------+
                |    MBIST Controller  |
                |                      |
                |  +----------------+  |
bist_start --->|  | FSM Controller  |  |
                |  +-------+--------+  |
                |          |           |
                |  +-------v--------+  |
                |  | Address        |  |
                |  | Generator      |  |
                |  +-------+--------+  |
                |          |           |
                |  +-------v--------+  |
                |  | Data Generator |  |
                |  +-------+--------+  |
                |          |           |
                |  +-------v--------+  |
                |  | Comparator     |  |
                |  +----------------+  |
                +----------+-----------+
                           |
                           v
                    Single-Port SRAM
```

The architecture diagram used in this repository is available at:

`docs/sram_mbist_architecture.svg`

![SRAM MBIST Controller Architecture](docs/sram_mbist_architecture.svg)

---

## 2. Algorithms

The project implements three different March algorithms using the same overall datapath.

| Algorithm | Operations | FSM States | Main Characteristics |
|---|---:|---:|---|
| **March C-** | 10N | 12 | Broadest fault coverage among the three |
| **March X** | 6N | 8 | Lowest hardware cost and shortest critical path |
| **March Y** | 8N | 12 | Adds read-back verification after writes |

### March C-

```text
↑(w0);
↑(r0,w1);
↑(r1,w0);
↓(r0,w1);
↓(r1,w0);
↑(r0)
```

March C- uses six March elements and provides the broadest coverage of the three implementations evaluated in this project.

### March X

```text
↑(w0);
↑(r0,w1);
↓(r1,w0);
↓(r0)
```

March X uses fewer memory operations and fewer FSM states, resulting in a smaller and faster implementation.

### March Y

```text
↑(w0);
↑(r0,w1,r1);
↓(r1,w0,r0);
↓(r0)
```

March Y adds an additional read-back after the write operation in its middle March elements. This increases the amount of control and comparison logic compared with March X.

---

## 3. RTL Architecture

Each algorithm uses the same basic MBIST datapath.

### Address Generator

The address generator produces the SRAM address and supports the required ascending and descending address traversal.

It is controlled by the algorithm-specific FSM and provides:

- Address loading
- Address increment
- Address decrement
- Address-direction control

### Data Generator

The data generator produces:

- Data written to SRAM
- Expected data used during read comparisons

The generated patterns depend on the current March operation.

### Comparator

The comparator checks the SRAM read data against the expected value.

A mismatch produces a comparison error that is used by the MBIST controller to determine the test result.

### FSM Controller

The FSM controller is the algorithm-specific part of the design.

It controls:

- SRAM read/write operations
- Address direction
- Address loading
- Data-pattern selection
- Expected-data selection
- March-element sequencing
- Test completion
- Pass/fail status

The datapath remains structurally similar across all three variants, while the FSM implements the corresponding March sequence.

---

## 4. MBIST Interface

The top-level module is `mbist_top`.

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

The behavioral SRAM model is used for simulation and is not part of the synthesized MBIST controller.

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

The three algorithm directories are intentionally organized in the same way so that their RTL, simulation models, testbenches, and simulation scripts can be compared consistently.

---

## 6. Simulation

Each algorithm has its own simulation environment.

The testbench is:

```text
tb/tb_mbist.v
```

and the behavioral SRAM model is:

```text
sim_models/memory_model.v
```

The simulation can be launched using the corresponding batch script:

```text
sim/run.bat
```

For example, from the March C- directory:

```cmd
cd march_c-\sim
run.bat
```

The same procedure can be used for:

```text
march_x/sim/run.bat
march_y/sim/run.bat
```

The simulation environment verifies both normal memory operation and fault-injected cases.

---

## 7. Fault-Injection Verification

The behavioral SRAM model provides fault-injection mechanisms for testing the MBIST controller.

The verification sequence includes:

| Test | Condition | Expected Result |
|---|---|---|
| T1 | Fault-free memory | Pass |
| T2 | Mid-test stuck-at fault | Fail |
| T3 | Multiple stuck-at faults | Fail |
| T4 | Faults present before test start | Fail |
| T5 | Two consecutive fault-free runs | Pass, Pass |

The fault-injection tests are applied consistently across the three algorithm variants so their behavior can be compared under the same simulation conditions.

The memory model also contains an `inject_corruption` mechanism for arbitrary single-shot corruption experiments, although it is not currently exercised by the standard test sequence.

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

These results demonstrate that **the number of March operations alone does not determine hardware cost**. The type of operation and the control logic required to implement it also affect area, power, and timing.

---

## 11. Design Scope

This repository focuses on the RTL implementation, simulation-based fault injection, and synthesis comparison of three March-based MBIST controllers for a single-port synchronous SRAM.

The SRAM used during verification is a behavioral model. The Genus results represent the synthesized MBIST controller logic rather than a physical SRAM macro.

The fault-injection experiments represent logical fault models applied to the behavioral memory model; they should not be interpreted as direct measurements of physical SRAM defect coverage.

---

## 12. Tools

- **Verilog HDL** — RTL implementation
- **Cadence Genus** — logic synthesis and PPA analysis
- **Batch simulation scripts** — simulation automation
- **Behavioral SRAM model** — fault-injection verification
- **Git / GitHub** — version control and project management
