#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#
# Build an ONNX Runtime Python wheel for Pyodide (wasm32-emscripten).
#
# The resulting wheel can be installed inside a Pyodide environment with micropip:
#   import micropip
#   await micropip.install("onnxruntime-<version>-cp312-cp312-emscripten_3_1_58_wasm32.whl")
#
# Prerequisites:
#   - Python 3.12 (must match the Python version embedded in the target Pyodide release)
#   - pyodide-build is installed (pip install pyodide-build)
#   - emsdk is installed and activated (emcc must be in PATH):
#       git clone https://github.com/emscripten-core/emsdk && cd emsdk
#       ./emsdk install 3.1.58 && ./emsdk activate 3.1.58 && source emsdk_env.sh
#   - cmake and ninja are on PATH
#
# Usage:
#   build_pyodide_wheel.sh [-v <pyodide_version>] [-c <Release|Debug>] [-o <output_dir>]

set -e -x

PYODIDE_VERSION="0.27.3"
BUILD_CONFIG="Release"
OUTPUT_DIR="/build/dist"

while getopts "v:c:o:" opt; do
  case "$opt" in
    v) PYODIDE_VERSION="$OPTARG" ;;
    c) BUILD_CONFIG="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    *) echo "Usage: $0 [-v <pyodide_version>] [-c <Release|Debug>] [-o <output_dir>]"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

mkdir -p "${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Step 1: Verify emcc is available
# ---------------------------------------------------------------------------
if ! command -v emcc &>/dev/null; then
  echo "ERROR: emcc not found in PATH. Install emsdk and run 'source emsdk_env.sh'."
  echo "Example:"
  echo "  git clone https://github.com/emscripten-core/emsdk"
  echo "  cd emsdk && ./emsdk install 3.1.58 && ./emsdk activate 3.1.58 && source emsdk_env.sh"
  exit 1
fi

EMSCRIPTEN_VERSION="$(emcc --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo "Emscripten version: ${EMSCRIPTEN_VERSION}"

# ---------------------------------------------------------------------------
# Step 2: Build ONNX Runtime and package the wasm32-emscripten wheel
# ---------------------------------------------------------------------------
# build.py handles: installing pyodide-build, setting up the xbuildenv,
# configuring CMake with the Emscripten toolchain, compiling, and packaging.
BUILD_DIR="${ORT_ROOT}/build_pyodide"
mkdir -p "${BUILD_DIR}"

python3 "${ORT_ROOT}/tools/ci_build/build.py" \
  --build_pyodide_wheel \
  --pyodide_version "${PYODIDE_VERSION}" \
  --build_dir "${BUILD_DIR}" \
  --config "${BUILD_CONFIG}" \
  --update \
  --build \
  --parallel \
  --skip_submodule_sync \
  --skip_tests \
  --disable_ml_ops \
  --disable_contrib_ops

# ---------------------------------------------------------------------------
# Step 3: Copy the wheel to the requested output directory
# ---------------------------------------------------------------------------
WHEEL_SRC_DIR="${BUILD_DIR}/${BUILD_CONFIG}/dist"
if ls "${WHEEL_SRC_DIR}"/*.whl 1>/dev/null 2>&1; then
  cp "${WHEEL_SRC_DIR}"/*.whl "${OUTPUT_DIR}/"
else
  echo "ERROR: No .whl found in ${WHEEL_SRC_DIR}"
  exit 1
fi

echo "Pyodide wheel built successfully in ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"/*.whl
