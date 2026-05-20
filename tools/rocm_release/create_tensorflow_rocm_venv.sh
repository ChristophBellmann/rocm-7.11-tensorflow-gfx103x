#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_ROOT="${RELEASE_ROOT:-${ROOT}/.rocm_release}"
ROCM_PREFIX="${ROCM_PREFIX:-/opt/rocm}"
VENV_DIR="${VENV_DIR:-$HOME/.venvs/tensorflow-rocm-custom}"
SRC_DIR="${SRC_DIR:-${RELEASE_ROOT}/wheels/tensorflow_rocm_custom}"
WHEEL_PATH="${WHEEL_PATH:-}"
TF_NUMPY_SPEC="${TF_NUMPY_SPEC:-numpy>=2,<3}"
TF_PROTOBUF_SPEC="${TF_PROTOBUF_SPEC:-protobuf<7}"
CONSTRAINTS_PATH="${CONSTRAINTS_PATH:-}"
ASSUME_YES=0
DO_SMOKE=1
PATCH_ACTIVATE=1
INSTALL_PACKAGES=()

usage() {
  cat <<'USAGE'
Usage: create_tensorflow_rocm_venv.sh [options]

Options:
  --venv <dir>
  --wheel <path>
  --src-dir <dir>
  --rocm-prefix <dir>
  --numpy-spec <spec>       default: numpy>=2,<3
  --protobuf-spec <spec>    default: protobuf<7
  --constraints <path>
  --install <package>
  --no-smoke
  --no-activate-patch
  -y, --yes
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }
confirm() { (( ASSUME_YES )) && return 0; read -r -p "$1 [Y/n] " a; [[ "$a" =~ ^(|[Yy]|yes|YES)$ ]]; }
file_uri() { python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$1"; }

wheel_name() {
  python3 - <<'PY' "$1"
import email.parser, zipfile, sys
with zipfile.ZipFile(sys.argv[1]) as z:
    metas=[n for n in z.namelist() if n.endswith('.dist-info/METADATA')]
    if not metas:
        print('tensorflow')
    else:
        msg=email.parser.Parser().parsestr(z.read(metas[0]).decode('utf-8','replace'))
        print((msg.get('Name') or 'tensorflow').strip())
PY
}

find_wheel() {
  if [[ -n "$WHEEL_PATH" ]]; then
    [[ -f "$WHEEL_PATH" ]] || die "wheel not found: $WHEEL_PATH"
    readlink -f "$WHEEL_PATH"
    return
  fi
  if [[ -f "$ROCM_PREFIX/wheels/tensorflow_rocm_custom/tensorflow-current.whl" ]]; then
    readlink -f "$ROCM_PREFIX/wheels/tensorflow_rocm_custom/tensorflow-current.whl"
    return
  fi
  local f
  f="$(ls -1t "$SRC_DIR"/tensorflow*.whl "$SRC_DIR"/tensorflow_rocm_custom*.whl 2>/dev/null | head -n1 || true)"
  [[ -n "$f" ]] || die "no TensorFlow wheel found"
  readlink -f "$f"
}

patch_activate_idempotent() {
  local activate_path="$VENV_DIR/bin/activate"
  python3 - <<'PY' "$activate_path"
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text(encoding='utf-8')
start = '# >>> TensorFlow ROCm runtime >>>'
end = '# <<< TensorFlow ROCm runtime <<<'
block = f"""\n{start}\nif [ -n \"${{VIRTUAL_ENV:-}}\" ] && [ -f \"$VIRTUAL_ENV/bin/tensorflow_rocm_env.sh\" ]; then\n    . \"$VIRTUAL_ENV/bin/tensorflow_rocm_env.sh\"\nfi\n{end}\n"""
if start in text and end in text:
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    text = before.rstrip() + block + after.lstrip('\n')
else:
    text = text.rstrip() + block
p.write_text(text, encoding='utf-8')
PY
}

write_env() {
  local envf="$VENV_DIR/bin/tensorflow_rocm_env.sh"
  cat >"$envf" <<EOF
#!/usr/bin/env bash
export ROCM_PATH="$ROCM_PREFIX"
export HIP_PATH="\${HIP_PATH:-\$ROCM_PATH}"
export HSA_PATH="\${HSA_PATH:-\$ROCM_PATH}"
export PATH="\$ROCM_PATH/bin:\$ROCM_PATH/llvm/bin:\${PATH:-}"
export LD_LIBRARY_PATH="\$ROCM_PATH/lib:\$ROCM_PATH/lib64:\$ROCM_PATH/lib/host-math/lib:\$ROCM_PATH/lib/rocm_sysdeps/lib:\$ROCM_PATH/llvm/lib:\$ROCM_PATH/lib/llvm/lib:\${LD_LIBRARY_PATH:-}"
export TF_ROCM_DISABLE_HIPBLASLT="\${TF_ROCM_DISABLE_HIPBLASLT:-1}"
export TF_ROCM_USE_HIPBLASLT="\${TF_ROCM_USE_HIPBLASLT:-0}"
export TF_ROCM_DISABLE_HIPBLASLT_INIT="\${TF_ROCM_DISABLE_HIPBLASLT_INIT:-1}"
export TF_CPP_MIN_LOG_LEVEL="\${TF_CPP_MIN_LOG_LEVEL:-1}"
export TF_ROCM_CUSTOM_CONSTRAINTS="$CONSTRAINTS_PATH"
export TENSORFLOW_ROCM_VENV_RUNTIME=1
EOF
  chmod +x "$envf"

  cat >"$VENV_DIR/bin/python-tf-rocm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
D="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$D/tensorflow_rocm_env.sh"
exec "$D/python" "$@"
EOF
  chmod +x "$VENV_DIR/bin/python-tf-rocm"

  cat >"$VENV_DIR/bin/pip-tf-rocm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
D="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$D/tensorflow_rocm_env.sh"
if [[ "${1:-}" == "install" ]]; then
  shift
  exec "$D/python" -m pip install -c "$TF_ROCM_CUSTOM_CONSTRAINTS" "$@"
fi
exec "$D/python" -m pip "$@"
EOF
  chmod +x "$VENV_DIR/bin/pip-tf-rocm"

  cat >"$VENV_DIR/bin/activate_tensorflow_rocm.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
V="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$V/bin/activate"
source "$V/bin/tensorflow_rocm_env.sh"
EOF
  chmod +x "$VENV_DIR/bin/activate_tensorflow_rocm.sh"

  if (( PATCH_ACTIVATE )); then
    patch_activate_idempotent
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv) VENV_DIR="$2"; shift 2 ;;
    --wheel) WHEEL_PATH="$2"; shift 2 ;;
    --src-dir) SRC_DIR="$2"; shift 2 ;;
    --rocm-prefix) ROCM_PREFIX="$2"; shift 2 ;;
    --numpy-spec) TF_NUMPY_SPEC="$2"; shift 2 ;;
    --protobuf-spec) TF_PROTOBUF_SPEC="$2"; shift 2 ;;
    --constraints) CONSTRAINTS_PATH="$2"; shift 2 ;;
    --install) INSTALL_PACKAGES+=("$2"); shift 2 ;;
    --no-smoke) DO_SMOKE=0; shift ;;
    --no-activate-patch) PATCH_ACTIVATE=0; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -d "$ROCM_PREFIX" ]] || die "ROCM_PREFIX does not exist: $ROCM_PREFIX"
