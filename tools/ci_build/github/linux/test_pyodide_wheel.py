"""Smoke test for the onnxruntime Pyodide wheel using pytest-pyodide.

Run with:
    ORT_PYODIDE_WHEEL=/path/to/onnxruntime-*.whl \\
    pytest tools/ci_build/github/linux/test_pyodide_wheel.py \\
      --rt=node \\
      --dist-dir ~/.pyodide-xbuildenv/<version>/xbuildenv/pyodide-root/dist/

Prerequisites:
    pip install pytest pytest-pyodide
    node must be on PATH
"""

import os
import pathlib


def _find_wheel_url() -> str:
    """Return a file:// URI for the ORT Pyodide wheel."""
    env = os.environ.get("ORT_PYODIDE_WHEEL")
    if env:
        return pathlib.Path(env).resolve().as_uri()
    # Fall back: look in dist/ at the repository root
    repo_root = pathlib.Path(__file__).parents[4]
    candidates = sorted(repo_root.glob("dist/onnxruntime-*.whl"))
    if candidates:
        return candidates[-1].as_uri()
    raise FileNotFoundError(
        "Pyodide wheel not found. Set the ORT_PYODIDE_WHEEL environment variable "
        "to the path of the built .whl file, or place it in dist/ at the repo root."
    )


WHEEL_URL = _find_wheel_url()


def test_onnxruntime_pyodide(selenium):
    """Install the ort wheel in Pyodide and run a sigmoid inference."""
    selenium.run_async(f"""
import micropip
await micropip.install("{WHEEL_URL}")
print("Installed onnxruntime wheel")

import onnxruntime as ort
print("onnxruntime version:", ort.__version__)

import numpy as np

# Minimal ONNX sigmoid model (ir_version=8, opset 17, float32[1] -> float32[1]).
# Encoded as raw protobuf bytes; verified with onnx.checker.check_model.
model_bytes = bytes([
    0x08, 0x08, 0x42, 0x04, 0x0a, 0x00, 0x10, 0x11, 0x3a, 0x36, 0x0a,
    0x0f, 0x0a, 0x01, 0x58, 0x12, 0x01, 0x59, 0x22, 0x07, 0x53, 0x69,
    0x67, 0x6d, 0x6f, 0x69, 0x64, 0x12, 0x01, 0x67, 0x5a, 0x0f, 0x0a,
    0x01, 0x58, 0x12, 0x0a, 0x0a, 0x08, 0x08, 0x01, 0x12, 0x04, 0x0a,
    0x02, 0x08, 0x01, 0x62, 0x0f, 0x0a, 0x01, 0x59, 0x12, 0x0a, 0x0a,
    0x08, 0x08, 0x01, 0x12, 0x04, 0x0a, 0x02, 0x08, 0x01,
])

sess = ort.InferenceSession(model_bytes)
x = np.array([0.0], dtype=np.float32)
outputs = sess.run(None, {{"X": x}})
y = float(outputs[0][0])
assert abs(y - 0.5) < 1e-5, f"Expected sigmoid(0)=0.5, got {{y}}"
print(f"Smoke test PASSED: sigmoid(0) = {{y}}")
""")
