# Model-to-Hardware Deliverables & Interface Specification

This document outlines the required artifacts, data formats, and handoff deliverables from the **AI Modeling Team** to the **RTL Hardware Team** to enable bit-exact verification and physical deployment of the **`WearSeizure-1D` (`wearseizure1d_k5only`)** accelerator on the **AMD-Xilinx Kria KV260**.

---

## 1. Required Deliverables Checklist

To complete full-system verification on the hardware accelerator, the modeling team is requested to provide the following four core deliverables:

| Item | Deliverable | Target Location | Description |
| :---:| :--- | :--- | :--- |
| **1** | **Quantized Weights & Biases** | `model/weights/*.txt` | **REQUIRED FROM MODELING TEAM:** Plain ASCII hex text files of DFP8 parameters with BatchNorm mathematically folded into Conv (total ~11.5 KiB). *Note: Binary `.pt` checkpoints remain in `WearSeizure-1D` and are excluded from Git.* |
| **2** | **Golden Model Simulator** | `model/golden_model.py` | Standalone Python/NumPy script implementing bit-exact fixed-point hardware datapath (no PyTorch dependencies required). |
| **3** | **Verification Test Vectors** | `model/test_vectors/*.txt` | Plain ASCII hex text files for the raw EEG input, 13 hardware layer outputs, and software classification outputs. |
| **4** | **Per-Layer Quantization Parameter Table** | `model/manifest.json` | **REQUIRED FROM MODELING TEAM:** Exact per-layer fractional bit shifts ($p_{\text{in}}, p_w, p_{\text{out}}$) and `output_shift` derived from calibration data. *(Currently committed values are STUB / TEMPLATE placeholders for RTL testing).* |

---

## 2. Detailed Deliverable Specifications

### 2.1 Quantized Weights & Biases (`model/weights/*.txt`) vs. Binary Checkpoint (`.pt`)
* **Git Cleanliness Policy:** Binary checkpoint files (`*.pt`, `*.pth`, `*.bin`) are explicitly **excluded from Git tracking via `.gitignore`** to avoid repository bloat and binary merge conflicts.
* **Extraction Workflow:** The modeling team (or hardware engineer with local model access) executes:
  ```bash
  python model/export_weights.py --checkpoint /path/to/wearseizure1d_k5only_best.pt
  ```
* **Hardware Ready:** `export_weights.py` automatically folds BatchNorm into preceding Conv weights/biases, scales them to signed 8-bit DFP8 ($p_w = 7$), and outputs 2-character uppercase hexadecimal strings into `model/weights/`. These files are directly consumed by Verilog `$readmemh` in hardware simulation and FPGA BRAM initialization.

### 2.2 Golden Model Simulator (`golden_model.py`)
* **Purpose:** Serves as the golden numerical reference for the RTL testbench and debugging pipeline failures without requiring a full machine learning runtime.
* **Requirements:**
  * **Zero Heavy Dependencies:** Implemented using pure Python or NumPy only (no PyTorch, CUDA, or heavy ML libraries).
  * **Bit-Accurate Arithmetic:** Exactly mimics the hardware PE datapath: signed 8-bit multiplication, 32-bit accumulator, arithmetic right shift (`>>> shift`), and 8-bit symmetric saturation clamp (`[-128, 127]`).
  * **Debug & Waveform Alignment:** Allows dumping intermediate values at any cycle or generating custom corner-case vectors (e.g. all-zeros, maximum saturation, impulse spikes) to debug waveform mismatches in GTKWave.

### 2.3 Layer-by-Layer Test Vectors (`model/test_vectors/`)
All test vectors should be formatted as 2-character uppercase hexadecimal strings (one 8-bit signed byte per line). The hardware accelerator executes layers 1 through 13, and the ARM host CPU performs GAP and FC in software:

| Filename | Producing Layer | Execution Target | Tensor Shape ($C \times L$) | Word Count |
| :--- | :--- | :---: | :---:| :---:|
| `00_input_eeg.txt` | Pre-filtered EEG input window | Input Stream | $1 \times 1024$ | 1,024 |
| `01_stem_out.txt` | `stem.0` (Conv1D) | **FPGA RTL** | $8 \times 512$ | 4,096 |
| `02_b1_dw_out.txt` | `b1.dw` (Depthwise) | **FPGA RTL** | $8 \times 256$ | 2,048 |
| `03_b1_pw_out.txt` | `b1.pw` (Pointwise) | **FPGA RTL** | $16 \times 256$ | 4,096 |
| `04_b2_dw_out.txt` | `b2.dw` (Depthwise, $dil=1$) | **FPGA RTL** | $16 \times 128$ | 2,048 |
| `05_b2_pw_out.txt` | `b2.pw` (Pointwise) | **FPGA RTL** | $24 \times 128$ | 3,072 |
| `06_b3_dw_out.txt` | `b3.dw` (Depthwise, $dil=2$) | **FPGA RTL** | $24 \times 64$ | 1,536 |
| `07_b3_pw_out.txt` | `b3.pw` (Pointwise) | **FPGA RTL** | $32 \times 64$ | 2,048 |
| `08_b4_dw_out.txt` | `b4.dw` (Depthwise, $dil=4$) | **FPGA RTL** | $32 \times 32$ | 1,024 |
| `09_b4_pw_out.txt` | `b4.pw` (Pointwise) | **FPGA RTL** | $48 \times 32$ | 1,536 |
| `10_context_0_dw_out.txt` | `context.0.dw` (Depthwise, $dil=8$) | **FPGA RTL** | $48 \times 32$ | 1,536 |
| `11_context_0_pw_out.txt` | `context.0.pw` (Pointwise) | **FPGA RTL** | $64 \times 32$ | 2,048 |
| `12_context_1_dw_out.txt` | `context.1.dw` (Depthwise, $dil=16$) | **FPGA RTL** | $64 \times 32$ | 2,048 |
| `13_context_1_pw_out.txt` | `context.1.pw` (Pointwise) | **FPGA RTL (Final HW Out)** | $64 \times 32$ | 2,048 |
| `14_gap_out.txt` | `gap` (Global Average Pooling) | *ARM Software* | $64 \times 1$ | 64 |
| `15_logits_output.txt` | `fc` (Classification Logits) | *ARM Software* | $2 \times 1$ | 2 |

