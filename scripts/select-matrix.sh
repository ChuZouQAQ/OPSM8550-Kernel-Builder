#!/usr/bin/env bash
#
# Select the build matrix for the Kernel_CI job based on the chosen root preset.
#
# Required env:
#   ROOT_SOLUTION    Human-readable root preset from workflow_dispatch input
#   GITHUB_OUTPUT    Path to the GitHub Actions outputs file
#
set -euo pipefail

: "${ROOT_SOLUTION:?ROOT_SOLUTION must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

case "$ROOT_SOLUTION" in
  "No root changes")
    BUILD_MATRIX='{"include":[{"build_label":"No root changes","ksu_type":"None"}]}'
    ;;
  "Official KernelSU")
    BUILD_MATRIX='{"include":[{"build_label":"Official KernelSU","ksu_type":"Official-KernelSU"}]}'
    ;;
  "KernelSU-Next")
    BUILD_MATRIX='{"include":[{"build_label":"KernelSU-Next","ksu_type":"KernelSU-Next"}]}'
    ;;
  "KernelSU-Next + susfs")
    BUILD_MATRIX='{"include":[{"build_label":"KernelSU-Next + susfs","ksu_type":"KernelSU-Next-with-susfs"}]}'
    ;;
  "KowSU")
    BUILD_MATRIX='{"include":[{"build_label":"KowSU","ksu_type":"KowSU"}]}'
    ;;
  "ReSukiSU")
    BUILD_MATRIX='{"include":[{"build_label":"ReSukiSU","ksu_type":"ReSukiSU"}]}'
    ;;
  "ReSukiSU + susfs")
    BUILD_MATRIX='{"include":[{"build_label":"ReSukiSU + susfs","ksu_type":"ReSukiSU-with-susfs"}]}'
    ;;
  "ReSukiSU + susfs + KPM")
    BUILD_MATRIX='{"include":[{"build_label":"ReSukiSU + susfs + KPM","ksu_type":"ReSukiSU-with-susfs-KPM"}]}'
    ;;
  "ReSukiSU + susfs (build both: with KPM and without KPM)")
    BUILD_MATRIX='{"include":[{"build_label":"ReSukiSU + susfs","ksu_type":"ReSukiSU-with-susfs"},{"build_label":"ReSukiSU + susfs + KPM","ksu_type":"ReSukiSU-with-susfs-KPM"}]}'
    ;;
  *)
    echo "::error::Unsupported root solution: $ROOT_SOLUTION"
    exit 1
    ;;
esac

echo "build_matrix=${BUILD_MATRIX}" >> "$GITHUB_OUTPUT"
