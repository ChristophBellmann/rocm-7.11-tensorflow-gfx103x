# ROCm release helpers

This directory is the packaging entrypoint for the custom gfx103x TensorFlow
ROCm wheel flow.

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

Default repo-local outputs:

- build workspace: `./.rocm_release/builds/tensorflow_rocm`
- wheel cache: `./.rocm_release/wheels/tensorflow_rocm_custom`

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

This repo owns build/promote packaging. TheRock validation only consumes and
validates the resulting wheels.
