# 1D-CNN Hardware Accelerator on SoC for Wearable EEG Seizure Detection

A specialized, energy-efficient 1D-CNN hardware accelerator implemented in synthesizable RTL for real-time, single-channel epileptic seizure detection from EEG signals, targeting the **AMD-Xilinx Kria KV260 / KR260 Starter Kit (Zynq UltraScale+ MPSoC)**.

This repository hosts the hardware architecture, register-transfer level (RTL) designs, testbenches, and verification infrastructure designed to accelerate the **`WearSeizure-1D` (`wearseizure1d_k5only`)** neural network architecture.

---

## 1. Project Specifications

* **Target Application:** Real-time Wearable Epileptic Seizure Detection (CHB-MIT Clinical Protocol).
* **Target Hardware:** AMD-Xilinx Kria KV260 / KR260 (Zynq UltraScale+ MPSoC `xczu5ev`).
* **Input Signal:** Single-channel raw EEG, sampled at **256 Hz**.
* **Inference Window:** **4.0 seconds (1024 samples)**, streaming with a 1.0-second step size (1 classification decision per second).
* **Signal Conditioning:** Causal 4th-order Butterworth bandpass filter (1.0 – 30.0 Hz) applied prior to inference.
* **Arithmetic Precision:** **INT8 / DFP8** (8-bit Dynamic Fixed-Point, symmetric power-of-two scaling).
* **Clinical Performance:**
  * **Event-Level Sensitivity:** **94.89%** (Macro) / **95.67%** (Micro).
  * **False Alarm Rate (FAR):** **0.2937 / hour** (~1 false alarm every 3.4 hours).
  * **Mean Detection Delay:** **17.75 seconds**.
* **Hardware Sizing & Memory Footprint:**
  * **Total Parameters:** **11,786 parameters (~11.5 KiB at INT8 / DFP8)** (11,656 params / 11.4 KiB on hardware BRAM, 130 params on host software).
  * **Total Computation:** **489,600 MACs** per inference window (**489,472 MACs on FPGA hardware**, 192 operations for GAP/FC on ARM PS).
  * **Total On-Chip SRAM:** **18.2 KiB** (11.5 KiB INT8 weights + 6.7 KiB line buffers).
  * **External Memory Access:** **Zero DRAM access** during active inference (100% on-chip BRAM). Occupies only **~2.8%** of Kria KV260 on-chip Block RAM (640 KiB available).

---

## 2. Model Architecture & Layer Specifications

The deployed network adopts an **AI-Hardware Co-Design** approach:
1. **Depthwise-Separable Convolutions:** Decouples temporal filtering (Depthwise) from channel projection (Pointwise 1×1), reducing parameters and arithmetic complexity by >75%.
2. **Unified Kernel ($K=5$) with Exponential Dilation ($1 \rightarrow 2 \rightarrow 4 \rightarrow 8 \rightarrow 16$):** Expands the receptive field to cover long-range neural patterns without increasing multiplier counts or parameter storage.
3. **BatchNorm Folding:** During deployment, batch normalization statistics ($\gamma, \beta, \mu, \sigma$) are mathematically pre-folded into the convolutional weights and biases ($W_{\text{fused}}, B_{\text{fused}}$). The RTL datapath requires **no dedicated BatchNorm blocks**.
4. **Hardware/Software Partitioning:** The 13 heavy convolutional feature-extraction layers are fully accelerated in custom RTL on the FPGA (Programmable Logic - PL). Global Average Pooling (GAP) and the lightweight 2-class Linear Classifier (FC) are executed in software on the host ARM Cortex-A53 CPU (Processing System - PS).

### Layer-by-Layer Detailed Breakdown (`wearseizure1d_k5only`)

