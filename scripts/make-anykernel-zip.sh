#!/usr/bin/env bash
#
# Build the AnyKernel3 flashable zip from the freshly built Image.
#
# Required env:
#   SOC
#   KSU_TYPE
#   BUILD_TIMESTAMP
#   GITHUB_ENV
#   ANYKERNEL_REPO
#   ANYKERNEL_COMMIT
#
set -euo pipefail

: "${SOC:?}"
: "${KSU_TYPE:?}"
: "${BUILD_TIMESTAMP:?}"
: "${GITHUB_ENV:?}"
: "${ANYKERNEL_REPO:?}"
: "${ANYKERNEL_COMMIT:?}"

ZIP_NAME="${SOC}_${KSU_TYPE}_${BUILD_TIMESTAMP}"
echo "ZIP_NAME=$ZIP_NAME" >> "$GITHUB_ENV"

if [[ -d AnyKernel3/.git ]]; then
  echo "[+] Reusing cached AnyKernel3 checkout."
  (
    cd AnyKernel3
    git clean -fdx
    git remote set-url origin "$ANYKERNEL_REPO"
    git fetch --depth=1 --no-tags origin "$ANYKERNEL_COMMIT"
    git checkout -q --detach FETCH_HEAD
    git reset --hard "$ANYKERNEL_COMMIT"
  )
else
  rm -rf AnyKernel3
  git init -q AnyKernel3
  git -C AnyKernel3 remote add origin "$ANYKERNEL_REPO"
  git -C AnyKernel3 fetch --depth=1 --no-tags origin "$ANYKERNEL_COMMIT"
  git -C AnyKernel3 checkout -q --detach FETCH_HEAD
fi

test "$(git -C AnyKernel3 rev-parse HEAD)" = "$ANYKERNEL_COMMIT"

sed -i 's/kernel.string=KernelSU by KernelSU Developers/kernel.string=KernelSU by TG@AzusaMyo/' \
  AnyKernel3/anykernel.sh
grep -q 'kernel.string=KernelSU by TG@AzusaMyo' AnyKernel3/anykernel.sh

cp "${SOC}/out/arch/arm64/boot/Image" AnyKernel3/Image

(
  cd AnyKernel3
  zip -r9 "../${ZIP_NAME}.zip" . -x .git/\* .github/\*
)

test -f "${ZIP_NAME}.zip"