WHEEL="$(find_wheel)"
PROJECT="$(wheel_name "$WHEEL")"
[[ -n "$CONSTRAINTS_PATH" ]] || CONSTRAINTS_PATH="$VENV_DIR/tensorflow-rocm-constraints.txt"

cat <<EOF
== TensorFlow ROCm venv ==
venv       : $VENV_DIR
ROCm       : $ROCM_PREFIX
wheel      : $WHEEL
project    : $PROJECT
NumPy spec : $TF_NUMPY_SPEC
protobuf   : $TF_PROTOBUF_SPEC
constraints: $CONSTRAINTS_PATH
EOF
confirm "Proceed?" || exit 0

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  mkdir -p "$(dirname "$VENV_DIR")"
  python3 -m venv "$VENV_DIR"
fi
mkdir -p "$(dirname "$CONSTRAINTS_PATH")"
{
  echo "# Generated by create_tensorflow_rocm_venv.sh"
  echo "$TF_NUMPY_SPEC"
  echo "$TF_PROTOBUF_SPEC"
  echo "$PROJECT @ $(file_uri "$WHEEL")"
} >"$CONSTRAINTS_PATH"
write_env

PY="$VENV_DIR/bin/python-tf-rocm"
PIP="$VENV_DIR/bin/pip-tf-rocm"
"$PY" -m pip install -U pip setuptools wheel >/dev/null
"$PY" -m pip install --force-reinstall "$TF_NUMPY_SPEC" "$TF_PROTOBUF_SPEC"
"$PIP" install --force-reinstall "$WHEEL"
"$PY" -m pip install --force-reinstall "$TF_NUMPY_SPEC" "$TF_PROTOBUF_SPEC"

if ((${#INSTALL_PACKAGES[@]})); then
  "$PIP" install "${INSTALL_PACKAGES[@]}"
fi

"$PY" -m pip check || true

if (( DO_SMOKE )); then
  "$PY" - <<'PY'
import time
import numpy as np
import google.protobuf
import tensorflow as tf
print('numpy                 :', np.__version__)
print('protobuf              :', google.protobuf.__version__)
print('tensorflow            :', tf.__version__)
print('built_with_rocm       :', tf.test.is_built_with_rocm())
print('physical_gpus         :', tf.config.list_physical_devices('GPU'))
if not tf.test.is_built_with_rocm():
    raise SystemExit('ERROR: TensorFlow is not built with ROCm')
if not tf.config.list_physical_devices('GPU'):
    raise SystemExit('ERROR: no TensorFlow GPU device visible')
with tf.device('/GPU:0'):
    n=2048
    a=tf.random.uniform((n,n), dtype=tf.float16)
    b=tf.random.uniform((n,n), dtype=tf.float16)
    c=tf.linalg.matmul(a,b); c.numpy()
    t0=time.time()
    for _ in range(5):
        c=tf.linalg.matmul(a,b)
    c.numpy()
    dt=time.time()-t0
print(f'matmul fp16           : n={n} iters=5 wall={dt:.3f}s it/s={5/dt:.2f}')
PY
fi

cat <<EOF

Install complete.
Use:
  source "$VENV_DIR/bin/activate"
  python -c 'import tensorflow as tf; print(tf.config.list_physical_devices("GPU"))'

or:
  "$VENV_DIR/bin/python-tf-rocm" -c 'import tensorflow as tf; print(tf.config.list_physical_devices("GPU"))'

For extra packages:
  "$VENV_DIR/bin/pip-tf-rocm" install <package>
EOF
