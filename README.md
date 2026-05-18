# ⚡ RISC-V Stride-Based Hardware Data Prefetcher

[![Verilog](https://img.shields.io/badge/Language-Verilog-blue)](https://en.wikipedia.org/wiki/Verilog)
[![FPGA](https://img.shields.io/badge/FPGA-Zybo%20Z7--10-green)](https://digilent.com/reference/programmable-logic/zybo-z7/start)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32I-orange)](https://riscv.org/)
[![Vivado](https://img.shields.io/badge/Tool-Vivado%202025.2-purple)](https://www.xilinx.com/products/design-tools/vivado.html)

> A fully synthesizable **Chen-Baer stride-based hardware data prefetcher** integrated into a 5-stage pipelined RV32I RISC-V processor. Physically verified on the **Digilent Zybo Z7-10 FPGA** using Vivado ILA, achieving a **2.71x execution speedup** and **99.4% cache hit rate** on sequential workloads.

---

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Performance Results](#performance-results)
- [Repository Structure](#repository-structure)
- [How to Build and Simulate](#how-to-build-and-simulate)
- [Hardware Verification](#hardware-verification)
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
| **Memory Arbiter** | Strict-priority arbiter ensuring CPU demand requests always preempt speculative prefetches |

### Prefetcher State Machine (Chen-Baer RPT)

Each entry in the Reference Prediction Table tracks a load instruction through three confidence states:

1. **INIT (0):** First occurrence of a load PC — records the memory address.
2. **TRANSIENT (1):** Second occurrence — computes the stride (current address − previous address).
3. **STEADY (2):** Third occurrence with matching stride — prefetcher begins issuing speculative fetches at `address + 2 × stride`.

If the stride changes while in STEADY, the state demotes back to TRANSIENT, preventing stale predictions.

---

## Key Features

- **Full RV32I ISA Support:** R-type, I-type, Load/Store, Branch, JAL, JALR, LUI, AUIPC
- **Pipeline Hazard Resolution:** Data forwarding eliminates most data hazards; load-use hazards handled with a single bubble
- **Speculative Prefetching:** Proactively fetches cache lines 2 strides ahead of the current access
- **O(1) RPT Lookup:** Direct-mapped table avoids expensive CAM logic, minimizing FPGA LUT usage
- **Hardware Performance Counters:** Built-in counters track cycles, stalls, hits, misses, prefetch events, and pollution in real-time
- **FPGA-Proven:** Synthesized and physically tested on Zybo Z7-10 with ILA-based signal capture

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

**Key Takeaways:**
- **99.4% stall reduction** compared to baseline (7,154 → 42 stall cycles)
- **2.71x overall speedup** in total execution time
- **97.6% cold-start miss elimination** (128 → 3 misses)

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
│   │   └── fpga_top.v                 # Zybo Z7 FPGA wrapper
│   ├── tb/
│   │   └── tb_riscv_top.v             # Cycle-accurate testbench
│   ├── constraints/
│   │   └── zybo_z7.xdc                # Pin constraints for Zybo Z7-10
│   ├── test_programs/
│   │   ├── program.mem                # Main test program (hex)
│   │   ├── data.mem                   # Initial data memory contents
│   │   ├── bench_stride16.mem         # Stride-16 benchmark
│   │   ├── bench_mixed.mem            # Mixed access pattern
│   │   └── bench_random.mem           # Random access pattern
│   ├── utilization_report.rpt         # Vivado resource utilization
│   └── timing_report.rpt             # Vivado timing analysis
└── README.md
```

---

## How to Build and Simulate

### Prerequisites
- **Xilinx Vivado 2025.2** (or compatible version)
- **Digilent Zybo Z7-10** board (for hardware verification)

### Behavioral Simulation
1. Open Vivado and create a new project targeting the `xc7z010clg400-1` device.
2. Add all `.v` files from `Synthesized_Project_Codes/rtl/` as design sources.
3. Add `tb_riscv_top.v` from `Synthesized_Project_Codes/tb/` as a simulation source.
4. Ensure `program.mem` and `data.mem` from `test_programs/` are accessible in the simulation working directory.
5. Run behavioral simulation. The testbench automatically runs all three test configurations (Baseline, Cache-only, Cache+Prefetcher) sequentially and prints performance counters to the Tcl console.

### FPGA Synthesis and Implementation
1. Set `fpga_top.v` as the top module.
2. Add `zybo_z7.xdc` as a constraints file.
3. Run Synthesis → Implementation → Generate Bitstream.
4. Program the Zybo Z7-10 via the Hardware Manager.

---

## Hardware Verification

The design was programmed onto a physical **Zybo Z7-10 FPGA (XC7Z010-1CLG400C)** and verified using a Xilinx Integrated Logic Analyzer (ILA). Key signals probed in real-time on the running hardware:

| Signal | Purpose |
|--------|---------|
| `dbg_pc[31:0]` | Tracks the program counter to confirm instruction flow |
| `evt_hit_w` | Confirms cache hits from prefetched data |
| `evt_pf_w` | Confirms the prefetcher is actively issuing speculative requests |

The ILA captures confirmed that `evt_pf_w` pulses matched the simulation behavior, proving that the stride detection logic operates correctly on physical silicon.

---

## Synthesis Results

Target: **Xilinx Zybo Z7-10 (XC7Z010-1CLG400C)**

| Resource | Used | Available | Utilization |
|----------|:----:|:---------:|:-----------:|
| Slice LUTs | 8,514* | 17,600 | 48.38% |
| Slice Registers | 5,342 | 35,200 | 15.18% |
| Block RAM (RAMB36) | 20 | 60 | 33.33% |
| Fmax | **76.18 MHz** | — | Timing Met ✅ |
| WNS (Worst Negative Slack) | 2.874 ns | — | Positive ✅ |

*\*LUT count includes the overhead of the Xilinx ILA debugging core used for hardware verification.*

---

## References

1. T. F. Chen and J. L. Baer, "Effective hardware-based data prefetching for high-performance processors," *IEEE Trans. Computers*, vol. 44, no. 5, pp. 609–623, May 1995.
2. D. A. Patterson and J. L. Hennessy, *Computer Organization and Design RISC-V Edition*, 2nd ed. Morgan Kaufmann, 2020.
3. A. Waterman, K. Asanović, and J. Hauser, eds., *The RISC-V Instruction Set Manual, Volume I: Unprivileged Architecture*, RISC-V International, 2019.
4. Xilinx Inc., *UG908: Vivado Design Suite User Guide — Programming and Debugging*, AMD/Xilinx, 2024.

---

*Developed by **Sarthak Kharwar** (B24498) — Indian Institute of Technology Mandi | Course: VL-326 VLSI System Design*
