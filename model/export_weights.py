#!/usr/bin/env python3
"""export_weights.py

Framework to extract weights from a trained PyTorch checkpoint (.pt / .pth),
perform BatchNorm folding, quantize to signed 16-bit DFP16, and generate
hex files for RTL simulation.

Usage:
    python export_weights.py --checkpoint path/to/checkpoint.pt
"""

import argparse
import json
import os
import sys
from pathlib import Path

MODEL_DIR = Path(__file__).parent
MANIFEST_PATH = MODEL_DIR / "manifest.json"
WEIGHTS_DIR = MODEL_DIR / "weights"


def fold_bn_weights(conv_w, conv_b, bn_gamma, bn_beta, bn_mean, bn_var, eps=1e-5):
    """Fuses BatchNorm into Conv weights and biases.
    W_fused = W * (gamma / sqrt(var + eps))
    B_fused = (B - mean) * (gamma / sqrt(var + eps)) + beta
    """
    import numpy as np

    std = np.sqrt(bn_var + eps)
    scale = bn_gamma / std

    # Reshape scale for broadcasting: (out_channels, 1, 1) or (out_channels, 1)
    if conv_w.ndim == 3:
        scale_reshaped = scale.reshape(-1, 1, 1)
    elif conv_w.ndim == 2:
        scale_reshaped = scale.reshape(-1, 1)
    else:
        scale_reshaped = scale

    w_fused = conv_w * scale_reshaped

    if conv_b is None:
        b_init = np.zeros_like(bn_mean)
    else:
        b_init = conv_b

    b_fused = (b_init - bn_mean) * scale + bn_beta
    return w_fused, b_fused


def to_hex16(val: int) -> str:
    """Formats a signed integer as a 4-character uppercase hex string (two's complement)."""
    val_clamped = max(-32768, min(32767, int(round(val))))
    return f"{val_clamped & 0xFFFF:04X}"


def to_hex32(val: int) -> str:
    """Formats a signed integer as an 8-character uppercase hex string (two's complement)."""
    val_clamped = max(-2147483648, min(2147483647, int(round(val))))
    return f"{val_clamped & 0xFFFFFFFF:08X}"


