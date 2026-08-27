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
assert_eq "10" "${#profiles[@]}" "profile count"

WORKFLOW_FILE="${SCRIPT_DIR}/../../.github/workflows/build.yml"
UPSTREAM_HEALTH_WORKFLOW="${SCRIPT_DIR}/../../.github/workflows/upstream-health.yml"
COMPILE_SCRIPT="${SCRIPT_DIR}/../compile-kernel.sh"
for profile in "${profiles[@]}"; do
  grep -Fq -- "- ${profile}" "$WORKFLOW_FILE" \
    || fail "workflow is missing profile option: $profile"
done
grep -Fq '"CC=ccache clang"' "$COMPILE_SCRIPT" \
  || fail "compile script is not passing ccache on the make command line"
grep -Fq 'KBUILD_BUILD_TIMESTAMP=' "$COMPILE_SCRIPT" \
  || fail "compile script is missing deterministic Kbuild metadata"
if grep -Fq 'CCACHE_PREFIX' "$WORKFLOW_FILE"; then
  fail "workflow must not export ccache's reserved CCACHE_PREFIX variable"
fi
grep -Fq 'CCACHE_KEY_PREFIX' "$WORKFLOW_FILE" \
  || fail "workflow is missing the cache-key-only ccache prefix"
grep -Eq '^[[:space:]]+lld \\' "$UPSTREAM_HEALTH_WORKFLOW" \
  || fail "upstream health workflow is missing the LLVM linker"

expected_socs=(sm7550 sm8450 sm8450 sm8550 sm8550 sm8550 sm8550 sm8650 sm8650 sm8650)
expected_upstream_socs=(sm8550 sm8450 sm8450 sm8550 sm8550 sm8550 sm8550 sm8650 sm8650 sm8650)
expected_codenames=(benz negroni ovaltine salami "salami aston" "salami aston" aston waffle waffle waffle)
expected_devices=("benz OP5D3FL1 CPH2613" "negroni OP516EL1 OP516FL1" "ovaltine OP5551L1 OP5552L1" "salami OP591BL1 OP594DL1" "salami OP591BL1 OP594DL1 aston OP5D35L1" "salami OP591BL1 OP594DL1 aston OP5D35L1" "aston OP5D35L1" "waffle OP5929L1 OP595DL1" "waffle OP5929L1 OP595DL1" "waffle OP5929L1 OP595DL1")

for i in "${!profiles[@]}"; do
  resolve_build_profile "${profiles[$i]}"
  assert_eq "${expected_socs[$i]}" "$SOC" "${profiles[$i]} SoC"
  assert_eq "${expected_upstream_socs[$i]}" "$UPSTREAM_SOC" "${profiles[$i]} upstream SoC"
  assert_eq "${expected_codenames[$i]}" "$DEVICE_CODENAMES" "${profiles[$i]} codenames"
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
resolve_susfs_settings sm7550 lineage-23.0
assert_eq "gki-android14-5.15" "$SUSFS_REF" "Nord CE4 susfs"
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
UPDATE_BINARY_FIXTURE="$(mktemp)"
NOMOUNT_FIXTURE_DIR="$(mktemp -d)"
trap 'rm -f "$ANYKERNEL_FIXTURE" "$UPDATE_BINARY_FIXTURE"; rm -rf "$NOMOUNT_FIXTURE_DIR"' EXIT
printf '%s\n' \
  'kernel.string=placeholder' \
  'do.devicecheck=0' \
  'device.name1=' \
  'device.name2=' \
  'device.name3=' \
  'device.name4=' \
  'device.name5=' \
  'supported.versions=' > "$ANYKERNEL_FIXTURE"
configure_anykernel_properties "$ANYKERNEL_FIXTURE" "Test Kernel" "salami OP591BL1 OP594DL1 aston OP5D35L1" "16"
grep -q '^kernel.string=Test Kernel$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel string"
grep -q '^do.devicecheck=1$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel device check"
grep -q '^device.name1=salami$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel salami mapping"
grep -q '^device.name2=OP591BL1$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel stock ID mapping"
grep -q '^device.name4=aston$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel aston mapping"
grep -q '^device.name5=OP5D35L1$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel 12R stock ID mapping"
grep -q '^supported.versions=16$' "$ANYKERNEL_FIXTURE" || fail "AnyKernel Android mapping"

for i in "${!profiles[@]}"; do
  resolve_build_profile "${profiles[$i]}"
  configure_anykernel_properties \
    "$ANYKERNEL_FIXTURE" \
    "${PROFILE_ID} test kernel" \
    "$DEVICE_NAMES" \
    "16"
  for device_name in $DEVICE_NAMES; do
    grep -q "^device.name[1-5]=${device_name}$" "$ANYKERNEL_FIXTURE" \
      || fail "${profiles[$i]} did not inject device ID: $device_name"
  done
done

printf '%s\n' \
  '  if [ ! "$match" ]; then' \
  '    abort " " "Unsupported device. Aborting...";' \
  '  fi;' > "$UPDATE_BINARY_FIXTURE"
add_anykernel_devicecheck_diagnostics "$UPDATE_BINARY_FIXTURE"
grep -Fq 'ro.product.device=$device' "$UPDATE_BINARY_FIXTURE" \
  || fail "AnyKernel device diagnostics"

printf '%s\n' 'menu "one"' endmenu 'menu "two"' endmenu > "$NOMOUNT_FIXTURE_DIR/Kconfig"
insert_line_before_last_match \
  "$NOMOUNT_FIXTURE_DIR/Kconfig" \
  endmenu \
  'source "fs/nomount/Kconfig"'
assert_eq "4" "$(grep -nF 'source "fs/nomount/Kconfig"' "$NOMOUNT_FIXTURE_DIR/Kconfig" | cut -d: -f1)" \
  "NoMount Kconfig insertion"

echo "PASS: profiles, SUSFS floor, NoMount integration, and AnyKernel protection"
