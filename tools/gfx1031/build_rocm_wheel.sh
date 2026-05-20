#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_ROOT="${WORK_ROOT:-${ROOT}/.build/rocm_wheel}"
SYSLIBS_DIR="${SYSLIBS_DIR:-${WORK_ROOT}/syslibs}"
VENV_DIR="${VENV_DIR:-${WORK_ROOT}/.venv}"
PYTHON_BIN="${PYTHON_BIN:-}"
REQUESTED_ROCM_PATH="${ROCM_PATH:-}"
ROCM_PATH="${REQUESTED_ROCM_PATH:-/opt/rocm}"
JOBS="${JOBS:-$(nproc)}"
TF_ENABLE_XLA="${TF_ENABLE_XLA:-1}"
BAZEL_BIN_DIR="${BAZEL_BIN_DIR:-${WORK_ROOT}/bin}"
BAZELISK="${BAZELISK:-${BAZEL_BIN_DIR}/bazelisk}"
WHEEL_OUT_DIR="${WHEEL_OUT_DIR:-${ROOT}/dist/wheels}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${WORK_ROOT}/cache/xdg}"
BAZELISK_HOME="${BAZELISK_HOME:-${WORK_ROOT}/cache/bazelisk}"
BAZEL_OUTPUT_USER_ROOT="${BAZEL_OUTPUT_USER_ROOT:-${WORK_ROOT}/cache/bazel/output_user_root}"
CCACHE_DIR="${CCACHE_DIR:-${WORK_ROOT}/cache/ccache}"
BUILD_LOG="${BUILD_LOG:-${WORK_ROOT}/build.log}"
BAZEL_VERBOSE_FAILURES="${BAZEL_VERBOSE_FAILURES:-1}"

