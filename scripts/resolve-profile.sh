#!/usr/bin/env bash
#
# Resolve workflow_dispatch inputs into a concrete build profile and export
# environment variables + step outputs for the rest of the job.
#
# Required env (all provided by the workflow):
#   INPUT_PLATFORM
#   INPUT_SOURCE_CHOICE
#   INPUT_BRANCH_MODE
#   INPUT_KERNEL_BRANCH
#   INPUT_CLANG_CHOICE
#   MATRIX_KSU_TYPE
#   GITHUB_ENV
#   GITHUB_OUTPUT
#   GITHUB_STEP_SUMMARY
#
set -euo pipefail

: "${INPUT_PLATFORM:?}"
: "${INPUT_SOURCE_CHOICE:?}"
: "${INPUT_BRANCH_MODE:?}"
: "${INPUT_CLANG_CHOICE:?}"
: "${MATRIX_KSU_TYPE:?}"
: "${GITHUB_ENV:?}"
: "${GITHUB_OUTPUT:?}"
: "${GITHUB_STEP_SUMMARY:?}"

INPUT_KERNEL_BRANCH="${INPUT_KERNEL_BRANCH:-}"

# ---- Platform ----------------------------------------------------------------
case "$INPUT_PLATFORM" in
  "Snapdragon 8 Gen 1 (SM8450 / OnePlus 10 Pro)")
    SOC="sm8450"
    PLATFORM_SLUG="8gen1"
    PLATFORM_NAME="Snapdragon 8 Gen 1"
    BUILD_CONFIGS="vendor/waipio_GKI.config vendor/oplus/waipio_GKI.config vendor/debugfs.config"
    OFFICIAL_BUILD_TARGET="waipio"
    OFFICIAL_GKI_FRAGMENT="arch/arm64/configs/vendor/waipio_GKI.config"
    RECOMMENDED_SOURCE="lineage-ovaltine-dev"
    ;;
  "Snapdragon 8 Gen 2 (SM8550 / OnePlus 11 / 12R)")
    SOC="sm8550"
    PLATFORM_SLUG="8gen2"
    PLATFORM_NAME="Snapdragon 8 Gen 2"
    BUILD_CONFIGS="vendor/kalama_GKI.config vendor/oplus/kalama_GKI.config vendor/debugfs.config"
    OFFICIAL_BUILD_TARGET="kalama"
    OFFICIAL_GKI_FRAGMENT="arch/arm64/configs/vendor/kalama_GKI.config"
    RECOMMENDED_SOURCE="LineageOS"
    ;;
  "Snapdragon 8 Gen 3 (SM8650 / OnePlus 12)")
    SOC="sm8650"
    PLATFORM_SLUG="8gen3"
    PLATFORM_NAME="Snapdragon 8 Gen 3"
    BUILD_CONFIGS="vendor/pineapple_GKI.config vendor/oplus/pineapple_GKI.config"
    OFFICIAL_BUILD_TARGET="pineapple"
    OFFICIAL_GKI_FRAGMENT="arch/arm64/configs/vendor/pineapple_GKI.config"
    RECOMMENDED_SOURCE="LineageOS"
    ;;
  *)
    echo "::error::Unsupported platform: $INPUT_PLATFORM"
    exit 1
    ;;
esac

# ---- Source preset -----------------------------------------------------------
case "$INPUT_SOURCE_CHOICE" in
  "Recommended source for this platform")
    KERNEL_SOURCE="$RECOMMENDED_SOURCE"
    SOURCE_LAYOUT="community-flat"
    ;;
  "OnePlus official source")
    KERNEL_SOURCE="OnePlusOSS"
    SOURCE_LAYOUT="oneplus-official"
    ;;
  "LineageOS / community source")
    SOURCE_LAYOUT="community-flat"
    case "$SOC" in
      sm8450) KERNEL_SOURCE="lineage-ovaltine-dev" ;;
      sm8550|sm8650) KERNEL_SOURCE="LineageOS" ;;
    esac
    ;;
  "crDroid source")
    SOURCE_LAYOUT="community-flat"
    if [[ "$SOC" == "sm8450" ]]; then
      echo "::error::crDroid source is not configured for Snapdragon 8 Gen 1 in this workflow yet."
      exit 1
    fi
    KERNEL_SOURCE="crdroidandroid"
    ;;
  "OnePlus 12R development source (SM8550 only)")
    SOURCE_LAYOUT="community-flat"
    if [[ "$SOC" != "sm8550" ]]; then
      echo "::error::OnePlus 12R development source is only available for Snapdragon 8 Gen 2 (SM8550)."
      exit 1
    fi
    KERNEL_SOURCE="OnePlus12R-development"
    ;;
  *)
    echo "::error::Unknown source choice: $INPUT_SOURCE_CHOICE"
    exit 1
    ;;
