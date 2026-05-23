"""
Converts a TF2 SavedModel to a TFLite file and prints output tensor details.
Usage:
    pip install tensorflow
    python ml/convert_to_tflite.py <path-to-folder-containing-saved_model.pb>

The output file is written to:
    assets/models/ssd_mobilenet_v2_int8.tflite
"""

import sys
import pathlib
import tensorflow as tf

if len(sys.argv) < 2:
    print("Usage: python convert_to_tflite.py <saved_model_dir>")
    sys.exit(1)

model_dir = sys.argv[1]
out_path = pathlib.Path(__file__).parent.parent / "assets" / "models" / "ssd_mobilenet_v2_int8.tflite"

print(f"Loading SavedModel from: {model_dir}")
print(f"Output will be written to: {out_path}")

# ── Attempt 1: pure TFLite ops + dynamic-range quantization ──────────────────
converter = tf.lite.TFLiteConverter.from_saved_model(str(model_dir))
converter.optimizations = [tf.lite.Optimize.DEFAULT]

try:
    tflite_model = converter.convert()
    method = "TFLite ops + dynamic-range quant"
except Exception as e:
    print(f"Pure TFLite conversion failed ({e}).")
    print("Retrying with TF select ops (larger model, same accuracy) ...")

    # ── Attempt 2: allow TF ops that have no TFLite equivalent ───────────────
    converter = tf.lite.TFLiteConverter.from_saved_model(str(model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter._experimental_lower_tensor_list_ops = False
    tflite_model = converter.convert()
    method = "TFLite ops + SELECT_TF_OPS fallback"

out_path.write_bytes(tflite_model)
size_kb = len(tflite_model) // 1024
print(f"\nConversion OK ({method}): {size_kb} KB → {out_path}\n")

# ── Print output tensor details so tflite_runner.dart can be verified ────────
interp = tf.lite.Interpreter(str(out_path))
interp.allocate_tensors()

print("Input tensors:")
for d in interp.get_input_details():
    print(f"  [{d['index']}] {d['name']}  shape={d['shape']}  dtype={d['dtype']}")

print("\nOutput tensors:")
for d in interp.get_output_details():
    print(f"  [{d['index']}] {d['name']}  shape={d['shape']}  dtype={d['dtype']}")