| Layer Name | Layer Type | Input Shape ($C_{in} \times L_{in}$) | Kernel ($k$) | Stride ($s$) | Dilation ($dil$) | Padding ($pad$) | Output Shape ($C_{out} \times L_{out}$) | Line Buffer | MACs | INT8 Weights |
| :--- | :--- | :---:| :---:| :---:| :---:| :---:| :---:| :---:| :---:| :---:|
| **`stem.0`** | Standard Conv1D | $1 \times 1024$ | **7** | 2 | 1 | 3 | $8 \times 512$ | 7 B | 28,672 | 56 B |
| **`b1.dw`** | Depthwise Conv1D | $8 \times 512$ | **5** | 2 | 1 | 2 | $8 \times 256$ | 40 B | 10,240 | 40 B |
| **`b1.pw`** | Pointwise Conv1D (1×1) | $8 \times 256$ | **1** | 1 | 1 | 0 | $16 \times 256$ | 8 B | 32,768 | 128 B |
| **`b2.dw`** | Depthwise Conv1D | $16 \times 256$ | **5** | 2 | 1 | 2 | $16 \times 128$ | 80 B | 10,240 | 80 B |
| **`b2.pw`** | Pointwise Conv1D (1×1) | $16 \times 128$ | **1** | 1 | 1 | 0 | $24 \times 128$ | 16 B | 49,152 | 384 B |
| **`b3.dw`** | Depthwise Conv1D | $24 \times 128$ | **5** | 2 | **2** | 4 | $24 \times 64$ | 216 B | 7,680 | 120 B |
| **`b3.pw`** | Pointwise Conv1D (1×1) | $24 \times 64$ | **1** | 1 | 1 | 0 | $32 \times 64$ | 24 B | 49,152 | 768 B |
| **`b4.dw`** | Depthwise Conv1D | $32 \times 64$ | **5** | 2 | **4** | 8 | $32 \times 32$ | 544 B | 5,120 | 160 B |
| **`b4.pw`** | Pointwise Conv1D (1×1) | $32 \times 32$ | **1** | 1 | 1 | 0 | $48 \times 32$ | 32 B | 49,152 | 1,536 B |
| **`context.0.dw`** | Depthwise Conv1D | $48 \times 32$ | **5** | 1 | **8** | 16 | $48 \times 32$ | 1,584 B | 7,680 | 240 B |
| **`context.0.pw`** | Pointwise Conv1D (1×1) | $48 \times 32$ | **1** | 1 | 1 | 0 | $64 \times 32$ | 48 B | 98,304 | 3,072 B |
| **`context.1.dw`** | Depthwise Conv1D | $64 \times 32$ | **5** | 1 | **16** | 32 | $64 \times 32$ | 4,160 B | 10,240 | 320 B |
| **`context.1.pw`** | Pointwise Conv1D (1×1) | $64 \times 32$ | **1** | 1 | 1 | 0 | $64 \times 32$ | 64 B | 131,072 | 4,096 B |
| *HW Subtotal* | *(13 Layers in RTL)* | | | | | | | **~6.7 KiB** | **489,472** | **11,528 B (~11.4 KiB)** |
| **`GAP`** | Global Average Pooling *(SW)* | $64 \times 32$ | — | — | — | — | $64 \times 1$ | — | 64 | 0 B |
| **`FC`** | Linear Classifier *(SW)* | $64 \times 1$ | **1** | — | — | — | $2 \times 1$ (Logits) | — | 128 | 128 B |
| **Total** | *(Full Pipeline)* | | | | | | | **~6.7 KiB** | **489,600** | **~11.5 KiB** |

> **Note on MACs Counting:** Software profilers (e.g., `thop`) report **585,920 MACs** because they count separate BatchNorm and activation operations. In actual deployment, BatchNorm is folded into preceding Conv weights/biases, yielding **489,472 hardware MACs** on FPGA and **192 operations** on ARM software.

---

## 3. Hardware Architecture Overview

The accelerator implements an **Instruction-Driven, Output-Stationary (OS)** datapath tailored for 1D streaming tensors:

* **Instruction-Based Controller:** Sequences through the **13 convolutional feature-extraction layers** by decoding 64-bit micro-instructions from an on-chip Instruction Memory, eliminating host CPU polling during feature extraction.
* **Output-Stationary Processing Element (PE) Array:** Partial sums are accumulated locally in wide 48-bit internal accumulators until each output channel point is fully resolved, minimizing memory read/write energy.
* **Configurable Convolution Engine:** Unified hardware execution for:
  * Standard 1D Convolution ($K=7$).
  * Depthwise Separable 1D Convolution ($K=5$).
  * Pointwise 1D Convolution ($K=1$).