esac

case "$KERNEL_SOURCE" in
  "OnePlusOSS")             SOURCE_NAME="OnePlus official source";       SOURCE_SLUG="oneplus-official" ;;
  "LineageOS")              SOURCE_NAME="LineageOS";                     SOURCE_SLUG="lineageos" ;;
  "lineage-ovaltine-dev")   SOURCE_NAME="LineageOS community (ovaltine)"; SOURCE_SLUG="lineage-community" ;;
  "crdroidandroid")         SOURCE_NAME="crDroid";                       SOURCE_SLUG="crdroid" ;;
  "OnePlus12R-development") SOURCE_NAME="OnePlus 12R development";       SOURCE_SLUG="oneplus12r-dev" ;;
esac

# ---- Clang preset ------------------------------------------------------------
case "$INPUT_CLANG_CHOICE" in
  "Recommended (auto-select based on branch)")               CLANG_VERSION="" ;;
  "clang-r596125 (Clang 22.0.2 / current AOSP mainline era)") CLANG_VERSION="clang-r596125" ;;
  "clang-r563880c (Android 16 / LineageOS 23.2+ era)")       CLANG_VERSION="clang-r563880c" ;;
  "clang-r547379 (Android 16 / LineageOS 23.0 era)")         CLANG_VERSION="clang-r547379" ;;
  "clang-r536225 (Android 15 / LineageOS 22.2 era)")         CLANG_VERSION="clang-r536225" ;;
  "clang-r487747c (Android 14 / LineageOS 21 era)")          CLANG_VERSION="clang-r487747c" ;;
  "clang-r450784d (Android 13 / LineageOS 20 era)")          CLANG_VERSION="clang-r450784d" ;;
  "clang-r416183b1 (Android 12 / LineageOS 19.1 era)")       CLANG_VERSION="clang-r416183b1" ;;
  *)
    echo "::error::Unknown clang choice: $INPUT_CLANG_CHOICE"
    exit 1
    ;;
esac

KSU_TYPE="$MATRIX_KSU_TYPE"
SUSFS_REF=""
SUSFS_PATCH_FILE=""

# ---- Repo layout -------------------------------------------------------------
if [[ "$SOURCE_LAYOUT" == "oneplus-official" ]]; then
  KERNEL_REPO="https://github.com/${KERNEL_SOURCE}/android_kernel_oneplus_${SOC}.git"
  MODULES_REPO="https://github.com/${KERNEL_SOURCE}/android_kernel_modules_and_devicetree_oneplus_${SOC}.git"
  # Clone as a sibling first. Cloning directly inside the modules checkout
  # races with the parallel modules clone because the destinations overlap.
  KERNEL_CLONE_DIR="${SOC}-kernel"
  MODULES_CLONE_DIR="${SOC}-modules"
else
  KERNEL_REPO="https://github.com/${KERNEL_SOURCE}/android_kernel_oneplus_${SOC}.git"
  MODULES_REPO="https://github.com/${KERNEL_SOURCE}/android_kernel_oneplus_${SOC}-modules.git"
  KERNEL_CLONE_DIR="${SOC}"
  MODULES_CLONE_DIR="${SOC}-modules"
fi

# ---- Branch resolution -------------------------------------------------------
if [[ "$INPUT_BRANCH_MODE" == "Use the recommended branch automatically" ]]; then
  KERNEL_BRANCH="$(git ls-remote --symref "$KERNEL_REPO" HEAD 2>/dev/null | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}' || true)"
  if [[ -z "$KERNEL_BRANCH" ]]; then
    echo "::error::Could not detect the default branch from $KERNEL_REPO"
    exit 1
  fi
else
  KERNEL_BRANCH="$INPUT_KERNEL_BRANCH"
  if [[ -z "$KERNEL_BRANCH" ]]; then
    echo "::error::Please type a branch name when using manual branch mode."
    exit 1
  fi
fi

