# gfx1031 ROCm Wheel Build

This directory contains the repo-local build entrypoint for the `christoph/gfx1031-buildfixes` TensorFlow fork.

## Goal

Build a TensorFlow ROCm wheel against an already prepared ROCm installation or custom ROCm dist without relying on external TheRock build logic.

## Interface

Required input:

```bash
export ROCM_PATH=/path/to/rocm
```

Typical invocation:

```bash
tools/gfx1031/build_rocm_wheel.sh
```

Useful overrides:

```bash
WORK_ROOT=/tmp/tf-rocm-build \
WHEEL_OUT_DIR=$PWD/dist/wheels \
JOBS=24 \
TF_ENABLE_XLA=1 \
TF_ROCM_DISABLE_HIPBLASLT=1 \
TF_ROCM_USE_HIPBLASLT=0 \
TF_ROCM_DISABLE_HIPBLASLT_INIT=1 \
ROCM_PATH=/path/to/custom/rocm \
tools/gfx1031/build_rocm_wheel.sh
```

## Notes

- The script pins Bazel's ROCm configure environment to the requested `ROCM_PATH`.
- It disables generated `hipBLASLt` use in `local_config_rocm` for the gfx1031 profile.
- It postprocesses the produced wheel with `patchelf --rename-dynamic-symbols` so TensorFlow's bundled LLVM symbols do not interpose on ROCm COMGR / HIP at runtime.
- Default outputs are repo-local. Integrators may override `WORK_ROOT` and `WHEEL_OUT_DIR` to keep artifacts elsewhere.
