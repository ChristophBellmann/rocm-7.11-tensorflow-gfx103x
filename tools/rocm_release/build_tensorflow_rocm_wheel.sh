#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_ROOT="${RELEASE_ROOT:-${ROOT}/.rocm_release}"
WORK_ROOT="${WORK_ROOT:-${RELEASE_ROOT}/build/tensorflow_rocm}"
WHEEL_OUT_DIR="${WHEEL_OUT_DIR:-${RELEASE_ROOT}/wheels/tensorflow_rocm_custom}"
BUILD_LOG="${BUILD_LOG:-${RELEASE_ROOT}/logs/tensorflow_rocm_build.log}"

mkdir -p "${RELEASE_ROOT}/logs" "${WHEEL_OUT_DIR}"

export RELEASE_ROOT
export WORK_ROOT
export WHEEL_OUT_DIR
export BUILD_LOG

exec bash "${ROOT}/tools/gfx1031/build_rocm_wheel.sh"