for var_name in WORK_ROOT SYSLIBS_DIR VENV_DIR BAZEL_BIN_DIR WHEEL_OUT_DIR XDG_CACHE_HOME BAZELISK_HOME BAZEL_OUTPUT_USER_ROOT CCACHE_DIR BUILD_LOG; do
  var_value="${!var_name}"
  if [[ "${var_value}" != /* ]]; then
    printf -v "${var_name}" '%s/%s' "${ROOT}" "${var_value}"
  fi
done
if [[ -z "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="${VENV_DIR}/bin/python"
elif [[ "${PYTHON_BIN}" != /* ]]; then
  PYTHON_BIN="${ROOT}/${PYTHON_BIN}"
fi

if [[ ! -d "${ROCM_PATH}" ]]; then
  echo "ERROR: ROCM_PATH does not exist: ${ROCM_PATH}" >&2
  exit 1
fi

mkdir -p "${WORK_ROOT}" "${SYSLIBS_DIR}" "${BAZEL_BIN_DIR}" "${WHEEL_OUT_DIR}" \
  "${XDG_CACHE_HOME}" "${BAZELISK_HOME}" "${BAZEL_OUTPUT_USER_ROOT}" "${CCACHE_DIR}"
mkdir -p "$(dirname "${BUILD_LOG}")"
: > "${BUILD_LOG}"
# Do not use tee process substitution here: long-lived Bazel helpers inherit the
# pipe FD and the script can appear hung after a successful build.
exec >> "${BUILD_LOG}" 2>&1

echo "Using TensorFlow repo: ${ROOT}"
echo "Using ROCM_PATH=${ROCM_PATH}"

export XDG_CACHE_HOME
export BAZELISK_HOME
export CCACHE_DIR

if [[ -e "/lib/x86_64-linux-gnu/libnuma.so.1" ]]; then
  ln -sfn /lib/x86_64-linux-gnu/libnuma.so.1 "${SYSLIBS_DIR}/libnuma.so"
  ln -sfn /lib/x86_64-linux-gnu/libnuma.so.1 "${SYSLIBS_DIR}/libnuma.so.1"
fi
export LIBRARY_PATH="${SYSLIBS_DIR}:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:${LIBRARY_PATH:-}"
export CCACHE_BASEDIR="${ROOT}"
export CCACHE_COMPILERCHECK=content

resolve_rocm_clang() {
  local path
  for path in \
    "${ROCM_PATH}/llvm/bin/clang" \
    "${ROCM_PATH}/lib/llvm/bin/clang"; do
    if [[ -x "${path}" ]]; then
      echo "${path}"
      return 0
    fi
  done
  return 1
}

resolve_rocm_clangxx() {
  local path
  for path in \
    "${ROCM_PATH}/llvm/bin/clang++" \
    "${ROCM_PATH}/lib/llvm/bin/clang++"; do
    if [[ -x "${path}" ]]; then
      echo "${path}"
      return 0
    fi
  done
  return 1
}

REAL_CLANG="${REAL_CLANG:-$(resolve_rocm_clang || true)}"
REAL_CLANGXX="${REAL_CLANGXX:-$(resolve_rocm_clangxx || true)}"
if [[ -z "${REAL_CLANG}" || -z "${REAL_CLANGXX}" ]]; then
  echo "ERROR: Required ROCm clang toolchain not found under ${ROCM_PATH}" >&2
  exit 1
fi

CCACHE_BIN="$(command -v ccache || true)"
CCACHE_CLANG_WRAPPER="${BAZEL_BIN_DIR}/clang_ccache_wrapper.sh"
CCACHE_CLANGXX_WRAPPER="${BAZEL_BIN_DIR}/clangxx_ccache_wrapper.sh"
if [[ -n "${CCACHE_BIN}" ]]; then
  cat > "${CCACHE_CLANG_WRAPPER}" <<WRAP
#!/usr/bin/env bash
exec "${CCACHE_BIN}" "${REAL_CLANG}" "\$@"
WRAP
  cat > "${CCACHE_CLANGXX_WRAPPER}" <<WRAP
#!/usr/bin/env bash
exec "${CCACHE_BIN}" "${REAL_CLANGXX}" "\$@"
WRAP
else
  cat > "${CCACHE_CLANG_WRAPPER}" <<WRAP
#!/usr/bin/env bash
exec "${REAL_CLANG}" "\$@"
WRAP
  cat > "${CCACHE_CLANGXX_WRAPPER}" <<WRAP
#!/usr/bin/env bash
exec "${REAL_CLANGXX}" "\$@"
WRAP
fi
chmod +x "${CCACHE_CLANG_WRAPPER}" "${CCACHE_CLANGXX_WRAPPER}"
export CC="${CCACHE_CLANG_WRAPPER}"
export CXX="${CCACHE_CLANGXX_WRAPPER}"

patch_rocm_crosstool_builtin_includes() {
  local clang_resource_dir crosstool_build real_clang_dir
  clang_resource_dir="$(${REAL_CLANG} --print-resource-dir 2>/dev/null || true)"
  real_clang_dir="$(cd "$(dirname "${REAL_CLANG}")" && pwd)"
  crosstool_build="${ROOT}/bazel-tensorflow/external/local_config_rocm/crosstool/BUILD"
  if [[ ! -f "${crosstool_build}" ]]; then
    return 0
  fi

  "${PYTHON_BIN}" - "${crosstool_build}" "${clang_resource_dir}" "${real_clang_dir}" "${ROCM_PATH}" <<'PY'
import glob
import os
import pathlib
import re
import sys

p = pathlib.Path(sys.argv[1])
clang_resource_dir = sys.argv[2]
real_clang_dir = sys.argv[3]
rocm_path = sys.argv[4]
s = p.read_text(encoding="utf-8")
m = re.search(r'cxx_builtin_include_directories\s*=\s*\[(.*?)\]\s*,', s, re.S)
if not m:
    raise SystemExit(0)
block = m.group(1)
add_candidates = []
if clang_resource_dir:
    add_candidates.append(os.path.join(clang_resource_dir, "include"))
for d in glob.glob(os.path.join(real_clang_dir, "..", "lib", "clang", "*", "include")):
    add_candidates.extend((os.path.realpath(d), os.path.abspath(d)))
for pat in (
    os.path.join(rocm_path, "llvm", "lib", "clang", "*", "include"),
    os.path.join(rocm_path, "lib", "llvm", "lib", "clang", "*", "include"),
):
    for d in glob.glob(pat):
        add_candidates.extend((os.path.realpath(d), os.path.abspath(d)))
for include_dir in add_candidates:
    if not os.path.isdir(include_dir):
        continue
    needle = f'"{include_dir}"'
    if needle in block:
        continue
    block = block.rstrip() + (", " if block.strip() else "") + needle
s = s[:m.start(1)] + block + s[m.end(1):]
p.write_text(s, encoding="utf-8")
PY
}

rewrite_tf_configure_bazelrc_rocm_env() {
  local bazelrc="${ROOT}/.tf_configure.bazelrc"
  if [[ ! -f "${bazelrc}" ]]; then
    return 0
  fi
  "${PYTHON_BIN}" - "${bazelrc}" "${ROCM_PATH}" <<'PY'
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
rocm_path = pathlib.Path(sys.argv[2]).resolve()
ld_library_path = f"{rocm_path}/lib:{rocm_path}/lib64:"
lines = p.read_text(encoding="utf-8").splitlines()
out = []
seen_rocm = False
seen_ld = False
for line in lines:
    if line.startswith('build --action_env ROCM_PATH='):
        out.append(f'build --action_env ROCM_PATH="{rocm_path}"')
        seen_rocm = True
        continue
    if line.startswith('build --action_env LD_LIBRARY_PATH='):
        out.append(f'build --action_env LD_LIBRARY_PATH="{ld_library_path}"')
        seen_ld = True
        continue
    out.append(line)
if not seen_rocm:
    out.append(f'build --action_env ROCM_PATH="{rocm_path}"')
if not seen_ld:
    out.append(f'build --action_env LD_LIBRARY_PATH="{ld_library_path}"')
p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

purge_bazel_local_config_rocm() {
  bazelisk --output_user_root="${BAZEL_OUTPUT_USER_ROOT}" shutdown >/dev/null 2>&1 || true
  find "${BAZEL_OUTPUT_USER_ROOT}" -type d -path '*/external/local_config_rocm' -prune -exec rm -rf {} + 2>/dev/null || true
  find "${BAZEL_OUTPUT_USER_ROOT}" -type d -path '*/external/local_config_git' -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf "${ROOT}/bazel-tensorflow/external/local_config_rocm" 2>/dev/null || true
  rm -rf "${ROOT}/bazel-tensorflow/external/local_config_git" 2>/dev/null || true
}

force_disable_generated_rocm_hipblaslt() {
  "${PYTHON_BIN}" - "${BAZEL_OUTPUT_USER_ROOT}" "${ROOT}" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
tf_root = pathlib.Path(sys.argv[2])
files = list(root.glob('*/external/local_config_rocm/rocm/rocm_config/rocm_config.h'))
files += list(root.glob('*/external/local_config_rocm/rocm/build_defs.bzl'))
files += [tf_root / 'bazel-tensorflow' / 'external' / 'local_config_rocm' / 'rocm' / 'rocm_config' / 'rocm_config.h']
files += [tf_root / 'bazel-tensorflow' / 'external' / 'local_config_rocm' / 'rocm' / 'build_defs.bzl']
for p in files:
    if not p.is_file():
        continue
    s = p.read_text(encoding='utf-8')
    n = s
    if p.name == 'rocm_config.h':
        n = re.sub(r'#define\s+TF_HIPBLASLT\s+1', '#define TF_HIPBLASLT 0', n)
    elif p.name == 'build_defs.bzl':
        n = n.replace(
            'if_rocm_hipblaslt(if_true, if_false = []):\n    return if_true',
            'if_rocm_hipblaslt(if_true, if_false = []):\n    return if_false',
        )
    if n != s:
        p.write_text(n, encoding='utf-8')
PY
}

postprocess_tensorflow_wheel_llvm_exports() {
  local wheel_path="$1"
  local tmp_root unpack_dir frame map_file out_dir
  if [[ ! -f "${wheel_path}" ]]; then
    echo "ERROR: missing wheel for postprocess: ${wheel_path}" >&2
    return 1
  fi
  if ! command -v patchelf >/dev/null 2>&1; then
    echo "ERROR: patchelf is required for TensorFlow wheel postprocessing" >&2
    return 1
  fi

  tmp_root="$(mktemp -d)"
  out_dir="$(dirname "${wheel_path}")"
  "${PYTHON_BIN}" -m wheel unpack --dest "${tmp_root}" "${wheel_path}" >/dev/null
  unpack_dir="$(find "${tmp_root}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  frame="${unpack_dir}/tensorflow/libtensorflow_framework.so.2"
  if [[ ! -f "${frame}" ]]; then
    echo "ERROR: unpacked wheel missing libtensorflow_framework.so.2" >&2
    rm -rf "${tmp_root}"
    return 1
  fi

  map_file="${tmp_root}/tf_llvm_fullrename.map"
  nm -D --defined-only "${frame}" \
    | awk '$3 ~ /^_Z(NK?4llvm|TIN4llvm|TSN4llvm|TVN4llvm)/ {print $3}' \
    | sort -u \
    | awk '{printf "%s __tfllvm_%05d\n", $1, NR}' > "${map_file}"

  if [[ ! -s "${map_file}" ]]; then
    echo "No TensorFlow LLVM dynamic exports found; skipping postprocess."
    rm -rf "${tmp_root}"
    return 0
  fi

  echo "Renaming TensorFlow LLVM dynamic symbols in wheel: ${wheel_path}"
  echo "  map entries: $(wc -l < "${map_file}")"
  while IFS= read -r -d '' so_file; do
    patchelf --rename-dynamic-symbols "${map_file}" "${so_file}"
  done < <(find "${unpack_dir}/tensorflow" -type f -name '*.so*' -print0)

  local remaining_old remaining_new
  remaining_old="$(nm -D --defined-only "${frame}" | awk '$3 ~ /^_Z(NK?4llvm|TIN4llvm|TSN4llvm|TVN4llvm)/ {n++} END{print n+0}')"
  remaining_new="$(nm -D --defined-only "${frame}" | awk '$3 ~ /^__tfllvm_/ {n++} END{print n+0}')"
  echo "  framework old llvm exports after rename: ${remaining_old}"
  echo "  framework renamed llvm exports after rename: ${remaining_new}"
  if [[ "${remaining_old}" != "0" ]]; then
    echo "ERROR: TensorFlow wheel postprocess left old LLVM exports in ${frame}" >&2
    rm -rf "${tmp_root}"
    return 1
  fi

  rm -f "${wheel_path}"
  "${PYTHON_BIN}" -m wheel pack --dest-dir "${out_dir}" "${unpack_dir}" >/dev/null
  rm -rf "${tmp_root}"
}

if [[ ! -x "${PYTHON_BIN}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi
"${PYTHON_BIN}" -m pip install -U pip setuptools wheel numpy keras_preprocessing packaging requests opt_einsum six

if [[ ! -x "${BAZELISK}" ]]; then
  curl -L -o "${BAZELISK}" https://github.com/bazelbuild/bazelisk/releases/download/v1.23.0/bazelisk-linux-amd64
  chmod +x "${BAZELISK}"
fi
ln -sf "${BAZELISK}" "${BAZEL_BIN_DIR}/bazel"
export PATH="${BAZEL_BIN_DIR}:${PATH}"

cd "${ROOT}"
ln -sf "${PYTHON_BIN}" "${BAZEL_BIN_DIR}/python"

export TF_NEED_ROCM=1
export TF_NEED_CUDA=0
export TF_NEED_TENSORRT=0
export TF_NEED_CLANG=0
export TF_ROCM_CLANG=1
export CLANG_COMPILER_PATH="${CCACHE_CLANG_WRAPPER}"
export TF_ENABLE_XLA
export TF_ROCM_AMDGPU_TARGETS="${TF_ROCM_AMDGPU_TARGETS:-gfx1031}"
export ROCM_PATH
export HIP_DEVICE_LIB_PATH="${ROCM_PATH}/lib/llvm/amdgcn/bitcode"
export PYTHON_BIN_PATH="${PYTHON_BIN}"
export CC_OPT_FLAGS="-O3"
export TF_SET_ANDROID_WORKSPACE=0

if [[ ! -d "${ROCM_PATH}/amdgcn" && -d "${ROCM_PATH}/lib/llvm/amdgcn" ]]; then
  ln -sfn "${ROCM_PATH}/lib/llvm/amdgcn" "${ROCM_PATH}/amdgcn"
fi

purge_bazel_local_config_rocm
set +e
yes "" | ./configure
cfg_rc=${PIPESTATUS[1]:-1}
set -e
if [[ "${cfg_rc}" -ne 0 && "${cfg_rc}" -ne 141 ]]; then
  echo "TensorFlow configure failed with exit code ${cfg_rc}" >&2
  exit "${cfg_rc}"
fi

rewrite_tf_configure_bazelrc_rocm_env
patch_rocm_crosstool_builtin_includes
force_disable_generated_rocm_hipblaslt

bazelisk --output_user_root="${BAZEL_OUTPUT_USER_ROOT}" build \
  --config=opt \
  --config=rocm \
  --config=nonccl \
  $( [[ "${BAZEL_VERBOSE_FAILURES}" == "1" ]] && echo "--verbose_failures" ) \
  --jobs="${JOBS}" \
  --repo_env=TF_ROCM_CLANG=1 \
  --repo_env=CLANG_COMPILER_PATH="${CCACHE_CLANG_WRAPPER}" \
  --action_env=PATH="${PATH}" \
  --action_env=CLANG_COMPILER_PATH="${CCACHE_CLANG_WRAPPER}" \
  --action_env=LIBRARY_PATH="${LIBRARY_PATH}" \
  --action_env=HIP_DEVICE_LIB_PATH="${HIP_DEVICE_LIB_PATH}" \
  --action_env=CCACHE_DIR="${CCACHE_DIR}" \
  --action_env=CCACHE_BASEDIR="${CCACHE_BASEDIR}" \
  --action_env=CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK}" \
  --linkopt=-L"${SYSLIBS_DIR}" \
  --host_linkopt=-L"${SYSLIBS_DIR}" \
  //tensorflow/tools/pip_package:wheel

WHEEL_HELPER="./bazel-bin/tensorflow/tools/pip_package/wheel"
WHEEL_HOUSE="${ROOT}/bazel-bin/tensorflow/tools/pip_package/wheel_house"
if [[ -x "${WHEEL_HELPER}" ]]; then
  "${WHEEL_HELPER}" \
    --output-name tensorflow_rocm_custom \
    --project-name tensorflow-rocm-custom \
    --output-dir "${WHEEL_OUT_DIR}"
else
  shopt -s nullglob
  wheels=( "${WHEEL_HOUSE}"/tensorflow-*.whl )
  shopt -u nullglob
  if [[ "${#wheels[@]}" -eq 0 ]]; then
    echo "ERROR: no TensorFlow wheel found in ${WHEEL_HOUSE}" >&2
    exit 1
  fi
  cp -f "${wheels[@]}" "${WHEEL_OUT_DIR}/"
fi

shopt -s nullglob
produced_wheels=( "${WHEEL_OUT_DIR}"/tensorflow-*.whl )
shopt -u nullglob
if [[ "${#produced_wheels[@]}" -eq 0 ]]; then
  echo "ERROR: no TensorFlow wheel available for postprocess in ${WHEEL_OUT_DIR}" >&2
  exit 1
fi
for wheel_path in "${produced_wheels[@]}"; do
  postprocess_tensorflow_wheel_llvm_exports "${wheel_path}"
done

echo "Done. Wheel(s):"
ls -lh "${WHEEL_OUT_DIR}"/*.whl
