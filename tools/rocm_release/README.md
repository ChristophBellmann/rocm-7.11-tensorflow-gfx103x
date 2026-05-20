# ROCm release helpers

This directory is the packaging entrypoint for the custom gfx103x TensorFlow
ROCm wheel flow.

## Shared ROCm 7.11 framework policy

Framework packaging ownership is split by fork:

- PyTorch wheel family and deterministic project venvs:
  `rocm-7.11-pytorch-gfx103x/tools/rocm_release/`
- ONNX Runtime wheel family:
  `rocm-7.11-onnxruntime-gfx103x/tools/rocm_release/`
- TensorFlow wheel family:
  this directory
- TheRock/base repo:
  ROCm stack build plus integration/validation only

TensorFlow keeps its own isolated build/runtime dependency policy. Do not apply
the PyTorch project-venv helper to TensorFlow.

Current TensorFlow default policy:

```text
TF_BUILD_NUMPY_SPEC='numpy>=2,<3'
TF_BUILD_PROTOBUF_SPEC='protobuf<7'
TF_RUNTIME_NUMPY_SPEC='numpy>=2,<3'
TF_RUNTIME_PROTOBUF_SPEC='protobuf<7'
```

Those defaults are the intended ABI/dependency contract for the custom gfx103x
TensorFlow wheel. Override both build and runtime specs explicitly only when
running a separate compatibility experiment.

## Build repo-local

```bash
tools/rocm_release/build_tensorflow_rocm_wheel.sh
```

Useful overrides:

```bash
ROCM_PATH=/path/to/custom/rocm \
JOBS=24 \
tools/rocm_release/build_tensorflow_rocm_wheel.sh
```

The release wrapper writes a TensorFlow-specific pip constraints file and exports
`PIP_CONSTRAINT` before calling the large upstream-oriented build script. This
makes direct pip calls inside the build honor the selected TensorFlow ABI policy
without duplicating the build implementation.

Alternative NumPy policy, only for an explicit rebuild/validation campaign:

```bash
TF_BUILD_NUMPY_SPEC='numpy<2' \
TF_RUNTIME_NUMPY_SPEC='numpy<2' \
ROCM_PATH=/path/to/custom/rocm \
tools/rocm_release/build_tensorflow_rocm_wheel.sh
```

Default repo-local outputs:

- build workspace: `./.rocm_release/builds/tensorflow_rocm`
- wheel cache: `./.rocm_release/wheels/tensorflow_rocm_custom`
- build constraints: `./.rocm_release/constraints/tensorflow-build-constraints.txt`

Canonical override:

- `RELEASE_ROOT=/path/to/release-state`

Compatibility note:

- existing legacy state under `./.rocm_release/build/tensorflow_rocm` is still accepted
  if present, but new runs should use `./.rocm_release/builds/tensorflow_rocm`.

## Promote to /opt/rocm

```bash
sudo tools/rocm_release/install_tensorflow_rocm_wheel_to_opt.sh
```

The helper copies the newest wheel from the repo-local release cache unless an
explicit wheel path is given.

Promoted destination:

- `/opt/rocm/wheels/tensorflow_rocm_custom/`
- stable symlink: `/opt/rocm/wheels/tensorflow_rocm_custom/tensorflow-current.whl`

## Deterministic TensorFlow runtime venv

Use the TensorFlow-specific helper, not the PyTorch helper:

```bash
tools/rocm_release/create_tensorflow_rocm_venv.sh \
  --venv .venv-tf \
  --rocm-prefix /opt/rocm \
  -y
```

The helper owns the old manual ordering workaround:

1. install TensorFlow-specific NumPy/protobuf specs
2. install the custom TensorFlow wheel through a generated constraints file
3. re-assert TensorFlow-specific NumPy/protobuf specs
4. write `python-tf-rocm` and `pip-tf-rocm` wrappers
5. optionally patch normal venv activation
6. run a TensorFlow ROCm GPU smoke test

For extra packages:

```bash
.venv-tf/bin/pip-tf-rocm install <package>
```

Supported runtime entrypoints:

```bash
source .venv-tf/bin/activate
python -c 'import tensorflow as tf; print(tf.config.list_physical_devices("GPU"))'

.venv-tf/bin/python-tf-rocm -c 'import tensorflow as tf; print(tf.config.list_physical_devices("GPU"))'
```

This repo owns TensorFlow build/promote/runtime helper behavior. TheRock
validation only consumes and validates the resulting wheels.
