#!/usr/bin/env bash
#
# Download the AOSP Clang toolchain requested in $CLANG_VERSION into
# toolchains/${CLANG_VERSION}. Intended to be skipped when the cache hits.
#
set -euo pipefail

: "${CLANG_VERSION:?CLANG_VERSION must be set}"

declare -A CLANG_URLS=(
  [clang-r596125]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel/clang-r596125.tar.gz"
  [clang-r416183b1]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-qpr3-release/clang-r416183b1.tar.gz"
  [clang-r450784d]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android13-qpr3-release/clang-r450784d.tar.gz"
  [clang-r487747c]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android14-qpr3-release/clang-r487747c.tar.gz"
  [clang-r536225]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android15-qpr2-release/clang-r536225.tar.gz"
  [clang-r547379]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android16-qpr2-release/clang-r547379.tar.gz"
  [clang-r563880c]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android16-qpr2-release/clang-r563880c.tar.gz"
)

URL="${CLANG_URLS[$CLANG_VERSION]:-}"
if [[ -z "$URL" ]]; then
  echo "::error::Unsupported clang version: $CLANG_VERSION"
  exit 1
fi

TARGET_DIR="toolchains/${CLANG_VERSION}"
mkdir -p "$TARGET_DIR"

TMP_TAR="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "$TMP_TAR"' EXIT

curl --retry 5 --retry-delay 3 --retry-all-errors -fL "$URL" -o "$TMP_TAR"
tar -xf "$TMP_TAR" -C "$TARGET_DIR"
