# ⚡ RISC-V Stride-Based Hardware Data Prefetcher

[![Verilog](https://img.shields.io/badge/Language-Verilog-blue)](https://en.wikipedia.org/wiki/Verilog)
[![FPGA](https://img.shields.io/badge/FPGA-Zybo%20Z7--10-green)](https://digilent.com/reference/programmable-logic/zybo-z7/start)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32I-orange)](https://riscv.org/)
[![Vivado](https://img.shields.io/badge/Tool-Vivado%202025.2-purple)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Status](https://img.shields.io/badge/Status-Hardware%20Verified-brightgreen)](https://github.com/optimusprimeboi/RISC-V-Stride-Prefetcher)

> A fully synthesizable **Chen-Baer stride-based hardware data prefetcher** integrated into a 5-stage pipelined RV32I RISC-V processor. Physically verified on the **Digilent Zybo Z7-10 FPGA** using Vivado ILA, achieving a **2.71x execution speedup** and **99.4% cache hit rate** on sequential workloads.

📊 **Quick Stats:** `2.71× speedup` | `99.4% stall reduction` | `97.6% cold-start miss elimination` | `76.18 MHz Fmax` | `Timing Met ✅`

---

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Performance Results](#performance-results)
- [Simulation Waveforms](#simulation-waveforms)
- [Hardware Verification on FPGA](#hardware-verification-on-fpga)
- [Repository Structure](#repository-structure)
- [How to Build and Simulate](#how-to-build-and-simulate)
- [Synthesis Results](#synthesis-results)
- [References](#references)

---

## Overview

Memory latency is the dominant bottleneck in modern processor performance. This project addresses the **Memory Wall** problem by implementing a proactive stride-based hardware prefetcher that detects regular memory access patterns and speculatively fetches data into the L1 cache **before** the CPU requests it.

### Research Question
> *What fraction of cold-start misses are eliminated by a stride-based prefetcher, and under what memory access patterns does the prefetcher cause harmful cache pollution?*

**Answer:** The prefetcher eliminated **97.6%** of cold-start misses for linear access patterns (128 → 3 misses). Cache pollution was minimal at only 2 events out of 127 prefetches issued.

---

## Architecture

The system consists of four major hardware blocks sharing a single memory bus:

| Block | Description |
|-------|-------------|
| **RV32I Core** | 5-stage pipeline (IF → ID → EX → MEM → WB) with full data forwarding from MEM and WB stages to EX |
| **L1 Data Cache** | 256-byte, direct-mapped, write-through, 4-word cache lines, zero-cycle hit path |
| **Stride Prefetcher** | 8-entry direct-mapped RPT using PC bits [4:2], Chen-Baer 3-state confidence FSM |
| **Memory Arbiter** | Strict-priority arbiter — CPU demand requests always preempt speculative prefetches |

### Block Diagram

```
                    ┌──────────────────┐
                    │   RV32I 5-Stage  │
                    │   Pipeline Core  │
                    └───────┬──────────┘
                            │ Load/Store
                    ┌───────▼──────────┐
                    │  L1 Data Cache   │
                    │  (256B, DM, WT)  │
                    └──┬───────────┬───┘
                       │           │ Miss / RPT event
                       │    ┌──────▼──────────┐
                       │    │ Stride Prefetcher│
                       │    │  (8-entry RPT)   │
                       │    └──────┬───────────┘
                    ┌──▼───────────▼───┐
                    │  Memory Arbiter  │
                    │  (CPU Priority)  │
                    └────────┬─────────┘
                    ┌────────▼─────────┐
                    │   Main Memory    │
                    │  (10-cycle DRAM) │
                    └──────────────────┘
```

### Prefetcher State Machine (Chen-Baer RPT)

Each entry in the Reference Prediction Table tracks a load instruction through three confidence states:

1. **INIT (0):** First occurrence of a load PC — records the memory address.
2. **TRANSIENT (1):** Second occurrence — computes the stride (`current_address − prev_address`).
3. **STEADY (2):** Third occurrence with matching stride — prefetcher issues fetches at `address + 2 × stride`.

If the stride changes while in STEADY, the state demotes back to TRANSIENT, preventing stale predictions.

### Key Signal Interface

The following are the primary I/O signals of the top-level `riscv_top` module that connect the CPU, Cache, and Prefetcher:

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `clk` | In | 1-bit | System clock (62.5 MHz on FPGA) |
| `rst_n` | In | 1-bit | Active-low asynchronous reset |
| `cache_enable` | In | 1-bit | Enables the L1 Data Cache (mapped to `sw[0]`) |
| `prefetch_enable` | In | 1-bit | Enables the Stride Prefetcher (mapped to `sw[1]`) |
| `dbg_pc[31:0]` | Out | 32-bit | Current Program Counter for ILA probing |
| `evt_hit` | Out | 1-bit | Pulses HIGH on every L1 cache hit |
| `evt_pf_issued` | Out | 1-bit | Pulses HIGH every time the prefetcher issues a request |
| `cnt_cycles[31:0]` | Out | 32-bit | Total elapsed clock cycles |
| `cnt_instrs[31:0]` | Out | 32-bit | Total retired instructions |
| `cnt_stall_cycles[31:0]` | Out | 32-bit | Total cycles the CPU spent stalled |
| `cnt_cache_hits[31:0]` | Out | 32-bit | Cumulative cache hit counter |
| `cnt_cache_misses[31:0]` | Out | 32-bit | Cumulative cache miss counter |
| `cnt_pf_hits[31:0]` | Out | 32-bit | Prefetch hits (prefetched lines actually used by CPU) |
| `cnt_pf_issued[31:0]` | Out | 32-bit | Total prefetch requests issued |
| `cnt_pf_pollution[31:0]` | Out | 32-bit | Prefetch pollution events (useful-but-evicted lines) |

---

## Key Features

- **Full RV32I ISA Support:** R-type, I-type, Load/Store, Branch, JAL, JALR, LUI, AUIPC
- **Pipeline Hazard Resolution:** Full data forwarding eliminates most hazards; load-use handled with one bubble
- **Speculative Prefetching:** Proactively fetches cache lines 2 strides ahead of the current access
- **O(1) RPT Lookup:** Direct-mapped table avoids expensive CAM logic, minimizing FPGA LUT usage
- **Hardware Performance Counters:** Real-time tracking of cycles, stalls, hits, misses, prefetch events, and pollution
- **Physical LED Feedback on FPGA board:**
  - `LED[0]` — Cache Enable status (mirrors `sw[0]`)
  - `LED[1]` — Prefetch Enable status (mirrors `sw[1]`)
  - `LED[2]` — Cache Hit heartbeat (visually flashes on every cache hit)
  - `LED[3]` — Prefetch heartbeat (visually flashes on every speculative fetch)
- **FPGA-Proven:** Synthesized and hardware-tested on Zybo Z7-10 with ILA signal capture

---

## Performance Results

Evaluated using a sequential array accumulation workload (2,564 instructions):

| Metric | Baseline (No Cache) | Cache Only | Cache + Prefetcher |
|--------|:-------------------:|:----------:|:------------------:|
| **Total Cycles** | 11,263 | 5,901 | 4,151 |
| **CPI** | 4.39 | 2.30 | **1.62** |
| **Stall Cycles** | 7,154 | 1,792 | **42** |
| **Cache Hit Rate** | N/A | 75.0% | **99.4%** |
| **Prefetches Issued** | 0 | 0 | 127 |
| **Prefetch Accuracy** | N/A | N/A | **98.4%** |
| **Cache Pollution Events** | 0 | 0 | 2 |

**Key Takeaways:**
- **99.4% stall reduction** compared to baseline (7,154 → 42 stall cycles)
- **2.71x overall speedup** in total execution time
- **97.6% cold-start miss elimination** (128 → 3 misses)
- Cache pollution is negligible (2 events) for sequential workloads

---

## Simulation Waveforms

The following Vivado behavioral simulation waveforms prove the design across all three test configurations:

### Overview — All 3 Tests (Timeline View)
![All Tests Overview](Simulation_Results/all_test_overview.png)
> The macro view clearly shows the dense `cpu_dmem_stall` blocks in Test 1 (Baseline) progressively shrinking through Test 2 (Cache Only), and nearly disappearing in Test 3 (Cache + Prefetcher).

### Test 1 — Baseline (No Cache, No Prefetcher)
![Test 1 Waveform](Simulation_Results/test1.png)
> `cpu_dmem_stall` is almost permanently HIGH. The CPU spends 63% of all clock cycles waiting for data from the 10-cycle latency main memory. CPI = 4.39.

### Test 2 — Cache Only (No Prefetcher)
![Test 2 Waveform](Simulation_Results/test2.png)
> Cache hits (4-word line fill) eliminate 75% of stalls. Remaining misses are cold-start misses on first access to each new cache line. CPI = 2.30.

### Test 3 — Cache + Stride Prefetcher
![Test 3 Waveform](Simulation_Results/test3.png)
> The RPT reaches STEADY state after 3 misses. `evt_pf_issued` pulses confirm speculative fetches. `cpu_dmem_stall` almost completely disappears. CPI = 1.62.

---

## Hardware Verification on FPGA

The design was synthesized, implemented, and programmed onto a physical **Digilent Zybo Z7-10 FPGA (XC7Z010-1CLG400C)** running at **62.5 MHz** (125 MHz board clock divided by 2 in `fpga_top.v`).

### ILA-Probed Signals
A Xilinx Integrated Logic Analyzer (ILA) core was instantiated to capture the following **three signals** that are marked with `(* mark_debug = "true" *)` in `fpga_top.v`:

| Signal | Width | What It Proves |
|--------|-------|----------------|
| `dbg_pc[31:0]` | 32-bit | Program Counter is incrementing — CPU is executing real instructions on the FPGA |
| `evt_hit_w` | 1-bit | Pulses HIGH on every cache hit — confirms prefetched data is being consumed by the CPU |
| `evt_pf_w` | 1-bit | Pulses HIGH on every issued prefetch — proves the RPT reached STEADY and is actively prefetching |

### Observed LED and Signal Behavior

| Configuration | `LED[2]` (Hit) | `LED[3]` (Prefetch) | `dbg_pc` Pattern |
|--------------|:--------------:|:-------------------:|:-----------------:|
| Cache OFF, Prefetch OFF | Dark | Dark | Irregular (frequent stalls) |
| Cache ON, Prefetch OFF | Occasional flicker | Dark | Mostly regular |
| Cache ON, Prefetch ON | Rapid flashing | Rapid flashing | Very regular increments |

### ILA Trigger Configuration
The ILA was configured to trigger on `evt_pf_w = 1`, capturing a snapshot window the exact moment the prefetcher first issues a speculative request. This proved that the hardware FSM transitions to STEADY state and begins prefetching, mirroring the behavioral simulation results.

---

## Repository Structure

```
├── Report/
│   └── b24498_COA_report.pdf          # IEEE-format technical paper
├── Simulation_Results/
│   ├── all_test_overview.png          # Macro view of all 3 test phases
│   ├── test1.png                      # Baseline waveform (heavy stalls)
│   ├── test2.png                      # Cache-only waveform
│   └── test3.png                      # Prefetcher waveform (stalls gone)
├── Synthesized_Project_Codes/
│   ├── rtl/                           # All Verilog source files
│   │   ├── riscv_top.v                # Top-level SoC integration
│   │   ├── rv32i_core.v               # 5-stage pipelined CPU
│   │   ├── l1_data_cache.v            # Direct-mapped L1 data cache
│   │   ├── stride_prefetcher.v        # Chen-Baer stride prefetcher
│   │   ├── control_unit.v             # Instruction decoder
│   │   ├── hazard_unit.v              # Forwarding and stall logic
│   │   ├── alu.v                      # Arithmetic logic unit
│   │   ├── reg_file.v                 # 32-entry register file
│   │   ├── imm_gen.v                  # Immediate generator
│   │   ├── instruction_memory.v       # BRAM-based IMEM
│   │   ├── main_memory.v              # Simulated 10-cycle DRAM
│   │   ├── perf_counters.v            # Hardware performance counters
│   │   └── fpga_top.v                 # Zybo Z7 FPGA wrapper with LED + ILA
│   ├── tb/
│   │   └── tb_riscv_top.v             # Cycle-accurate testbench (3 tests)
│   ├── constraints/
│   │   └── zybo_z7.xdc                # Pin constraints for Zybo Z7-10
│   ├── test_programs/
│   │   ├── program.mem                # Main test program (hex)
│   │   ├── data.mem                   # Initial data memory contents
│   │   ├── bench_stride16.mem         # Stride-16 benchmark
│   │   ├── bench_mixed.mem            # Mixed access pattern
│   │   └── bench_random.mem           # Random access pattern
│   ├── utilization_report.rpt         # Vivado post-implementation resource report
│   └── timing_report.rpt             # Vivado post-route timing analysis
└── README.md
```

---

## ⚡ Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/optimusprimeboi/RISC-V-Stride-Prefetcher.git
cd RISC-V-Stride-Prefetcher

# 2. Open Vivado and create a project targeting xc7z010clg400-1
# 3. Add all .v files from Synthesized_Project_Codes/rtl/ as sources
# 4. Add tb_riscv_top.v as simulation source
# 5. Run Behavioral Simulation — watch the Tcl console for performance stats!
```

---

## How to Build and Simulate

### Prerequisites
- **Xilinx Vivado 2025.2** (or compatible version)
- **Digilent Zybo Z7-10** board (for hardware verification)

### Behavioral Simulation
1. Open Vivado and create a new project targeting `xc7z010clg400-1`.
2. Add all `.v` files from `Synthesized_Project_Codes/rtl/` as design sources.
3. Add `tb_riscv_top.v` from `tb/` as a simulation source.
4. Copy `program.mem` and `data.mem` into the simulation working directory.
5. Run behavioral simulation. The testbench automatically executes all 3 configurations and prints a performance counter summary to the Tcl console.

### FPGA Synthesis and Implementation
1. Set `fpga_top.v` as the top module.
2. Add `zybo_z7.xdc` as a constraints file.
3. **Important:** Update the `IMEM_INIT` and `DMEM_INIT` file paths in `fpga_top.v` to point to your local copy of `program.mem` and `data.mem`.
4. Run Synthesis → Implementation → Generate Bitstream.
5. Program the Zybo Z7-10 via Vivado Hardware Manager.
6. Use `sw[0]` to enable Cache and `sw[1]` to enable Prefetcher. Watch `LED[2]` and `LED[3]` for hit and prefetch activity.

### Configurable Parameters

You can modify these parameters in the RTL to experiment with different configurations:

| Parameter | File | Default | Description |
|-----------|------|:-------:|-------------|
| `RPT_SIZE` | `stride_prefetcher.v` | 8 entries | Number of RPT entries (indexed by PC bits) |
| `CACHE_LINES` | `l1_data_cache.v` | 16 lines (256B) | Number of cache lines (4 words each) |
| `MEM_LATENCY` | `fpga_top.v` | 10 cycles | Simulated DRAM access latency |
| `IMEM_DEPTH` | `fpga_top.v` | 1024 words | Instruction memory depth |
| `DMEM_DEPTH` | `fpga_top.v` | 4096 words | Data memory depth |

---

## Synthesis Results

Target: **Xilinx Zybo Z7-10 (XC7Z010-1CLG400C)**

| Resource | Used | Available | Utilization |
|----------|:----:|:---------:|:-----------:|
| Slice LUTs | 8,514* | 17,600 | 48.38% |
| Slice Registers | 5,342 | 35,200 | 15.18% |
| Block RAM (RAMB36) | 20 | 60 | 33.33% |
| F7 Muxes | 207 | 8,800 | 2.35% |
| Bonded IOBs | 8 | 100 | 8.00% |
| Fmax | **76.18 MHz** | — | Timing Met ✅ |
| WNS (Worst Negative Slack) | **+2.874 ns** | — | Positive ✅ |

*\*LUT count includes the overhead of the Xilinx ILA debugging core used for hardware verification.*

> All timing constraints are met. Zero failing endpoints across Setup, Hold, and Pulse Width checks.

---

## ⚠️ Known Limitations and Future Work

| Limitation | Impact | Suggested Fix |
|-----------|--------|---------------|
| **RPT Aliasing** | Two different load PCs may hash to the same RPT entry (only 8 entries, indexed by PC[4:2]) causing incorrect stride predictions | Increase RPT to 16–32 entries or use a tagged RPT |
| **Cache Pollution on Random Accesses** | Prefetching wrong lines evicts valid data in the tiny 256-byte cache during non-sequential loops | Add a confidence threshold — only prefetch after 2 confirmed STEADY hits |
| **Single-Port Memory Bus** | Cache and Prefetcher share one memory bus; prefetch latency is non-zero even in STEADY state | Add a dedicated prefetch port or a small prefetch buffer/queue |
| **Fixed Prefetch Distance** | Always prefetches `2 × stride` ahead; may over-fetch for slow loops | Make prefetch distance adaptive based on measured hit rate |
| **No Branch Prediction** | Branch mispredictions flush the pipeline, and currently fetched data may be invalidated | Integrate a simple 2-bit saturating branch predictor |

---

## References

1. T. F. Chen and J. L. Baer, "Effective hardware-based data prefetching for high-performance processors," *IEEE Trans. Computers*, vol. 44, no. 5, pp. 609–623, May 1995.
2. D. A. Patterson and J. L. Hennessy, *Computer Organization and Design RISC-V Edition*, 2nd ed. Morgan Kaufmann, 2020.
3. A. Waterman, K. Asanović, and J. Hauser, eds., *The RISC-V Instruction Set Manual, Volume I: Unprivileged Architecture*, RISC-V International, 2019.
4. Xilinx Inc., *UG908: Vivado Design Suite User Guide — Programming and Debugging*, AMD/Xilinx, 2024.

---

