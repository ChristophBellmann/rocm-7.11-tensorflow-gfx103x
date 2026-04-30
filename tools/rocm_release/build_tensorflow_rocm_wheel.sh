#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_ROOT="${RELEASE_ROOT:-${ROOT}/.rocm_release}"
DEFAULT_WORK_ROOT="${RELEASE_ROOT}/builds/tensorflow_rocm"
LEGACY_WORK_ROOT="${RELEASE_ROOT}/build/tensorflow_rocm"
if [[ -z "${WORK_ROOT:-}" ]]; then
  if [[ -d "${DEFAULT_WORK_ROOT}" ]] || [[ ! -d "${LEGACY_WORK_ROOT}" ]]; then
    WORK_ROOT="${DEFAULT_WORK_ROOT}"
  else
    WORK_ROOT="${LEGACY_WORK_ROOT}"
  fi
fi
WHEEL_OUT_DIR="${WHEEL_OUT_DIR:-${RELEASE_ROOT}/wheels/tensorflow_rocm_custom}"
BUILD_LOG="${BUILD_LOG:-${RELEASE_ROOT}/logs/tensorflow_rocm_build.log}"

# TensorFlow has its own dependency/ABI policy. Keep it explicit and separate
# from the PyTorch/ONNX Runtime NumPy-2 policy until this TensorFlow wheel is
# rebuilt and validated under a different contract.
export TF_BUILD_NUMPY_SPEC="${TF_BUILD_NUMPY_SPEC:-numpy<2}"
export TF_BUILD_PROTOBUF_SPEC="${TF_BUILD_PROTOBUF_SPEC:-protobuf<7}"
export TF_RUNTIME_NUMPY_SPEC="${TF_RUNTIME_NUMPY_SPEC:-${TF_BUILD_NUMPY_SPEC}}"
export TF_RUNTIME_PROTOBUF_SPEC="${TF_RUNTIME_PROTOBUF_SPEC:-${TF_BUILD_PROTOBUF_SPEC}}"

mkdir -p "${RELEASE_ROOT}/logs" "${WHEEL_OUT_DIR}"

export RELEASE_ROOT
export WORK_ROOT
export WHEEL_OUT_DIR
export BUILD_LOG

exec bash "${ROOT}/tools/gfx1031/build_rocm_wheel.sh"