# ---- Clang auto-selection ----------------------------------------------------
if [[ -z "$CLANG_VERSION" ]]; then
  case "$KERNEL_BRANCH" in
    lineage-19.1*|oneplus/*_s_12.1*|oneplus/*_s_12.0*)
      CLANG_VERSION="clang-r416183b1" ;;
    lineage-20*|thirteen*|oneplus/*_t_13*|oneplus_*_t_13*)
      CLANG_VERSION="clang-r450784d" ;;
    lineage-21*|fourteen*|oneplus/*_u_14*|oneplus_*_u_14*)
      CLANG_VERSION="clang-r487747c" ;;
    lineage-22*|fifteen*|oneplus/*_v_15*|oneplus_*_v_15*)
      CLANG_VERSION="clang-r536225" ;;
    lineage-23.0*)
      CLANG_VERSION="clang-r547379" ;;
    16.0|lineage-23*|oneplus/*_b_16*|oneplus_*_b_16*)
      CLANG_VERSION="clang-r563880c" ;;
    *)
      CLANG_VERSION="clang-r563880c"
      echo "::warning::Could not confidently infer the best clang version for branch '$KERNEL_BRANCH'. Falling back to $CLANG_VERSION."
      ;;
  esac
fi

# ---- Root/add-on repositories ------------------------------------------------
KSU_REPO=""
KSU_REF=""
KSU_COMMIT=""
case "$KSU_TYPE" in
  None)
    ;;
  Official-KernelSU)
    KSU_REPO="https://github.com/tiann/KernelSU.git"
    KSU_REF="main"
    ;;
  KernelSU-Next)
    KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
    KSU_REF="dev"
    ;;
  KowSU)
    KSU_REPO="https://github.com/KOWX712/KernelSU.git"
    KSU_REF="master"
    ;;
  ReSukiSU*)
    KSU_REPO="https://github.com/ReSukiSU/ReSukiSU.git"
    KSU_REF="main"
    ;;
  *)
    echo "::error::No upstream repository mapping is configured for $KSU_TYPE"
    exit 1
    ;;
esac

if [[ -n "$KSU_REPO" ]]; then
  KSU_COMMIT="$(git ls-remote --exit-code "$KSU_REPO" "refs/heads/${KSU_REF}" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
  if [[ ! "$KSU_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::Could not resolve $KSU_REPO branch '$KSU_REF' to a commit."
    exit 1
  fi
fi

# ---- susfs reference ---------------------------------------------------------
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_COMMIT=""
if [[ "$KSU_TYPE" == *susfs* ]]; then
  case "$SOC" in
    sm8450)
      SUSFS_REF="gki-android13-5.10"
      ;;
    sm8550)
      case "$KERNEL_BRANCH" in
        lineage-20*|thirteen*|android13*|13.*|oneplus/*_t_13*|oneplus_*_t_13*)
          SUSFS_REF="gki-android13-5.15" ;;
        lineage-21*|lineage-22*|lineage-23*|fourteen*|fifteen*|sixteen*|android14*|android15*|android16*|14.*|15.*|16.*|oneplus/*_u_14*|oneplus/*_v_15*|oneplus/*_b_16*|oneplus_*_u_14*|oneplus_*_v_15*|oneplus_*_b_16*)
          SUSFS_REF="gki-android14-5.15" ;;
        *)
          SUSFS_REF="gki-android14-5.15"
          echo "::warning::Could not confidently infer the best SM8550 susfs branch for '$KERNEL_BRANCH'. Falling back to $SUSFS_REF."
          ;;
      esac
      ;;
    sm8650)
      SUSFS_REF="gki-android14-6.1"
      ;;
    *)
      echo "::error::No susfs mapping is configured for platform $SOC"
      exit 1
      ;;
  esac
  SUSFS_PATCH_FILE="50_add_susfs_in_${SUSFS_REF}.patch"
  SUSFS_COMMIT="$(git ls-remote --exit-code "$SUSFS_REPO" "refs/heads/${SUSFS_REF}" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
  if [[ ! "$SUSFS_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::Could not resolve susfs branch '$SUSFS_REF' to a commit."
    exit 1
  fi
fi

# ---- Repo/branch availability checks -----------------------------------------
KERNEL_COMMIT="$(git ls-remote --exit-code --heads "$KERNEL_REPO" "$KERNEL_BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
if [[ ! "$KERNEL_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Branch '$KERNEL_BRANCH' was not found in $KERNEL_REPO"
  exit 1
fi

MODULES_COMMIT="$(git ls-remote --exit-code --heads "$MODULES_REPO" "$KERNEL_BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
if [[ ! "$MODULES_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Branch '$KERNEL_BRANCH' was not found in $MODULES_REPO"
  echo "::error::This workflow requires the matching modules repository for defconfig/Kconfig resolution."
  exit 1
fi

ANYKERNEL_REPO="https://github.com/Kernel-SU/AnyKernel3.git"
ANYKERNEL_COMMIT="$(git ls-remote --exit-code "$ANYKERNEL_REPO" HEAD 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
if [[ ! "$ANYKERNEL_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Could not resolve AnyKernel3 HEAD to a commit."
  exit 1
fi

case "$KERNEL_SOURCE" in
  OnePlusOSS)
    if [[ ! "$KERNEL_BRANCH" =~ ^oneplus/ ]] && [[ ! "$KERNEL_BRANCH" =~ ^oneplus_ ]]; then
      echo "::warning::This source usually uses oneplus/* branches, but '$KERNEL_BRANCH' was selected."
    fi
    ;;
  LineageOS|OnePlus12R-development|lineage-ovaltine-dev)
    if [[ ! "$KERNEL_BRANCH" =~ ^lineage- ]]; then
      echo "::warning::This source usually uses lineage-* branches, but '$KERNEL_BRANCH' was selected."
    fi
    ;;
  crdroidandroid)
    echo "Note: crDroid branch naming may differ from LineageOS."
    ;;
esac

# ---- Export to GITHUB_ENV ----------------------------------------------------
{
  echo "SOC=$SOC"
  echo "PLATFORM_SLUG=$PLATFORM_SLUG"
  echo "PLATFORM_NAME=$PLATFORM_NAME"
  echo "BUILD_CONFIGS=$BUILD_CONFIGS"
  echo "SOURCE_LAYOUT=$SOURCE_LAYOUT"
  echo "KERNEL_SOURCE=$KERNEL_SOURCE"
  echo "SOURCE_NAME=$SOURCE_NAME"
  echo "SOURCE_SLUG=$SOURCE_SLUG"
  echo "KERNEL_REPO=$KERNEL_REPO"
  echo "MODULES_REPO=$MODULES_REPO"
  echo "KERNEL_CLONE_DIR=$KERNEL_CLONE_DIR"
  echo "MODULES_CLONE_DIR=$MODULES_CLONE_DIR"
  echo "OFFICIAL_BUILD_TARGET=$OFFICIAL_BUILD_TARGET"
  echo "OFFICIAL_GKI_FRAGMENT=$OFFICIAL_GKI_FRAGMENT"
  echo "KERNEL_BRANCH=$KERNEL_BRANCH"
  echo "KERNEL_COMMIT=$KERNEL_COMMIT"
  echo "MODULES_COMMIT=$MODULES_COMMIT"
  echo "CLANG_VERSION=$CLANG_VERSION"
  echo "KSU_TYPE=$KSU_TYPE"
  echo "KSU_REPO=$KSU_REPO"
  echo "KSU_REF=$KSU_REF"
  echo "KSU_COMMIT=$KSU_COMMIT"
  echo "SUSFS_REPO=$SUSFS_REPO"
  echo "SUSFS_REF=$SUSFS_REF"
  echo "SUSFS_COMMIT=$SUSFS_COMMIT"
  echo "SUSFS_PATCH_FILE=$SUSFS_PATCH_FILE"
  echo "ANYKERNEL_REPO=$ANYKERNEL_REPO"
  echo "ANYKERNEL_COMMIT=$ANYKERNEL_COMMIT"
} >> "$GITHUB_ENV"

{
  echo "soc=$SOC"
  echo "platform_slug=$PLATFORM_SLUG"
  echo "platform_name=$PLATFORM_NAME"
  echo "kernel_source=$KERNEL_SOURCE"
  echo "source_name=$SOURCE_NAME"
  echo "source_slug=$SOURCE_SLUG"
  echo "source_layout=$SOURCE_LAYOUT"
  echo "kernel_branch=$KERNEL_BRANCH"
  echo "kernel_commit=$KERNEL_COMMIT"
  echo "modules_commit=$MODULES_COMMIT"
  echo "clang_version=$CLANG_VERSION"
  echo "ksu_type=$KSU_TYPE"
  echo "ksu_commit=$KSU_COMMIT"
  echo "susfs_ref=$SUSFS_REF"
  echo "susfs_commit=$SUSFS_COMMIT"
  echo "anykernel_commit=$ANYKERNEL_COMMIT"
} >> "$GITHUB_OUTPUT"

{
  echo "### Build profile"
  echo "- Platform: $PLATFORM_NAME ($SOC)"
  echo "- Source: $SOURCE_NAME"
  echo "- Branch: $KERNEL_BRANCH"
  echo "- Kernel commit: \`${KERNEL_COMMIT}\`"
  echo "- Modules commit: \`${MODULES_COMMIT}\`"
  echo "- Clang: $CLANG_VERSION"
  echo "- Root solution: $KSU_TYPE"
  if [[ -n "$KSU_COMMIT" ]]; then
    echo "- KernelSU commit: \`${KSU_COMMIT}\` ($KSU_REF)"
  fi
  if [[ -n "$SUSFS_REF" ]]; then
    echo "- susfs: $SUSFS_REF (\`${SUSFS_COMMIT}\`)"
  fi
  echo "- AnyKernel3 commit: \`${ANYKERNEL_COMMIT}\`"
} >> "$GITHUB_STEP_SUMMARY"
