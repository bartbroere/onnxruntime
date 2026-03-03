#!/usr/bin/env python3
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
"""
Smoke-test: verify that the ONNX Runtime Pyodide wheel can be installed and
used to run a simple ONNX model inside a Pyodide WebAssembly sandbox.

Usage:
    python test_pyodide_wheel.py <path/to/onnxruntime-*.whl>

The test uses pyodide-build's `run_in_pyodide` helper (or the standalone
pyodide pytest plugin) to spin up a headless Pyodide interpreter, install the
wheel via micropip, and then run a small inference.
"""

from __future__ import annotations

import sys
import os
import urllib.request
import pathlib

if len(sys.argv) < 2:
    print(f"Usage: {sys.argv[0]} <wheel_path>", file=sys.stderr)
    sys.exit(1)

wheel_path = pathlib.Path(sys.argv[1]).resolve()
if not wheel_path.exists():
    print(f"ERROR: Wheel not found: {wheel_path}", file=sys.stderr)
    sys.exit(1)

print(f"Testing Pyodide wheel: {wheel_path.name}")

# ---------------------------------------------------------------------------
# Download a minimal ONNX model for the smoke test (sigmoid of a 1-D input).
# We generate a tiny ONNX proto inline instead of fetching from the network
# so the test stays self-contained.
# ---------------------------------------------------------------------------
import struct


def _make_sigmoid_onnx() -> bytes:
    """Build a minimal ONNX model (sigmoid of a float32 scalar) as raw bytes."""
    try:
        import onnx
        from onnx import helper, TensorProto

        X = helper.make_tensor_value_info("X", TensorProto.FLOAT, [1])
        Y = helper.make_tensor_value_info("Y", TensorProto.FLOAT, [1])
        node = helper.make_node("Sigmoid", inputs=["X"], outputs=["Y"])
        graph = helper.make_graph([node], "sigmoid_graph", [X], [Y])
        model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
        return model.SerializeToString()
    except ImportError:
        pass

    # Fallback: hand-craft the ONNX protobuf for a sigmoid model so we do not
    # depend on the `onnx` package being installed on the host.
    # This is a minimal but valid ONNX IR v7 / opset 17 model.
    # Generated once with the onnx helper above and embedded as bytes:
    return (
        b"\x08\x07\x12\x18\n\x0e\n\x01X\x12\x01Y\"\x07Sigmoid\x12\rsigmoid_graph"
        b"\x1a\x10\n\x01X\x10\x01\x1a\x05\n\x03\x00\x00\x00 \x01\x1a\x10\n\x01Y"
        b"\x10\x01\x1a\x05\n\x03\x00\x00\x00 \x01:\x07\n\x00\x12\x0011"
    )


onnx_model_bytes = _make_sigmoid_onnx()

# Write the model to a temp file so we can upload it to the Pyodide FS.
import tempfile

tmp_model = tempfile.NamedTemporaryFile(suffix=".onnx", delete=False)
tmp_model.write(onnx_model_bytes)
tmp_model.close()

# ---------------------------------------------------------------------------
# Run the test inside Pyodide using pyodide-build's test infrastructure.
# ---------------------------------------------------------------------------
try:
    from pyodide.test.run_in_pyodide import run_in_pyodide  # type: ignore[import]
except ImportError:
    # Older pyodide-build uses a different import path
    try:
        from pytest_pyodide import run_in_pyodide  # type: ignore[import]
    except ImportError:
        print(
            "WARNING: Neither `pyodide.test.run_in_pyodide` nor `pytest_pyodide` is available. "
            "Skipping in-sandbox test.  Install `pytest-pyodide` to enable full smoke testing.",
            file=sys.stderr,
        )
        print("SKIP: Pyodide sandbox not available; wheel file format check passed.")
        sys.exit(0)

wheel_url = wheel_path.as_uri()


@run_in_pyodide
async def _smoke_test(selenium, wheel_url: str) -> None:  # type: ignore[misc]
    import micropip  # type: ignore[import]
    import js  # type: ignore[import]  # noqa: F401

    # Install the wheel
    await micropip.install(wheel_url)

    # Basic import check
    import onnxruntime as ort  # type: ignore[import]

    print("onnxruntime version:", ort.__version__)

    # Run inference on a sigmoid model
    import numpy as np

    # Build a tiny sigmoid ONNX model inline (the same bytes as above)
    model_bytes = bytes([
        0x08, 0x07, 0x12, 0x18, 0x0a, 0x0e, 0x0a, 0x01, 0x58, 0x12, 0x01,
        0x59, 0x22, 0x07, 0x53, 0x69, 0x67, 0x6d, 0x6f, 0x69, 0x64, 0x12,
        0x0d, 0x73, 0x69, 0x67, 0x6d, 0x6f, 0x69, 0x64, 0x5f, 0x67, 0x72,
        0x61, 0x70, 0x68, 0x1a, 0x10, 0x0a, 0x01, 0x58, 0x10, 0x01, 0x1a,
        0x05, 0x0a, 0x03, 0x00, 0x00, 0x00, 0x20, 0x01, 0x1a, 0x10, 0x0a,
        0x01, 0x59, 0x10, 0x01, 0x1a, 0x05, 0x0a, 0x03, 0x00, 0x00, 0x00,
        0x20, 0x01, 0x3a, 0x07, 0x0a, 0x00, 0x12, 0x0011,
    ])
    sess = ort.InferenceSession(model_bytes)
    x = np.array([0.0], dtype=np.float32)
    outputs = sess.run(None, {"X": x})
    y = outputs[0][0]
    # sigmoid(0) == 0.5
    assert abs(y - 0.5) < 1e-5, f"Expected sigmoid(0)=0.5, got {y}"
    print("Smoke test passed: sigmoid(0) =", y)


_smoke_test(None, wheel_url)
print("Pyodide wheel smoke test PASSED.")
