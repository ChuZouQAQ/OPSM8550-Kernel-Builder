#!/usr/bin/env bash
#
# Orchestrates the full kernel compile flow:
#   1. Set up cross-compile / ccache environment
#   2. Apply the requested KSU variant
#   3. Apply susfs patches (if requested)
#   4. Generate defconfig, merge config fragments, apply variant tweaks
#   5. Build Image
#   6. Run post-build verifications
#
# Required env (provided by the workflow):
#   GITHUB_WORKSPACE
#   CLANG_VERSION
#   SOC
#   BUILD_CONFIGS
#   SOURCE_LAYOUT
#   OFFICIAL_BUILD_TARGET
#   KSU_TYPE
#   KERNEL_BRANCH
#   SUSFS_REF          (optional; only for susfs variants)
#   SUSFS_PATCH_FILE   (optional; only for susfs variants)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/kernel-helpers.sh
. "${SCRIPT_DIR}/lib/kernel-helpers.sh"
# shellcheck source=lib/ksu-setup.sh
. "${SCRIPT_DIR}/lib/ksu-setup.sh"
# shellcheck source=lib/susfs-apply.sh
. "${SCRIPT_DIR}/lib/susfs-apply.sh"
# shellcheck source=lib/verify.sh
. "${SCRIPT_DIR}/lib/verify.sh"

: "${GITHUB_WORKSPACE:?}"
: "${CLANG_VERSION:?}"
: "${SOC:?}"
: "${BUILD_CONFIGS:?}"
: "${SOURCE_LAYOUT:?}"
: "${OFFICIAL_BUILD_TARGET:?}"
: "${KSU_TYPE:?}"
: "${KERNEL_BRANCH:?}"

# ---- Toolchain / ccache env --------------------------------------------------
CLANG_ROOT="${GITHUB_WORKSPACE}/toolchains/${CLANG_VERSION}/bin"
export PATH="${CLANG_ROOT}:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CCACHE_DIR="${GITHUB_WORKSPACE}/.ccache"
export CCACHE_BASEDIR="${GITHUB_WORKSPACE}"
export CCACHE_NOHASHDIR=true
export CCACHE_COMPILERCHECK=content
export CCACHE_MAXSIZE=2G
mkdir -p "${CCACHE_DIR}"
export CC="ccache ${CLANG_ROOT}/clang"
export CXX="ccache ${CLANG_ROOT}/clang++"
export HOSTCC="ccache ${CLANG_ROOT}/clang"
export HOSTCXX="ccache ${CLANG_ROOT}/clang++"
export LD="${CLANG_ROOT}/ld.lld"
export AR="${CLANG_ROOT}/llvm-ar"
export NM="${CLANG_ROOT}/llvm-nm"
export OBJCOPY="${CLANG_ROOT}/llvm-objcopy"
export OBJDUMP="${CLANG_ROOT}/llvm-objdump"
export STRIP="${CLANG_ROOT}/llvm-strip"

cd "${SOC}"

# ---- KSU variant -------------------------------------------------------------
install_ksu_variant "${KSU_TYPE}"

# ---- susfs -------------------------------------------------------------------
if [[ "$KSU_TYPE" == *susfs* ]]; then
  : "${SUSFS_REF:?}"
  : "${SUSFS_PATCH_FILE:?}"
  apply_susfs_full "$SUSFS_REF" "$SUSFS_PATCH_FILE"
  verify_susfs_source_integration "${KSU_KERNEL_DIR}"
fi

touch .scmversion

# ---- Config -----------------------------------------------------------------
ACTIVE_BUILD_CONFIGS="${BUILD_CONFIGS}"
if [[ "$SOURCE_LAYOUT" == "oneplus-official" ]]; then
  ACTIVE_BUILD_CONFIGS="vendor/${OFFICIAL_BUILD_TARGET}_GKI.config"
fi

apply_variant_configs arch/arm64/configs/gki_defconfig

# shellcheck disable=SC2086
make O=out gki_defconfig ${ACTIVE_BUILD_CONFIGS}

apply_variant_configs out/.config
make O=out olddefconfig

# ---- Build -------------------------------------------------------------------
ccache -z || true

if ! make -j"$(nproc)" O=out Image 2>&1 | tee build.log; then
  ccache -sv || true
  echo "==== BUILD ERROR SUMMARY ===="
  grep -nE ' error:|undefined reference|No rule to make target|fatal error:' build.log | tail -n 50 || true
  echo "==== BUILD FAILED (last 200 lines) ===="
  tail -n 200 build.log || true
  exit 1
fi

# ---- Post-build checks -------------------------------------------------------
if [[ "$KSU_TYPE" == *susfs* ]]; then
  require_config_enabled  out/.config CONFIG_KSU_SUSFS
  require_config_disabled out/.config CONFIG_KSU_MANUAL_HOOK
  require_config_disabled out/.config CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
  echo "==== SUSFS CONFIG SNAPSHOT ===="
  grep -E '^CONFIG_KSU_SUSFS|^CONFIG_KSU_MANUAL_HOOK|^CONFIG_TMPFS_XATTR=' out/.config || true
fi

if [[ "$KSU_TYPE" == "ReSukiSU-with-susfs-KPM" ]]; then
  require_config_enabled out/.config CONFIG_KPM
  require_config_enabled out/.config CONFIG_KALLSYMS
  require_config_enabled out/.config CONFIG_KALLSYMS_ALL
  echo "==== RESUKISU KPM CONFIG SNAPSHOT ===="
  grep -E '^CONFIG_KPM=|^CONFIG_KALLSYMS=|^CONFIG_KALLSYMS_ALL=' out/.config || true
fi

if [[ "$KSU_TYPE" == ReSukiSU-with-susfs* ]]; then
  verify_resukisu_susfs_hook_mode
fi

if [[ "$KSU_TYPE" == *susfs* ]]; then
  verify_susfs_binary_presence
fi

ccache -sv || true
test -f out/arch/arm64/boot/Image
