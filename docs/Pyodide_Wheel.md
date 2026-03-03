# ONNX Runtime Pyodide Wheel

ONNX Runtime provides a Python wheel for the [Pyodide](https://pyodide.org) runtime.
Pyodide runs CPython in the browser via WebAssembly, allowing Python code — including
machine learning inference — to execute client-side without a server.

The Pyodide wheel is compiled with [Emscripten](https://emscripten.org/) and tagged
`cp312-cp312-emscripten_3_1_58_wasm32` (Pyodide 0.27.x / Python 3.12). It can be
installed in a Pyodide environment with **micropip**:

```python
import micropip
await micropip.install("onnxruntime")
```

Or from a local / custom URL:

```python
await micropip.install(
    "https://example.com/onnxruntime-2.x.y-cp312-cp312-emscripten_3_1_58_wasm32.whl"
)
```

## Usage

```python
import onnxruntime as ort
import numpy as np

# Load a model (bytes or path supported by Pyodide's virtual filesystem)
sess = ort.InferenceSession("model.onnx")

# Run inference
inputs = {sess.get_inputs()[0].name: np.array([[1.0, 2.0, 3.0]], dtype=np.float32)}
outputs = sess.run(None, inputs)
print(outputs)
```

## Limitations

The Pyodide wheel is a minimal build of ONNX Runtime:

| Feature | Status |
|---------|--------|
| CPU Execution Provider | ✅ Included |
| ONNX format models | ✅ Supported |
| Contrib ops | ❌ Disabled (reduces binary size) |
| ML ops | ❌ Disabled (reduces binary size) |
| CUDA / GPU EPs | ❌ Not available in WebAssembly |
| Multi-threading | ⚠️ Requires `SharedArrayBuffer` (cross-origin isolation) |

## Building from source

### Prerequisites

- Linux or macOS (Windows is not supported for Pyodide builds)
- Python 3.12 (must match the Pyodide Python version)
- `cmake` and `ninja`
- `pyodide-build` installed: `pip install pyodide-build==0.27.5`

### Build

```bash
bash tools/ci_build/github/linux/build_pyodide_wheel.sh \
    -v 0.27.5 \
    -c Release \
    -o ./dist
```

Options:

| Flag | Default | Description |
|------|---------|-------------|
| `-v` | `0.27.5` | Target Pyodide version |
| `-c` | `Release` | Build configuration (`Release` or `Debug`) |
| `-o` | `/build/dist` | Output directory for the wheel |

Alternatively, invoke `build.py` directly for more control:

```bash
python tools/ci_build/build.py \
    --build_pyodide_wheel \
    --pyodide_version 0.27.5 \
    --build_dir build_pyodide \
    --config Release \
    --skip_tests \
    --disable_ml_ops \
    --disable_contrib_ops
```

## CI

The wheel is built automatically in the
[`pyodide-wheels`](.github/workflows/pyodide-wheels.yml) GitHub Actions workflow
on pushes to `main` and on release tags.
