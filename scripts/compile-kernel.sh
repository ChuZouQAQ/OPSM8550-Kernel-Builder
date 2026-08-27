#!/usr/bin/env bash
#
# Apply the selected integrations, generate config, and optionally build Image.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git-helpers.sh
. "${SCRIPT_DIR}/lib/git-helpers.sh"
# shellcheck source=lib/kernel-helpers.sh
. "${SCRIPT_DIR}/lib/kernel-helpers.sh"
# shellcheck source=lib/ksu-setup.sh
. "${SCRIPT_DIR}/lib/ksu-setup.sh"
# shellcheck source=lib/susfs-apply.sh
. "${SCRIPT_DIR}/lib/susfs-apply.sh"
# shellcheck source=lib/nomount-setup.sh
. "${SCRIPT_DIR}/lib/nomount-setup.sh"
# shellcheck source=lib/verify.sh
. "${SCRIPT_DIR}/lib/verify.sh"

: "${GITHUB_WORKSPACE:?}"
: "${GITHUB_STEP_SUMMARY:?}"
: "${CLANG_VERSION:?}"
: "${SOC:?}"
: "${BUILD_CONFIGS:?}"
: "${SOURCE_LAYOUT:?}"
: "${OFFICIAL_BUILD_TARGET:?}"
: "${KSU_TYPE:?}"
: "${KERNEL_BRANCH:?}"
: "${KERNEL_COMMIT:?}"
: "${BUILD_MODE:?}"

BUILD_STARTED_AT="$(date +%s)"
CONFIG_SECONDS=0
COMPILE_SECONDS=0
BUILD_PHASE="setup"

publish_performance_summary() {
  local status="$?"
  local finished_at
  local elapsed

  trap - EXIT
  finished_at="$(date +%s)"
  elapsed=$((finished_at - BUILD_STARTED_AT))

  {
    echo "### Build performance"
    echo "- Result: $([[ "$status" -eq 0 ]] && echo success || echo failure)"
    echo "- Last phase: $BUILD_PHASE"
    echo "- Config/patch time: ${CONFIG_SECONDS}s"
    echo "- Compile time: ${COMPILE_SECONDS}s"
    echo "- Script total: ${elapsed}s"
    if command -v ccache >/dev/null 2>&1; then
      echo
      echo '```text'
      ccache --show-stats || true
      echo '```'
    fi
  } >> "$GITHUB_STEP_SUMMARY"

  exit "$status"
}
trap publish_performance_summary EXIT

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
export CCACHE_COMPRESS=true
export CCACHE_COMPRESSLEVEL=6
export CCACHE_MAXSIZE=3G
mkdir -p "${CCACHE_DIR}"

cd "${SOC}"

SOURCE_DATE_EPOCH="$(git show -s --format=%ct "$KERNEL_COMMIT")"
export SOURCE_DATE_EPOCH
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP="$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%d %H:%M:%S UTC')"
export KBUILD_BUILD_USER=opskernel
export KBUILD_BUILD_HOST=github-actions

# Command-line assignments take precedence over Kbuild's own CC/HOSTCC values.
# Exporting CC alone is not sufficient when LLVM=1 because the kernel Makefile
# assigns CC=clang internally.
MAKE_ARGS=(
  O=out
  LLVM=1
  LLVM_IAS=1
  "CC=ccache clang"
  "CXX=ccache clang++"
  "HOSTCC=ccache clang"
  "HOSTCXX=ccache clang++"
)

ccache --zero-stats || true
CONFIG_STARTED_AT="$(date +%s)"
BUILD_PHASE="source integration"

install_ksu_variant "${KSU_TYPE}"

if [[ "$KSU_TYPE" == *susfs* ]]; then
  : "${SUSFS_REF:?}"
  : "${SUSFS_COMMIT:?}"
  : "${SUSFS_PATCH_FILE:?}"
  apply_susfs_full "$SUSFS_REF" "$SUSFS_COMMIT" "$SUSFS_PATCH_FILE"
  verify_susfs_source_integration "${KSU_KERNEL_DIR}"
fi

if [[ "$KSU_TYPE" == *nomount* ]]; then
  : "${NOMOUNT_REPO:?}"
  : "${NOMOUNT_REF:?}"
  : "${NOMOUNT_COMMIT:?}"
  install_nomount "$NOMOUNT_REPO" "$NOMOUNT_REF" "$NOMOUNT_COMMIT"
  verify_nomount_source_integration
fi

touch .scmversion

