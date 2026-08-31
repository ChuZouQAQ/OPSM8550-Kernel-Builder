#!/usr/bin/env bash
#
# Resolve every supported profile against live upstreams without cloning/building.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/profile-data.sh
. "${SCRIPT_DIR}/lib/profile-data.sh"

TMP_DIR="$(mktemp -d)"
LOCAL_SUMMARY=""
if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
  LOCAL_SUMMARY="$(mktemp)"
  GITHUB_STEP_SUMMARY="$LOCAL_SUMMARY"
fi

cleanup() {
  rm -rf "$TMP_DIR"
  [[ -z "$LOCAL_SUMMARY" ]] || rm -f "$LOCAL_SUMMARY"
}
trap cleanup EXIT
STATUS=0
COUNT=0
PROFILES=()
mapfile -t PROFILES < <(list_build_profiles)
PROFILE_COUNT="${#PROFILES[@]}"

{
  echo "### Upstream resolution"
  echo
  echo "| Profile | Kernel branch | Modules branch | Kernel | Modules | SUSFS | NoMount | Result |"
  echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
} >> "$GITHUB_STEP_SUMMARY"

for profile in "${PROFILES[@]}"; do
  COUNT=$((COUNT + 1))
  env_file="${TMP_DIR}/env-${COUNT}"
  output_file="${TMP_DIR}/output-${COUNT}"
  resolver_summary="${TMP_DIR}/summary-${COUNT}"
  : > "$env_file"
  : > "$output_file"
  : > "$resolver_summary"

  echo "[${COUNT}/${PROFILE_COUNT}] Resolving ${profile}"
  if INPUT_BUILD_PROFILE="$profile" \
     INPUT_BRANCH_MODE="Use the recommended branch automatically" \
     INPUT_KERNEL_BRANCH="" \
     INPUT_CLANG_CHOICE="Recommended (auto-select based on branch)" \
     INPUT_ROOT_SOLUTION="ReSukiSU + SUSFS + NoMount (experimental)" \
     INPUT_BUILD_MODE="Patch/config validation only" \
     GITHUB_ENV="$env_file" \
     GITHUB_OUTPUT="$output_file" \
     GITHUB_STEP_SUMMARY="$resolver_summary" \
     bash "${SCRIPT_DIR}/resolve-profile.sh"; then
    profile_id="$(awk -F= '$1 == "profile_id" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    branch="$(awk -F= '$1 == "kernel_branch" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    modules_branch="$(awk -F= '$1 == "modules_branch" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    kernel_commit="$(awk -F= '$1 == "kernel_commit" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    modules_commit="$(awk -F= '$1 == "modules_commit" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    susfs_commit="$(awk -F= '$1 == "susfs_commit" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    nomount_commit="$(awk -F= '$1 == "nomount_commit" {print substr($0, index($0, "=") + 1)}' "$output_file")"
    echo "| ${profile_id} | ${branch} | ${modules_branch} | \`${kernel_commit:0:12}\` | \`${modules_commit:0:12}\` | \`${susfs_commit:0:12}\` | \`${nomount_commit:0:12}\` | pass |" \
      >> "$GITHUB_STEP_SUMMARY"
  else
    safe_profile="${profile//|/\\|}"
    echo "| ${safe_profile} | - | - | - | - | - | - | **failed** |" >> "$GITHUB_STEP_SUMMARY"
    STATUS=1
  fi
done

if [[ "$STATUS" -ne 0 ]]; then
  echo "::error::One or more upstream profiles failed to resolve."
fi
if [[ -n "$LOCAL_SUMMARY" ]]; then
  cat "$LOCAL_SUMMARY"
fi
exit "$STATUS"
