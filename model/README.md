# WearSeizure-1D Model & Golden Reference Environment

This directory hosts the algorithmic model definitions, quantization specifications, weight parameters, and layer-by-layer verification vectors for the **`WearSeizure-1D` (`wearseizure1d_k5only`)** neural network, serving as the bridge between PyTorch algorithmic training and FPGA hardware acceleration on the **AMD-Xilinx Kria KV260 / KR260**.

---

## 1. Overview of `WearSeizure-1D`

`WearSeizure-1D` is a lightweight, depthwise-separable 1D Convolutional Neural Network engineered for real-time, ultra-low-power epileptic seizure detection from single-channel EEG signals (CHB-MIT clinical protocol):

* **Input:** Single-channel EEG window of **4.0 seconds (1024 samples)** sampled at **256 Hz**, pre-filtered via a causal 4th-order Butterworth bandpass filter (1.0 – 30.0 Hz).
* **Architecture:** 1 Standard Conv Stem + 4 Depthwise-Separable Blocks ($K=5$) + 2 Dilated Context Blocks ($dil \in \{8, 16\}$) + Global Average Pooling (GAP) + Linear Classifier.
* **Complexity:** **11,786 parameters** and **489,600 MACs** per inference window.
* **Output:** Binary classification logits ($2 \times 1$: Non-Seizure vs. Seizure).

---

## 2. Arithmetic Precision: INT8 / DFP8

To maximize energy efficiency, minimize SRAM footprint, and maintain clinical detection sensitivity (>94% event-level sensitivity), the model team standardizes on **8-bit Dynamic Fixed-Point (DFP8)** arithmetic.

### Format Characteristics

* **Word Format:** Signed 8-bit two's complement (`int8`, range: $[-128, +127]$).
* **Power-of-Two Scaling:** Each tensor $X$ is scaled by a dynamic power-of-two factor $S = 2^{-p}$, where $p$ is the fractional bit shift:
  $$\text{Real Value } x \approx q \times 2^{-p}, \quad q \in [-128, 127]$$
* **Hardware Shift-Based Requantization:** Unlike affine integer schemes that require full multiplier units for requantization ($M \times \text{acc}$), DFP requantization between consecutive layers is executed purely through **arithmetic right shifts**:
  $$\text{Output Shift Amount} = p_{\text{weight}} + p_{\text{in}} - p_{\text{out}}$$
  This maps directly onto the hardware core's 64-bit micro-instruction barrel shifter (`OUTPUT_SHIFT`).

### On-Chip Memory Sizing
At INT8 / DFP8 precision:
* **Weight Memory:** $11,786 \times 1\text{ Byte} \approx \mathbf{11.5\text{ KiB}}$.
* **Total On-Chip Footprint:** $\approx \mathbf{18.2\text{ KiB}}$ (11.5 KiB Weights + 6.7 KiB Line Buffers).
* **Resource Utilization:** Occupies only **~2.8%** of the 640 KiB Block RAM available on the Kria KV260/KR260 MPSoC (`xczu5ev`).

---

## 3. Mathematical Folding: Batch Normalization

During training, Batch Normalization (BN) stabilizes convergence. For zero-overhead hardware inference, BN parameters ($\gamma, \beta, \mu, \sigma^2, \epsilon$) are mathematically fused into the convolutional kernel weights and biases prior to quantization:

$$W_{\text{fused}} = \frac{\gamma}{\sqrt{\sigma^2 + \epsilon}} \cdot W_{\text{conv}}$$

$$B_{\text{fused}} = \beta + \frac{\gamma}{\sqrt{\sigma^2 + \epsilon}} \cdot (B_{\text{conv}} - \mu)$$

The hardware execution units process $W_{\text{fused}}$ and $B_{\text{fused}}$ directly, requiring no runtime division, square root, or dedicated normalization pipeline stages.

---

## 4. Directory Organization