* **Sliding Line Buffer:** Stream-buffers temporal samples to service multi-tap convolutions across varying dilation rates ($dil \in \{1, 2, 4, 8, 16\}$) with single-pass data reuse.
* **On-Chip Ping-Pong Banking:** Interleaved dual-port SRAM banks to enable simultaneous feature map calculation and DMA transfer across AXI interfaces.
* **Software Output Hand-off:** After layer 13 (`context.1.pw`) finishes, the resulting $64 \times 32$ feature map is transferred to the ARM host CPU, which computes GAP (32-tap mean) and the 2-class Linear FC layer in microseconds.

---

## 4. Directory Structure

```text
AI-Accelerator-RTL/
├── docs/                 # Architecture specifications, register maps, and protocols
├── model/                # Python bit-exact golden reference and quantized test vectors
│   ├── test_vectors/     # Hex / text test vectors for layer-by-layer validation
│   └── weights/          # Quantized INT8 weights and fused biases
├── rtl/                  # Synthesizable Verilog-2001 / SystemVerilog RTL source files
│   ├── core/             # Processing elements, line buffers, MAC units
│   ├── memory/           # Dual-port BRAM wrappers and Ping-Pong memory banks
│   └── top/              # Top-level accelerator core and AXI interconnect wrappers
├── tb/                   # Self-checking testbenches and verification test harnesses
├── sim/                  # Simulation environment and automated execution scripts
│   └── Makefile          # Icarus Verilog build and execution rules
├── Makefile              # Root automation entrypoint
└── README.md             # Project overview and technical specification
```

---

## 5. Development & Simulation Environment Setup (WSL2 + Icarus Verilog)

To ensure lightweight, hassle-free simulation and seamless team collaboration on Git without the overhead of heavy proprietary EDA project files, this repository standardizes on **Icarus Verilog (`iverilog`)** and **GTKWave** running under **WSL2 (Windows Subsystem for Linux)**.

### 5.1 One-Time Environment Setup (WSL2 / Ubuntu)

All team members can configure their environment with standard apt packages:

```bash
# 1. Update package lists and install Icarus Verilog + GTKWave
sudo apt update
sudo apt install -y iverilog gtkwave make

# 2. Verify installed versions
iverilog -V
gtkwave --version
```

*(Note: If WSL2 is not yet installed on Windows, run `wsl --install` in an Administrator PowerShell prompt and reboot).*

### 5.2 Verification Quickstart & Command Reference

From the project root within the WSL2 terminal:

```bash
# ---------------------------------------------------------
# 1. RTL Compilation & Syntax Checking
# ---------------------------------------------------------
make compile                  # Check syntax & synthesizability for ALL files in rtl/
make compile SRC=smoke_adder  # Check syntax for a SINGLE file (e.g. rtl/smoke_adder.v)

# ---------------------------------------------------------
# 2. Simulation & Testbench Execution
# ---------------------------------------------------------
make smoke                    # Quick smoke test (tb_smoke: a + b verification)
make test TB=tb_smoke         # Run a specific testbench (e.g. tb/tb_smoke.v)
make test-all                 # Run ALL testbenches in tb/ sequentially with summary report

# ---------------------------------------------------------
# 3. Waveform Inspection with GTKWave
# ---------------------------------------------------------
make wave                     # Automatically opens waveform of the MOST RECENTLY run test
make wave TB=tb_smoke         # Explicitly opens a specific test waveform (build/tb_smoke.vcd)

# ---------------------------------------------------------
# 4. Clean Artifacts
# ---------------------------------------------------------
make clean                    # Remove build directory, simulation executables, and .vcd dumps
```

### 5.3 Hardware/Software Development Philosophy
* **On Git & Local Machines:** Team members write pure Verilog testbenches, iterate on RTL logic, and verify bit-exact outputs using **Icarus Verilog + GTKWave**.
* **On Physical FPGA (Vivado Target):** Once the RTL datapath passes functional verification, the verified `rtl/` source directory is imported into **Xilinx Vivado** on personal machines for AXI IP packaging, Static Timing Analysis (STA), and Bitstream generation on the **AMD-Xilinx Kria KV260**.
