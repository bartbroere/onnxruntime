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
#   - pyodide-build is installed (pip install pyodide-build)
#   - The ONNX Runtime source tree is available
#   - cmake and ninja are on PATH
#
# Usage:
#   build_pyodide_wheel.sh [-v <pyodide_version>] [-c <Release|Debug>] [-o <output_dir>]

set -e -x

PYODIDE_VERSION="0.27.5"
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
# Step 1: Install pyodide-build and the cross-build environment
# ---------------------------------------------------------------------------
python3 -m pip install "pyodide-build==${PYODIDE_VERSION}"

echo "Installing Pyodide ${PYODIDE_VERSION} cross-build environment..."
python3 -m pyodide xbuildenv install "${PYODIDE_VERSION}"

# Obtain the path to the installed xbuildenv.  The directory layout is:
#   <xbuildenv_root>/
#     emsdk/              <- Emscripten SDK (with the version Pyodide was built with)
#     xbuildenv/
#       pyodide-env/
#         usr/include/python3.x/   <- Python headers for wasm32
XBUILDENV_ROOT="$(python3 -m pyodide xbuildenv path "${PYODIDE_VERSION}")"
echo "Pyodide xbuildenv root: ${XBUILDENV_ROOT}"

# ---------------------------------------------------------------------------
# Step 2: Activate the Emscripten toolchain bundled with the xbuildenv
# ---------------------------------------------------------------------------
EMSDK_DIR="${XBUILDENV_ROOT}/emsdk"
if [ ! -d "${EMSDK_DIR}" ]; then
  echo "ERROR: emsdk not found at ${EMSDK_DIR}. The pyodide xbuildenv may not have been installed correctly."
  exit 1
fi

# shellcheck source=/dev/null
source "${EMSDK_DIR}/emsdk_env.sh"

# Derive the Emscripten ABI tag (e.g. "emscripten_3_1_58") from the activated version.
EMSCRIPTEN_VERSION="$(emcc --version | head -1 | grep -oP '\d+\.\d+\.\d+')"
PYODIDE_ABI_VERSION="emscripten_$(echo "${EMSCRIPTEN_VERSION}" | tr '.' '_')"
echo "Emscripten version: ${EMSCRIPTEN_VERSION} -> ABI tag: ${PYODIDE_ABI_VERSION}"

# ---------------------------------------------------------------------------
# Step 3: Determine Python include directory from the xbuildenv sysroot
# ---------------------------------------------------------------------------
PYTHON_MAJOR_MINOR="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PYODIDE_SYSROOT="${XBUILDENV_ROOT}/xbuildenv/pyodide-env"
PYTHON_INCLUDE_DIR="${PYODIDE_SYSROOT}/usr/include/python${PYTHON_MAJOR_MINOR}"

if [ ! -d "${PYTHON_INCLUDE_DIR}" ]; then
  echo "WARNING: Expected Python include dir not found at ${PYTHON_INCLUDE_DIR}."
  echo "CMake will attempt to locate Python headers automatically."
  PYTHON_INCLUDE_DIR=""
fi

# ---------------------------------------------------------------------------
# Step 4: Build ONNX Runtime with Emscripten targeting Python (Pyodide)
# ---------------------------------------------------------------------------
BUILD_DIR="${ORT_ROOT}/build_pyodide"
mkdir -p "${BUILD_DIR}"

EXTRA_CMAKE_ARGS=""
if [ -n "${PYTHON_INCLUDE_DIR}" ]; then
  EXTRA_CMAKE_ARGS="-DPython3_INCLUDE_DIRS=${PYTHON_INCLUDE_DIR} -DPython_INCLUDE_DIRS=${PYTHON_INCLUDE_DIR}"
fi

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
  --disable_contrib_ops \
  --cmake_extra_defines \
    "FETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER" \
    ${EXTRA_CMAKE_ARGS}

# ---------------------------------------------------------------------------
# Step 5: Package the pybind11 module as a wasm32-emscripten wheel
# ---------------------------------------------------------------------------
# Copy the compiled .so into the expected location for setup.py
PYBIND_SO_SRC="${BUILD_DIR}/${BUILD_CONFIG}/onnxruntime_pybind11_state.so"
PYBIND_SO_DST="${ORT_ROOT}/onnxruntime/capi/onnxruntime_pybind11_state.so"

if [ ! -f "${PYBIND_SO_SRC}" ]; then
  echo "ERROR: Compiled pybind11 module not found at ${PYBIND_SO_SRC}"
  exit 1
fi

cp "${PYBIND_SO_SRC}" "${PYBIND_SO_DST}"

# Build the wheel, passing the Pyodide ABI tag via the environment
cd "${ORT_ROOT}"
export PYODIDE_ABI_VERSION="${PYODIDE_ABI_VERSION}"
python3 setup.py bdist_wheel \
  --use_pyodide \
  --dist-dir "${OUTPUT_DIR}"

echo "Pyodide wheel built successfully in ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"/*.whl