def main():
    parser = argparse.ArgumentParser(description="Export weights from PyTorch checkpoint to DFP16 hex files.")
    parser.add_argument("--checkpoint", type=str, required=False, default=None,
                        help="Path to the trained PyTorch checkpoint (.pt / .pth)")
    parser.add_argument("--output_dir", type=str, default=str(WEIGHTS_DIR),
                        help="Destination directory for exported hex files")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if not args.checkpoint or not os.path.isfile(args.checkpoint):
        print("=" * 70)
        print("[NOTICE] export_weights.py: Ready to extract weights.")
        print("No trained checkpoint was specified or the file does not exist.")
        print()
        print("When the model training team provides the checkpoint file, run:")
        print(f"    python {Path(__file__).name} --checkpoint path/to/model_best.pt")
        print()
        print("This script will automatically:")
        print("  1. Load the PyTorch checkpoint state dictionary.")
        print("  2. Fold BatchNorm layers into Conv1D weights and biases.")
        print("  3. Quantize parameters to INT16 / DFP16 according to manifest.json.")
        print(f"  4. Write individual hex files and all_weights.hex to {out_dir.name}/")
        print("=" * 70)
        return 0

    try:
        import torch
        import numpy as np
    except ImportError:
        print("[ERROR] PyTorch and NumPy are required to extract weights from .pt checkpoints.")
        print("Please install them with: pip install torch numpy")
        return 1

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    print(f"Loading checkpoint: {args.checkpoint}")
    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    state_dict = checkpoint.get("state_dict", checkpoint)

    all_weights_flat = []

    # Map state_dict keys for wearseizure1d_k5only
    LAYER_MAPPING = [
        # (layer_id, name, conv_w_key, conv_b_key, bn_prefix)
        (1, "stem.0", "stem.0.weight", None, "stem.1"),
        (2, "b1.dw", "b1.depthwise.weight", None, None),
        (3, "b1.pw", "b1.pointwise.weight", None, "b1.bn"),
        (4, "b2.dw", "b2.branch_k5.weight", None, "b2.bn_dw"),
        (5, "b2.pw", "b2.pointwise.weight", None, "b2.bn_pw"),
        (6, "b3.dw", "b3.branch_k5.weight", None, "b3.bn_dw"),
        (7, "b3.pw", "b3.pointwise.weight", None, "b3.bn_pw"),
        (8, "b4.dw", "b4.branch_k5.weight", None, "b4.bn_dw"),
        (9, "b4.pw", "b4.pointwise.weight", None, "b4.bn_pw"),
        (10, "context.0.dw", "context.0.depthwise.weight", None, None),
        (11, "context.0.pw", "context.0.pointwise.weight", None, "context.0.bn"),
        (12, "context.1.dw", "context.1.depthwise.weight", None, None),
        (13, "context.1.pw", "context.1.pointwise.weight", None, "context.1.bn"),
        (14, "gap", None, None, None),
        (15, "fc", "classifier.weight", "classifier.bias", None),
    ]

    print("Extracting, folding, and quantizing layers:")

    for layer_id, name, conv_w_key, conv_b_key, bn_prefix in LAYER_MAPPING:
        if name == "gap":
            continue

        meta = next(l for l in manifest["layers"] if l["layer_id"] == layer_id)
        p_w = meta.get("p_weight", 14)
        p_in = meta.get("p_in", 13)
        p_bias = p_in + p_w

        # Extract conv weight
        w_tensor = state_dict[conv_w_key].detach().cpu().numpy()
        b_tensor = state_dict[conv_b_key].detach().cpu().numpy() if conv_b_key else None

        # Fold BatchNorm if present
        if bn_prefix:
            gamma = state_dict[f"{bn_prefix}.weight"].detach().cpu().numpy()
            beta = state_dict[f"{bn_prefix}.bias"].detach().cpu().numpy()
            mean = state_dict[f"{bn_prefix}.running_mean"].detach().cpu().numpy()
            var = state_dict[f"{bn_prefix}.running_var"].detach().cpu().numpy()
            w_fused, b_fused = fold_bn_weights(w_tensor, b_tensor, gamma, beta, mean, var)
        else:
            w_fused = w_tensor
            b_fused = b_tensor if b_tensor is not None else np.zeros(w_tensor.shape[0])

        # Quantize weights to 16-bit DFP16
        w_scale = 2.0 ** p_w
        w_q = np.clip(np.round(w_fused * w_scale), -32768, 32767).astype(np.int64)

        # Quantize biases to 32-bit (accumulator scale)
        b_scale = 2.0 ** p_bias
        b_q = np.clip(np.round(b_fused * b_scale), -2147483648, 2147483647).astype(np.int64)

        # Write to hex files
        safe_name = name.replace(".", "_")
        w_file = out_dir / f"{layer_id:02d}_{safe_name}_weights.txt"
        b_file = out_dir / f"{layer_id:02d}_{safe_name}_bias.txt"

        with open(w_file, "w", encoding="utf-8") as wf:
            for val in w_q.flatten():
                wf.write(f"{to_hex16(val)}\n")
                all_weights_flat.append(val)

        with open(b_file, "w", encoding="utf-8") as bf:
            for val in b_q.flatten():
                bf.write(f"{to_hex32(val)}\n")

        print(f"  [{layer_id:02d}] {name:<14}: {w_q.size:>5d} weights -> {w_file.name}")

    # Write combined master hex
    master_file = out_dir / "all_weights.hex"
    with open(master_file, "w", encoding="utf-8") as mf:
        for val in all_weights_flat:
            mf.write(f"{to_hex16(val)}\n")

    print(f"\n[OK] Weight extraction complete! Total parameters: {len(all_weights_flat)}")
    print(f"Master file saved at: {master_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
