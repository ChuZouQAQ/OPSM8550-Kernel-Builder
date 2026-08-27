#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/profile-data.sh
. "${SCRIPT_DIR}/../lib/profile-data.sh"
# shellcheck source=../lib/anykernel-helpers.sh
. "${SCRIPT_DIR}/../lib/anykernel-helpers.sh"
# shellcheck source=../lib/nomount-setup.sh
. "${SCRIPT_DIR}/../lib/nomount-setup.sh"
# shellcheck source=../lib/susfs-apply.sh
. "${SCRIPT_DIR}/../lib/susfs-apply.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

profiles=()
mapfile -t profiles < <(list_build_profiles)
assert_eq "9" "${#profiles[@]}" "profile count"

WORKFLOW_FILE="${SCRIPT_DIR}/../../.github/workflows/build.yml"
COMPILE_SCRIPT="${SCRIPT_DIR}/../compile-kernel.sh"
for profile in "${profiles[@]}"; do
  grep -Fq -- "- ${profile}" "$WORKFLOW_FILE" \
    || fail "workflow is missing profile option: $profile"
done
grep -Fq '"CC=ccache clang"' "$COMPILE_SCRIPT" \
  || fail "compile script is not passing ccache on the make command line"
grep -Fq 'KBUILD_BUILD_TIMESTAMP=' "$COMPILE_SCRIPT" \
  || fail "compile script is missing deterministic Kbuild metadata"

expected_socs=(sm8450 sm8450 sm8550 sm8550 sm8550 sm8550 sm8650 sm8650 sm8650)
expected_devices=(negroni ovaltine salami "salami aston" "salami aston" aston waffle waffle waffle)

for i in "${!profiles[@]}"; do
  resolve_build_profile "${profiles[$i]}"
  assert_eq "${expected_socs[$i]}" "$SOC" "${profiles[$i]} SoC"
  assert_eq "${expected_devices[$i]}" "$DEVICE_NAMES" "${profiles[$i]} devices"
  [[ -n "$PROFILE_ID" && -n "$BUILD_CONFIGS" && -n "$SOURCE_SLUG" ]] \
    || fail "${profiles[$i]} did not resolve all required metadata"
done

resolve_root_solution "ReSukiSU + susfs"
assert_eq "ReSukiSU-with-susfs" "$KSU_TYPE" "root mapping"
resolve_root_solution "ReSukiSU + SUSFS + NoMount (experimental)"
assert_eq "ReSukiSU-with-susfs-nomount" "$KSU_TYPE" "NoMount root mapping"
grep -Fq -- '- ReSukiSU + SUSFS + NoMount (experimental)' "$WORKFLOW_FILE" \
  || fail "workflow is missing the NoMount root option"

resolve_clang_version "Recommended (auto-select based on branch)" "lineage-23.2"
assert_eq "clang-r563880c" "$CLANG_VERSION" "LineageOS 23.2 clang"
resolve_clang_version "Recommended (auto-select based on branch)" "main"
assert_eq "clang-r596125" "$CLANG_VERSION" "mainline clang"

resolve_susfs_settings sm8550 lineage-20.0
assert_eq "gki-android13-5.15" "$SUSFS_REF" "Android 13 susfs"
resolve_susfs_settings sm8550 lineage-23.2
assert_eq "gki-android14-5.15" "$SUSFS_REF" "Android 16 susfs"
version_is_at_least 2.2.0 2.2.0 || fail "SUSFS minimum version equality"
version_is_at_least 2.3.0 2.2.0 || fail "SUSFS newer version acceptance"
if version_is_at_least 2.1.9 2.2.0; then
  fail "SUSFS old version rejection"
fi

infer_android_versions oneplus/sm8550_v_15.0.0_oneplus11
assert_eq "15" "$SUPPORTED_ANDROID_VERSIONS" "OnePlus Android 15 detection"
infer_android_versions sixteen-qpr2
assert_eq "16" "$SUPPORTED_ANDROID_VERSIONS" "Android 16 development detection"

ANYKERNEL_FIXTURE="$(mktemp)"
NOMOUNT_FIXTURE_DIR="$(mktemp -d)"
trap 'rm -f "$ANYKERNEL_FIXTURE"; rm -rf "$NOMOUNT_FIXTURE_DIR"' EXIT
printf '%s\n' \
  'kernel.string=placeholder' \
  'do.devicecheck=0' \
  'device.name1=' \
  'device.name2=' \
  'device.name3=' \
  'device.name4=' \
  'device.name5=' \
  'supported.versions=' > "$ANYKERNEL_FIXTURE"
configure_anykernel_properties "$ANYKERNEL_FIXTURE" "Test Kernel" "salami aston" "16"
grep -q '^kernel.string=Test Kernel$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel string"
grep -q '^do.devicecheck=1$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel device check"
grep -q '^device.name1=salami$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel salami mapping"
grep -q '^device.name2=aston$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel aston mapping"
grep -q '^supported.versions=16$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel Android mapping"

printf '%s\n' 'menu "one"' endmenu 'menu "two"' endmenu > "$NOMOUNT_FIXTURE_DIR/Kconfig"
insert_line_before_last_match \
  "$NOMOUNT_FIXTURE_DIR/Kconfig" \
  endmenu \
  'source "fs/nomount/Kconfig"'
assert_eq "4" "$(grep -nF 'source "fs/nomount/Kconfig"' "$NOMOUNT_FIXTURE_DIR/Kconfig" | cut -d: -f1)" \
  "NoMount Kconfig insertion"

echo "PASS: profiles, SUSFS floor, NoMount integration, and AnyKernel protection"
