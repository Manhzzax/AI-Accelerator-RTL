#!/usr/bin/env python3
"""generate_instructions.py

Reads manifest.json and compiles the 13 hardware layers of WearSeizure-1D into 64-bit
micro-instructions (instructions.hex) for CNN_1D_Core. (Layers 14 GAP and 15 FC
are executed in software on the host ARM CPU).

NOTE (STUB / TEMPLATE):
    The current compiled output_shift values default to 7 (template).
    Once the AI modeling team provides the final PTQ calibration table,
    update manifest.json and re-run this script to generate the production microcode.
"""

import json
from pathlib import Path

MANIFEST_PATH = Path(__file__).parent / "manifest.json"
OUTPUT_HEX_PATH = Path(__file__).parent / "instructions.hex"

DILATION_ENCODING = {
    1: 0,
    2: 1,
    4: 2,
    8: 3,
    16: 4,
}

CONV_MODE_ENCODING = {
    "conv1d": 0,
    "pointwise": 0,
    "linear": 0,
    "depthwise": 1,
    "gap": 2,
}

STRIDE_ENCODING = {
    1: 0,
    2: 1,
}


def encode_instruction(layer: dict) -> int:
    """Encodes a single layer's hyperparameters into a 64-bit micro-instruction."""
    dil = DILATION_ENCODING.get(layer["dilation"], 0)
    conv_mode = CONV_MODE_ENCODING.get(layer["type"], 0)
    in_ch = layer["in_channels"] & 0x3FF
    out_ch = layer["out_channels"] & 0x3FF
    kernel = layer["kernel_size"] & 0xF
    stride = STRIDE_ENCODING.get(layer["stride"], 0)
    pad = layer["padding"] & 0xF
    out_shift = layer.get("output_shift", 7) & 0x3F
    src_fm_base = layer.get("src_fm_base", 0) & 0x3FF
    
    # Sub-fields inside [11:2]
    relu_en = 1 if layer.get("relu", False) else 0
    pad_upper = (layer["padding"] >> 4) & 0x3
    reserved_flags = 0

    src_sel = layer.get("src_fm_sel", 0) & 0x1
    dst_sel = layer.get("dst_fm_sel", 1) & 0x1

    inst = 0
    inst |= (dil & 0xF) << 60
    inst |= (conv_mode & 0x3) << 58
    inst |= (in_ch & 0x3FF) << 48
    inst |= (out_ch & 0x3FF) << 38
    inst |= (kernel & 0xF) << 34
    inst |= (stride & 0x3) << 32
    inst |= (pad & 0xF) << 28
    inst |= (out_shift & 0x3F) << 22
    inst |= (src_fm_base & 0x3FF) << 12
    inst |= (reserved_flags & 0x7F) << 5
    inst |= (pad_upper & 0x3) << 3
    inst |= (relu_en & 0x1) << 2
    inst |= (src_sel & 0x1) << 1
    inst |= (dst_sel & 0x1) << 0

    return inst


def main():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    instructions = []
    print(f"Compiling {len(manifest['layers'])} layers from {MANIFEST_PATH.name}...")

    for layer in manifest["layers"]:
        inst_64 = encode_instruction(layer)
        inst_hex = f"{inst_64:016X}"
        instructions.append(inst_hex)
        relu_str = "RELU" if layer.get("relu", False) else "NONE"
        print(f"  Layer {layer['layer_id']:02d} ({layer['name']:<14}): 0x{inst_hex} | "
              f"k={layer['kernel_size']} s={layer['stride']} dil={layer['dilation']} "
              f"in={layer['in_channels']} out={layer['out_channels']} shift={layer['output_shift']} "
              f"act={relu_str}")

    with open(OUTPUT_HEX_PATH, "w", encoding="utf-8") as f:
        is_stub = "STUB" in manifest.get("_quantization_status", "")
        if is_stub:
            f.write("// STUB / TEMPLATE: 13 64-bit micro-instructions generated with placeholder output_shift=7.\n")
            f.write("// Recompile via 'python model/generate_instructions.py' once final PTQ calibration parameters are delivered.\n")
        for hex_str in instructions:
            f.write(f"{hex_str}\n")

    print(f"\n[OK] Successfully wrote {len(instructions)} micro-instructions to {OUTPUT_HEX_PATH}")


if __name__ == "__main__":
    main()
