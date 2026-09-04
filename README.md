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
* **Arithmetic Precision:** **INT16 / DFP16** (16-bit Dynamic Fixed-Point, symmetric power-of-two scaling).
* **Clinical Performance:**
  * **Event-Level Sensitivity:** **94.89%** (Macro) / **95.67%** (Micro).
  * **False Alarm Rate (FAR):** **0.2937 / hour** (~1 false alarm every 3.4 hours).
  * **Mean Detection Delay:** **17.75 seconds**.
* **Hardware Sizing & Memory Footprint:**
  * **Total Parameters:** **11,786 parameters (~23.0 KiB at INT16 / DFP16)**.
  * **Total Computation:** **489,600 MACs** per inference window.
  * **Total On-Chip SRAM:** **36.3 KiB** (23.0 KiB INT16 weights + 13.3 KiB line buffers and feature maps).
  * **External Memory Access:** **Zero DRAM access** during active inference (100% on-chip BRAM). Occupies only **~5.6%** of Kria KV260 on-chip Block RAM (640 KiB available).

---

## 2. Model Architecture & Layer Specifications

The deployed network adopts an **AI-Hardware Co-Design** approach:
1. **Depthwise-Separable Convolutions:** Decouples temporal filtering (Depthwise) from channel projection (Pointwise 1×1), reducing parameters and arithmetic complexity by >75%.
2. **Unified Kernel ($K=5$) with Exponential Dilation ($1 \rightarrow 2 \rightarrow 4 \rightarrow 8 \rightarrow 16$):** Expands the receptive field to cover long-range neural patterns without increasing multiplier counts or parameter storage.
3. **BatchNorm Folding:** During deployment, batch normalization statistics ($\gamma, \beta, \mu, \sigma$) are mathematically pre-folded into the convolutional weights and biases ($W_{\text{fused}}, B_{\text{fused}}$). The RTL datapath requires **no dedicated BatchNorm blocks**.
4. **Global Average Pooling (GAP):** Condenses the temporal dimension to eliminate large fully-connected weight matrices.

### Layer-by-Layer Detailed Breakdown (`wearseizure1d_k5only`)

| Layer Name | Layer Type | Input Shape ($C_{in} \times L_{in}$) | Kernel ($k$) | Stride ($s$) | Dilation ($dil$) | Padding ($pad$) | Output Shape ($C_{out} \times L_{out}$) | Line Buffer | MACs (HW) | INT16 Weights |
| :--- | :--- | :---:| :---:| :---:| :---:| :---:| :---:| :---:| :---:| :---:|
| **`stem.0`** | Standard Conv1D | $1 \times 1024$ | **7** | 2 | 1 | 3 | $8 \times 512$ | 14 B | 28,672 | 112 B |
| **`b1.dw`** | Depthwise Conv1D | $8 \times 512$ | **5** | 2 | 1 | 2 | $8 \times 256$ | 80 B | 10,240 | 80 B |
| **`b1.pw`** | Pointwise Conv1D (1×1) | $8 \times 256$ | **1** | 1 | 1 | 0 | $16 \times 256$ | 16 B | 32,768 | 256 B |
| **`b2.dw`** | Depthwise Conv1D | $16 \times 256$ | **5** | 2 | 1 | 2 | $16 \times 128$ | 160 B | 10,240 | 160 B |
| **`b2.pw`** | Pointwise Conv1D (1×1) | $16 \times 128$ | **1** | 1 | 1 | 0 | $24 \times 128$ | 32 B | 49,152 | 768 B |
| **`b3.dw`** | Depthwise Conv1D | $24 \times 128$ | **5** | 2 | **2** | 4 | $24 \times 64$ | 432 B | 7,680 | 240 B |
| **`b3.pw`** | Pointwise Conv1D (1×1) | $24 \times 64$ | **1** | 1 | 1 | 0 | $32 \times 64$ | 48 B | 49,152 | 1,536 B |
| **`b4.dw`** | Depthwise Conv1D | $32 \times 64$ | **5** | 2 | **4** | 8 | $32 \times 32$ | 1,088 B | 5,120 | 320 B |
| **`b4.pw`** | Pointwise Conv1D (1×1) | $32 \times 32$ | **1** | 1 | 1 | 0 | $48 \times 32$ | 64 B | 49,152 | 3,072 B |
| **`context.0.dw`** | Depthwise Conv1D | $48 \times 32$ | **5** | 1 | **8** | 16 | $48 \times 32$ | 3,168 B | 7,680 | 480 B |
| **`context.0.pw`** | Pointwise Conv1D (1×1) | $48 \times 32$ | **1** | 1 | 1 | 0 | $64 \times 32$ | 96 B | 98,304 | 6,144 B |
| **`context.1.dw`** | Depthwise Conv1D | $64 \times 32$ | **5** | 1 | **16** | 32 | $64 \times 32$ | 8,320 B | 10,240 | 640 B |
| **`context.1.pw`** | Pointwise Conv1D (1×1) | $64 \times 32$ | **1** | 1 | 1 | 0 | $64 \times 32$ | 128 B | 131,072 | 8,192 B |
| **`GAP`** | Global Average Pooling | $64 \times 32$ | — | — | — | — | $64 \times 1$ | — | 64 | 0 B |
| **`FC`** | Linear Classifier | $64 \times 1$ | **1** | — | — | — | $2 \times 1$ (Logits) | — | 128 | 256 B |
| **Total** | | | | | | | | **~13.3 KiB** | **489,600** | **~23.0 KiB** |

> **Note on MACs Counting:** Software profilers (e.g., `thop`) report **585,920 MACs** because they count separate BatchNorm and activation operations. In actual hardware, BatchNorm is folded into the Conv layer weights/biases, resulting in **489,600 hardware MACs**.

---

## 3. Hardware Architecture Overview

The accelerator implements an **Instruction-Driven, Output-Stationary (OS)** datapath tailored for 1D streaming tensors:

* **Instruction-Based Controller:** Sequences through each neural network layer by decoding 64-bit micro-instructions from an on-chip Instruction Memory, eliminating host CPU polling across layer boundaries.
* **Output-Stationary Processing Element (PE) Array:** Partial sums are accumulated locally in wide 48-bit internal accumulators until each output channel point is fully resolved, minimizing memory read/write energy.
* **Configurable Convolution Engine:** Unified hardware execution for:
  * Standard 1D Convolution ($K=7$).
  * Depthwise Separable 1D Convolution ($K=5$).
  * Pointwise 1D Convolution ($K=1$).
  * Dense Linear Classification (Matrix-Vector multiplication).
* **Sliding Line Buffer:** Stream-buffers temporal samples to service multi-tap convolutions across varying dilation rates ($dil \in \{1, 2, 4, 8, 16\}$) with single-pass data reuse.
* **On-Chip Ping-Pong Banking:** Interleaved dual-port SRAM banks to enable simultaneous feature map calculation and DMA transfer across AXI interfaces.

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
