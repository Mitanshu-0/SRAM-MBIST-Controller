# MBIST — Memory Built-In Self-Test (Verilog)

A Verilog MBIST (Memory Built-In Self-Test) controller for a single-port
synchronous SRAM, implemented and compared across three classic March-test
algorithms. Each variant shares an identical datapath — address generator,
data generator, comparator — and swaps out only the FSM controller, so
synthesis results (area / power / timing) are directly comparable across
algorithms with the FSM as the sole independent variable.

## Algorithms compared

| Variant  | Sequence | Operations | States | Fault coverage |
|----------|----------|------------|--------|-----------------|
| **March C-** | `↑(w0); ↑(r0,w1); ↑(r1,w0); ↓(r0,w1); ↓(r1,w0); ↑(r0)` | 10N | 12 | SAF, TF, CFin, CFid |
| **March Y**  | `↑(w0); ↑(r0,w1,r1); ↓(r1,w0,r0); ↓(r0)` | 8N | 12 | SAF, TF, CFin |
| **March X**  | `↑(w0); ↑(r0,w1); ↓(r1,w0); ↓(r0)` | 6N | 8 | SAF, TF, CFin |

- **March C-** gives the broadest fault coverage (adds CFid detection over
  March X/Y) at the highest operation count.
- **March Y** strengthens March X by adding a read-back after every write
  (`r0,w1,r1` / `r1,w0,r0` instead of just `r0,w1` / `r1,w0`), catching
  transition/coupling faults that a single write-then-move-on can miss.
- **March X** is the leanest of the three — fewest operations, fewest states.

## Repository structure

```
MBIST/
├── march_c-/
│   ├── rtl/        # address_generator.v, comparator.v, data_generator.v,
│   │                # fsm_controller.v, mbist_top.v, memory_model.v
│   ├── tb/          # tb_mbist.v
│   └── sim/         # created on demand by run.bat — gitignored
│       └── run.bat
├── march_x/
│   └── ...          # same layout
├── march_y/
│   └── ...          # same layout
└── docs/
    └── genus_reports/
        ├── march_c-/
        ├── march_x/
        └── march_y/
```

## Architecture

`mbist_top.v` instantiates and wires together:

- **`address_generator`** — up/down counter with load, drives `mem_addr`
- **`data_generator`** — selects the write pattern and expected read pattern
  per FSM phase (`write_sel` / `expect_sel`)
- **`comparator`** — checks `mem_dout` against the expected pattern, flags
  `comp_error`
- **`fsm_controller`** — sequences the March elements (M0…Mn), drives
  `mem_we`, address direction/load, and pattern selects. **This is the only
  module that differs between variants** — port interface is identical
  across March C-, March X, and March Y, so the FSM is a drop-in swap.

`mbist_top` I/O:

| Port | Direction | Description |
|------|-----------|--------------|
| `clk`, `rst_n` | in | clock / active-low reset |
| `bist_start` | in | pulse to begin test |
| `bist_done` | out | test sequence complete |
| `bist_pass` | out | pass/fail result, valid when `bist_done` is high |
| `mem_addr`, `mem_din`, `mem_dout`, `mem_we`, `mem_en` | — | memory interface, connect to DUT SRAM or `memory_model.v` for sim |

`memory_model.v` is a behavioral single-port SRAM used only for simulation —
it is **not** part of the synthesized design (see Synthesis section below).

## FSM state design

Each variant's FSM pairs a **read state** (issue the address, comparator
result not yet valid) with a **write/compare state** (comparator result
from the pipelined read is now valid, so compare + write + advance happen
together). This read/compare-and-write split is what lets a single-port
synchronous memory be walked without stalling a cycle between operations.

**March C-** — 12 states (`ST_IDLE`, `ST_DONE` + one RD/WR pair per March
element M0–M5):
```
ST_IDLE → ST_M0_WR
        → ST_M1_RD → ST_M1_WR
        → ST_M2_RD → ST_M2_WR
        → ST_M3_RD → ST_M3_WR
        → ST_M4_RD → ST_M4_WR
        → ST_M5_RD → ST_DONE
```

**March X** — 8 states, same RD/WR pairing pattern but only 2 read/write
March elements (M1, M2) plus a final read-only pass (M3):
```
ST_IDLE → ST_M0_WR
        → ST_M1_RD → ST_M1_WR
        → ST_M2_RD → ST_M2_WR
        → ST_M3_RD → ST_DONE
```

**March Y** — 12 states. M1 and M2 each expand to a **4-state sub-sequence**
(`RD1 → WR → RD2 → CMP`) instead of a single RD/WR pair, because each
element does a read-back after the write to verify it stuck (`r0,w1,r1` /
`r1,w0,r0`) rather than just moving on after the write:
```
ST_IDLE → ST_M0_WR
        → ST_M1_RD1 → ST_M1_WR → ST_M1_RD2 → ST_M1_CMP
        → ST_M2_RD1 → ST_M2_WR → ST_M2_RD2 → ST_M2_CMP
        → ST_M3_RD → ST_DONE
```

This is the direct structural reason March Y costs more states/area than
March X for only 2 extra N of operations — the read-back requires two
additional states per March element (RD2 + CMP) rather than adding to an
existing state.

## Running simulation

Each variant is self-contained. From inside a variant's `sim/` folder:

```
cd march_c-\sim
run.bat
```

This compiles the testbench (`tb_mbist.v`) against `rtl/` and `memory_model.v`,
runs the simulation, and drops the compiled output / waveform in `sim/`
(gitignored — regenerate anytime by re-running `run.bat`). Repeat inside
`march_x\sim` and `march_y\sim` to run the other variants.

## Synthesis

Each variant was synthesized in Cadence Genus with `mbist_top` as the
synthesis top — i.e. `address_generator`, `data_generator`, `comparator`,
and `fsm_controller` only. `memory_model.v` is sim-only (behavioral, not
synthesizable as-is) and `tb_mbist.v` is never part of the synthesized
design.

Reports live under `docs/genus_reports/<variant>/`:

| File | Contents |
|------|-----------|
| `<variant>_area.rep` | cell/gate area breakdown |
| `<variant>_power.rep` | power estimate |
| `<variant>_timing.rep` | timing/slack report |
| `<variant>_messages.rep` | synthesis warnings/errors |
| `<variant>_netlist.v` | gate-level netlist |
| `<variant>.sdc`, `mbist.sdc` | timing constraints used |
| `run.tcl` | Genus script used to produce the above |

## Status / TODO

- [ ] Add a summary table comparing area/power/timing across the three variants
- [ ] Document specific fault-injection test cases per variant
- [ ] CI to auto-run simulations on push