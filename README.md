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

### Results

All three synthesized against a 2.0 ns (500 MHz) clock constraint, `slow`
corner, `mbist_top` as top:

| Metric | March C- | March X | March Y |
|---|---|---|---|
| Cell count | 94 | 82 | 118 |
| Total area | 532.86 | 466.25 | 578.27 |
| Total power | 85.2 µW | 77.0 µW | 171.0 µW |
| Critical path delay | 1721 ps | 1425 ps | 1466 ps |
| Setup slack @ 2.0 ns | 70 ps | 416 ps | 358 ps |
| Max theoretical Fmax | ~581 MHz | ~702 MHz | ~682 MHz |
| Operations | 10N | 6N | 8N |

**Takeaways:**
- **March X is the cheapest and fastest** across every metric — fewest
  states (8), fewest cells, lowest power, shortest critical path. Makes
  sense: it's the least ambitious algorithm (SAF/TF/CFin only, no CFid).
- **March Y costs more than March C- on area and power**, despite doing
  *fewer* operations (8N vs 10N) and having the *same* state count (12).
  The read-back verification states (`RD2`/`CMP` per element) add combinational
  compare/mux logic on top of the FSM, which shows up directly in power —
  March Y's `logic` category is 41.8% of total power vs. ~11% for the other
  two, and switching power alone (3.77e-05 W) is roughly 4x March C-'s. So
  operation count (N) doesn't map cleanly to hardware cost — *what* each
  operation does (plain read vs. read-with-verify) matters more than *how
  many* there are.
- **March C-'s critical path runs through the FSM's `bist_pass` decode
  logic** (12-deep combinational chain from `state_reg[1]` to
  `bist_pass_reg`), while March X/Y's critical paths run through the
  address generator/state register — consistent with March C- having the
  most states to decode into a single pass/fail bit.

## Fault-injection tests

All three testbenches (`tb_mbist.v`) run the same 5-test sequence against
`memory_model.v`'s built-in fault-injection tasks (`inject_stuck_at`,
`inject_corruption`), so results are directly comparable variant-to-variant:

| Test | What it does | Expected `bist_pass` |
|---|---|---|
| **T1 — Clean memory** | Run BIST with no faults injected | `1` (pass) |
| **T2 — Mid-run stuck-at fault** | Start BIST, wait 10 cycles, inject SA1 (`0xFF`) at address 5 while the test is running | `0` (fail) |
| **T3 — Multiple stuck-at faults** | Start BIST, wait 10 cycles, inject SA1 at addr 2 and SA0 at addr 7 | `0` (fail) |
| **T4 — Pre-existing faults** | Inject faults at addr 0 and 3 *before* `bist_start` is asserted | `0` (fail) |
| **T5 — Back-to-back clean runs** | Two consecutive clean runs after reset, verifies `bist_pass`/error state clears properly between runs and isn't sticky | `1`, `1` (pass, pass) |

`memory_model.v` also exposes `inject_corruption` (arbitrary single-shot bit
corruption vs. a persistent stuck-at fault) — defined but not currently
exercised by any of the three testbenches; available for future test cases.

**Known limitation (March Y only):** the testbench header notes that RDF
(Read Disturb Fault) is not detectable by this March Y sequence — a write
between the two reads of each element (`r0,w1,r1`) masks that fault class,
since the write intentionally changes the expected value between reads.
This is a property of the algorithm itself, not a testbench gap.


- [x] Synthesis results comparison across variants
- [x] Fault-injection test documentation