### 2.4 Quantization Metadata, Scaling & Microcode (`manifest.json` & `instructions.hex`)

* **Quantization Status:** **CALIBRATED**. Per-layer fractional exponents ($p_{\text{in}}, p_w, p_{\text{out}}$) and `output_shift` ($5 \le \text{shift} \le 7$) are empirically measured from the trained model checkpoint (`chb01__chb01_03`, L1+L8 fold) and validation activations.
* **Microcode Encoding:** The 64-bit microcode in `model/instructions.hex` contains **exactly 13 instructions** compiled via `model/generate_instructions.py`:
  * **Bit `[2]` (`RELU_EN`):** Fused Activation control (`1` for layers with fused ReLU, `0` for linear/bypass layers).
  * **Bits `[4:3]` (`PAD_UPPER`):** Upper 2 bits of padding for $P > 15$ (e.g. $P=16$ for `context.0.dw`, $P=32$ for `context.1.dw`).
  * **Bits `[11:5]` (`RESERVED`):** 7 reserved flag bits for future acceleration features.
  * **Bits `[27:22]` (`OUTPUT_SHIFT`):** 6-bit per-layer arithmetic right-shift amount matching `Fixed_Point_Quantizer.v`.

---

## 3. Existing References in `WearSeizure-1D` and Baseline RTL

The following components and specifications are **already finalized and documented** in the modeling and reference repositories, so they do **not** need to be reinvented:

### 3.1 Signal Preprocessing & Streaming Contract
* **Causal Bandpass Filter:** Defined in [`WearSeizure-1D/src/wearseizure/signal/filters.py`](../../WearSeizure-1D/src/wearseizure/signal/filters.py).
  * Implementation: 4th-order Butterworth bandpass (1.0 Hz to 30.0 Hz at $f_s = 256\text{ Hz}$).
  * Execution: Strictly causal via `scipy.signal.lfilter`, with per-EDF filter state $z_i$ reset at recording boundaries (no non-causal `filtfilt`).
* **Affine Normalizer:** Defined in [`WearSeizure-1D/src/wearseizure/signal/normalize.py`](../../WearSeizure-1D/src/wearseizure/signal/normalize.py).
  * Memoryless streaming affine transformation: $(x - \text{bias}) \times \text{scale}$.
  * Parameters: Robust median / MAD statistics fitted on the training partition.
* **I/O Interface Contract:** Specified in [`WearSeizure-1D/src/wearseizure/rtl_interface/golden_io_contract.py`](../../WearSeizure-1D/src/wearseizure/rtl_interface/golden_io_contract.py) and [`spec.md`](../../WearSeizure-1D/src/wearseizure/rtl_interface/spec.md).
  * Input window: 1024 samples (4.0 s @ 256 Hz), 16-bit signed sample stream with `tlast` assertion on sample 1023.

### 3.2 Clinical Benchmark & Architecture Sizing
* **Benchmark Consolidation:** Defined in [`WearSeizure-1D/docs/HARDWARE_HANDOFF.md`](../../WearSeizure-1D/docs/HARDWARE_HANDOFF.md) and [`docs/RESEARCH_REALITY_CHECK.md`](../../WearSeizure-1D/docs/RESEARCH_REALITY_CHECK.md).
  * **Selected Architecture:** `wearseizure1d_k5only` (1 Stem, 4 Inverted Bottlenecks with $K=5$, 2 Context blocks with dilations 8 and 16, GAP, Linear classifier).
  * **Clinical Metrics:** Sensitivity Macro: 0.9358 (L1) / 0.9489 (L1+L8); FAR/h: 0.2216 (L1) / 0.1904 (L1+L4); Detection latency: ~17.8 – 18.8 s.
  * **Complexity:** 11,786 parameters, 489,600 hardware MACs (fused Conv+BN, compared to 585,920 software `thop` operations).
  * **SRAM Footprint:** Total on-chip storage ~18.2 KiB (well within the Kria KV260 / ZU5EV on-chip SRAM capacity).

### 3.3 Hardware Baseline Reference
* **Reference RTL Path:** [`AI-Accelerator-RTL/reference/Configurable_AI_Accelerator-OS/rtl/`](../reference/Configurable_AI_Accelerator-OS/rtl/)
  * Contains the 14 baseline modules of the 1D-CNN Output-Stationary architecture (`CNN_1D_Core.v`, `PEA.v`, `Line_Buffer.v`, `Controller.v`, `Ping_Pong_FMAP_Bank_Memory.v`, `Weight_Bank_Memory.v`, `Bias_Bank_Memory.v`, etc.).
  * All upcoming accelerator optimizations (multi-dilation Line Buffer for $K=5, dil \in \{1, 2, 4, 8, 16\}$, stride 2 subsampling, 64-bit microcode decoding) will be developed and verified against this baseline.