ACTIVE_BUILD_CONFIGS="${BUILD_CONFIGS}"
if [[ "$SOURCE_LAYOUT" == "oneplus-official" ]]; then
  ACTIVE_BUILD_CONFIGS="vendor/${OFFICIAL_BUILD_TARGET}_GKI.config"
fi
read -r -a ACTIVE_CONFIG_ARRAY <<< "$ACTIVE_BUILD_CONFIGS"

BUILD_PHASE="config generation"
apply_variant_configs arch/arm64/configs/gki_defconfig
make "${MAKE_ARGS[@]}" gki_defconfig "${ACTIVE_CONFIG_ARRAY[@]}"
apply_variant_configs out/.config
make "${MAKE_ARGS[@]}" olddefconfig

if [[ "$KSU_TYPE" != "None" ]]; then
  require_config_enabled out/.config CONFIG_KSU
fi
if [[ "$KSU_TYPE" == *susfs* ]]; then
  require_config_enabled  out/.config CONFIG_KSU_SUSFS
  require_config_enabled  out/.config CONFIG_KSU_SUSFS_SUS_MAP
  require_config_enabled  out/.config CONFIG_KSU_SUSFS_OPEN_REDIRECT
  require_config_disabled out/.config CONFIG_KSU_MANUAL_HOOK
  require_config_disabled out/.config CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
fi
if [[ "$KSU_TYPE" == *nomount* ]]; then
  require_config_enabled out/.config CONFIG_KEYS
  require_config_enabled out/.config CONFIG_NOMOUNT
fi

CONFIG_SECONDS=$(($(date +%s) - CONFIG_STARTED_AT))

if [[ "$BUILD_MODE" == "Patch/config validation only" ]]; then
  SMOKE_TARGETS=()
  if [[ "$KSU_TYPE" == *susfs* ]]; then
    SMOKE_TARGETS+=(fs/susfs.o fs/namespace.o fs/proc/task_mmu.o kernel/reboot.o)
  fi
  if [[ "$KSU_TYPE" == *nomount* ]]; then
    SMOKE_TARGETS+=("${NOMOUNT_FS_DIR}/nomount/nomount.o")
  fi

  if [[ "${#SMOKE_TARGETS[@]}" -gt 0 ]]; then
    BUILD_PHASE="integration object smoke compile"
    COMPILE_STARTED_AT="$(date +%s)"
    if ! make -j"$(nproc)" "${MAKE_ARGS[@]}" "${SMOKE_TARGETS[@]}" 2>&1 | tee integration-smoke.log; then
      COMPILE_SECONDS=$(($(date +%s) - COMPILE_STARTED_AT))
      echo "::error::SUSFS/NoMount integration object smoke compile failed."
      exit 1
    fi
    COMPILE_SECONDS=$(($(date +%s) - COMPILE_STARTED_AT))
    if [[ "$KSU_TYPE" == *susfs* ]]; then
      verify_susfs_binary_presence
    fi
    if [[ "$KSU_TYPE" == *nomount* ]]; then
      verify_nomount_binary_presence
    fi
  fi

  BUILD_PHASE="validation complete"
  echo "[+] Source integration, config validation, and integration object smoke compile completed."
  exit 0
fi

BUILD_PHASE="kernel compilation"
COMPILE_STARTED_AT="$(date +%s)"
if ! make -j"$(nproc)" "${MAKE_ARGS[@]}" Image 2>&1 | tee build.log; then
  COMPILE_SECONDS=$(($(date +%s) - COMPILE_STARTED_AT))
  ccache --show-stats || true
  echo "==== BUILD ERROR SUMMARY ===="
  grep -nE ' error:|undefined reference|No rule to make target|fatal error:' build.log | tail -n 50 || true
  echo "==== BUILD FAILED (last 200 lines) ===="
  tail -n 200 build.log || true
  exit 1
fi
COMPILE_SECONDS=$(($(date +%s) - COMPILE_STARTED_AT))

BUILD_PHASE="post-build verification"
if [[ "$KSU_TYPE" == *susfs* ]]; then
  echo "==== SUSFS CONFIG SNAPSHOT ===="
  grep -E '^CONFIG_KSU_SUSFS|^CONFIG_KSU_MANUAL_HOOK|^CONFIG_TMPFS_XATTR=|^CONFIG_NOMOUNT=' out/.config || true
  verify_resukisu_susfs_hook_mode
  verify_susfs_binary_presence
fi
if [[ "$KSU_TYPE" == *nomount* ]]; then
  verify_nomount_binary_presence
fi

ccache --show-stats || true
test -f out/arch/arm64/boot/Image
BUILD_PHASE="build complete"
