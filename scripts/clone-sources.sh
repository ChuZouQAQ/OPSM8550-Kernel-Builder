#!/usr/bin/env bash
#
# Clone the kernel and matching -modules repositories for the resolved profile.
# Both clones run in parallel to cut latency.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/git-helpers.sh
. "${SCRIPT_DIR}/lib/git-helpers.sh"

: "${KERNEL_REPO:?}"
: "${MODULES_REPO:?}"
: "${KERNEL_BRANCH:?}"
: "${MODULES_BRANCH:?}"
: "${KERNEL_COMMIT:?}"
: "${MODULES_COMMIT:?}"
: "${KERNEL_CLONE_DIR:?}"
: "${MODULES_CLONE_DIR:?}"
: "${SOURCE_LAYOUT:?}"
: "${SOC:?}"
: "${GITHUB_WORKSPACE:?}"

clone_repo() {
  local repo="$1"
  local branch="$2"
  local commit="$3"
  local dest="$4"
  local label="$5"

  echo "[clone] $label -> $repo ($branch at $commit) into $dest"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    echo "::error::Refusing to clone $label into existing path: $dest"
    exit 1
  fi

  git init -q "$dest"
  git -C "$dest" remote add origin "$repo"
  git_fetch_retry "$dest" --depth=1 --no-tags origin "$commit" \
    || { echo "::error::Failed to fetch $label commit '$commit' for branch '$branch': $repo"; exit 1; }
  git -C "$dest" checkout -q --detach FETCH_HEAD
  test "$(git -C "$dest" rev-parse HEAD)" = "$commit" \
    || { echo "::error::$label checkout did not match resolved commit '$commit'."; exit 1; }
}

# Kick off modules clone in background; kernel clone in foreground.
clone_repo "$MODULES_REPO" "$MODULES_BRANCH" "$MODULES_COMMIT" "$MODULES_CLONE_DIR" "modules repo" &
MODULES_PID=$!

clone_repo "$KERNEL_REPO" "$KERNEL_BRANCH" "$KERNEL_COMMIT" "$KERNEL_CLONE_DIR" "kernel repo"

if ! wait "$MODULES_PID"; then
  echo "::error::Background modules repo clone failed."
  exit 1
fi

if [[ "$SOURCE_LAYOUT" == "oneplus-official" ]]; then
  OFFICIAL_KERNEL_DIR="${MODULES_CLONE_DIR}/kernel_platform/msm-kernel"
  mkdir -p "$(dirname "$OFFICIAL_KERNEL_DIR")"
  rm -rf "$OFFICIAL_KERNEL_DIR"
  mv "$KERNEL_CLONE_DIR" "$OFFICIAL_KERNEL_DIR"
  rm -rf "${SOC}"
  ln -sfn "${GITHUB_WORKSPACE}/${OFFICIAL_KERNEL_DIR}" "${SOC}"
fi