```text
model/
├── README.md               # Model architecture & data format description (this file)
├── export_weights.py       # Extraction framework to fold BN & quantize checkpoint to 16-bit hex
├── generate_instructions.py# Microcode compiler assembling 64-bit microcode for CNN_1D_Core
├── instructions.hex        # Generated 64-bit micro-instructions for all 15 layers
├── manifest.json           # Layer metadata, tensor shapes, and fractional bit shifts
├── test_vectors/           # Bit-exact layer-by-layer verification vectors (from model team)
│   ├── 00_input_eeg.txt
│   ├── 01_stem_out.txt
│   ├── ...
│   └── 15_logits_output.txt
└── weights/                # Folded, quantized DFP8 parameter files (exported from checkpoint)
    ├── 01_stem_0_weights.txt
    ├── 01_stem_0_bias.txt
    ├── ...
    └── all_weights.hex
```

---

## 5. Interface File Specifications

### 5.1 Parameter & Activation Text Files (`.txt`)
All weights and intermediate feature maps are stored as plain ASCII text files formatted for direct loading into Verilog simulation via `$readmemh`:
* **Encoding:** Signed 8-bit two's complement represented as 2-character uppercase hexadecimal strings (`00` to `FF`). *(Biases are 32-bit signed values represented as 8-character hex strings `00000000` to `FFFFFFFF`).*
* **Format:** One hex word per line.
* **Ordering:** Channel-major, temporal-contiguous raster order.

**Example (8-bit Weights / Activations):**
```text
0A    // +10
7F    // +127 (Max positive)
F6    // -10
80    // -128 (Min negative)
```

### 5.2 Layer-by-Layer Verification Points
The full execution graph of `WearSeizure-1D` comprises 15 layer transformations. The reference golden flow traces each point to enable isolated hardware verification:

| ID | Layer Reference | Output Shape ($C \times L$) | Total Elements | 8-bit Size |
| :---:| :--- | :---:| :---:| :---:|
| `00` | Input EEG Window | $1 \times 1024$ | 1,024 | 1,024 B |
| `01` | `stem.0` (Conv1D) | $8 \times 512$ | 4,096 | 4,096 B |
| `02` | `b1.dw` (Depthwise) | $8 \times 256$ | 2,048 | 2,048 B |
| `03` | `b1.pw` (Pointwise) | $16 \times 256$ | 4,096 | 4,096 B |
| `04` | `b2.dw` (Depthwise) | $16 \times 128$ | 2,048 | 2,048 B |
| `05` | `b2.pw` (Pointwise) | $24 \times 128$ | 3,072 | 3,072 B |
| `06` | `b3.dw` (Depthwise) | $24 \times 64$ | 1,536 | 1,536 B |
| `07` | `b3.pw` (Pointwise) | $32 \times 64$ | 2,048 | 2,048 B |
| `08` | `b4.dw` (Depthwise) | $32 \times 32$ | 1,024 | 1,024 B |
| `09` | `b4.pw` (Pointwise) | $48 \times 32$ | 1,536 | 1,536 B |
| `10` | `context.0.dw` | $48 \times 32$ | 1,536 | 1,536 B |
| `11` | `context.0.pw` | $64 \times 32$ | 2,048 | 2,048 B |
| `12` | `context.1.dw` | $64 \times 32$ | 2,048 | 2,048 B |
| `13` | `context.1.pw` | $64 \times 32$ | 2,048 | 2,048 B |
| `14` | `gap` (Average Pooling) | $64 \times 1$ | 64 | 64 B |
| `15` | `fc` (Classification Logits) | $2 \times 1$ | 2 | 2 B |

### 5.3 Layer Metadata Schema (`manifest.json`)
To coordinate the fractional shift values ($p$) and memory offsets between software generation and RTL testbenches, the model directory utilizes a JSON metadata manifest:

```json
{
  "model_name": "WearSeizure-1D",
  "precision": "INT8/DFP8",
  "input_samples": 1024,
  "sampling_rate_hz": 256,
  "layers": [
    {
      "layer_id": 1,
      "name": "stem.0",
      "type": "conv1d",
      "in_channels": 1,
      "out_channels": 8,
      "kernel_size": 7,
      "stride": 2,
      "dilation": 1,
      "padding": 3,
      "weight_shift": 12,
      "output_shift": 11
    }
  ]
}
```
