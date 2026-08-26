#!/usr/bin/env bash
#
# Post-patch/post-build verification helpers. Sourced, not executed.
#

verify_susfs_source_integration() {
  local ksu_kernel_dir="$1"
  local runtime_file="${ksu_kernel_dir}/runtime/ksud_integration.c"

  test -f fs/susfs.c || {
    echo "::error::fs/susfs.c is missing after applying susfs patches."
    exit 1
  }

  test -f include/linux/susfs.h || {
    echo "::error::include/linux/susfs.h is missing after applying susfs patches."
    exit 1
  }

  test -f include/linux/susfs_def.h || {
    echo "::error::include/linux/susfs_def.h is missing after applying susfs patches."
    exit 1
  }

  grep -Fq 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile || {
    echo "::error::fs/Makefile does not reference susfs.o after applying susfs patches."
    exit 1
  }

  grep -q 'ksu_handle_sys_reboot' kernel/reboot.c || {
    echo "::error::kernel/reboot.c is missing the susfs reboot hook after applying susfs patches."
    exit 1
  }

  grep -R -q 'CMD_SUSFS_SHOW_VERSION' "$ksu_kernel_dir" || {
    echo "::error::KernelSU tree does not expose CMD_SUSFS_SHOW_VERSION, so the manager will not detect susfs."
    exit 1
  }

  if grep -R -q 'ksu_selinux_hide_running' security/selinux; then
    local fake_state_def_re='^[[:space:]]*(__[A-Za-z0-9_]+[[:space:]]+)*struct[[:space:]]+selinux_state[[:space:]]+fake_state([[:space:];=]|$)'
    local running_def_re='^[[:space:]]*(__[A-Za-z0-9_]+[[:space:]]+)*bool[[:space:]]+ksu_selinux_hide_running([[:space:];=]|$)'

    grep -R -Eq "$fake_state_def_re" "$ksu_kernel_dir" || {
      echo "::error::KernelSU tree does not define fake_state required by the susfs SELinux hooks."
      exit 1
    }
    grep -R -Eq "$running_def_re" "$ksu_kernel_dir" || {
      echo "::error::KernelSU tree does not define ksu_selinux_hide_running required by the susfs SELinux hooks."
      exit 1
    }
  fi

  if [[ "$KSU_TYPE" == ReSukiSU* ]]; then
    test -f "$runtime_file" || {
      echo "::error::ReSukiSU runtime file is missing at ${runtime_file}"
      exit 1
    }

    grep -Eq '^[[:space:]]*DEFINE_STATIC_KEY_TRUE\(ksu_is_init_rc_hook_enabled\);$' "$runtime_file" || {
      echo "::error::ReSukiSU runtime compat is missing ksu_is_init_rc_hook_enabled, so susfs builds will fail or silently fall back."
      exit 1
    }

    grep -Eq '^[[:space:]]*DEFINE_STATIC_KEY_TRUE\(ksu_is_input_hook_enabled\);$' "$runtime_file" || {
      echo "::error::ReSukiSU runtime compat is missing ksu_is_input_hook_enabled, so susfs builds will fail or silently fall back."
      exit 1
    }

    if ! grep -Eq '^[[:space:]]*#define ksu_init_rc_hook ksu_is_init_rc_hook_enabled$' "$runtime_file" && \
       ! grep -Eq '^[[:space:]]*#define ksu_init_rc_hook_inactive\(\) \(!static_branch_likely\(&ksu_is_init_rc_hook_enabled\)\)$' "$runtime_file"; then
      echo "::error::ReSukiSU runtime compat is not pointing init_rc hook to the susfs static key."
      exit 1
    fi

    if ! grep -Eq '^[[:space:]]*#define ksu_input_hook ksu_is_input_hook_enabled$' "$runtime_file" && \
       ! grep -Eq '^[[:space:]]*#define ksu_input_hook_inactive\(\) \(!static_branch_likely\(&ksu_is_input_hook_enabled\)\)$' "$runtime_file"; then
      echo "::error::ReSukiSU runtime compat is not pointing input hook to the susfs static key."
      exit 1
    fi
  fi

  {
    echo "==== SUSFS SOURCE PROOF ===="
    echo "kernel_branch=${KERNEL_BRANCH}"
    echo "kernel_commit=${KERNEL_COMMIT}"
    echo "modules_commit=${MODULES_COMMIT}"
    echo "ksu_commit=${KSU_COMMIT}"
    echo "susfs_ref=${SUSFS_REF}"
    echo "susfs_commit=${SUSFS_COMMIT}"
    echo "susfs_patch=${SUSFS_PATCH_FILE}"
    grep -Fn 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile || true
    grep -n 'ksu_handle_sys_reboot' kernel/reboot.c | head -n 5 || true
    grep -R -n 'CMD_SUSFS_SHOW_VERSION' "$ksu_kernel_dir" | head -n 10 || true
    grep -R -nE 'fake_state|ksu_selinux_hide_running' "$ksu_kernel_dir" | head -n 10 || true
    if [[ -f "$runtime_file" ]]; then
      grep -nE 'ksu_is_init_rc_hook_enabled|ksu_is_input_hook_enabled|ksu_init_rc_hook_key_false|ksu_input_hook_key_false' "$runtime_file" | head -n 20 || true
    fi
  } | tee susfs-source-proof.txt
}

verify_susfs_binary_presence() {
  local symbol_hits=0
  local string_hits=0

  if [[ -f out/System.map ]]; then
    grep -E 'susfs_(init|show_version|get_enabled_features)' out/System.map && symbol_hits=1 || true
  fi

  if [[ -f out/vmlinux ]]; then
    strings out/vmlinux | grep -E 'susfs is initialized! version:|CMD_SUSFS_SHOW_VERSION|CONFIG_KSU_SUSFS_SUS_MOUNT' && string_hits=1 || true
  fi

  if [[ "$symbol_hits" -eq 0 && "$string_hits" -eq 0 ]]; then
    echo "::error::susfs config flags were enabled, but no susfs signature was found in the final kernel artifacts."
    exit 1
  fi

  {
    echo "==== SUSFS BINARY PROOF ===="
    echo "kernel_branch=${KERNEL_BRANCH}"
    echo "kernel_commit=${KERNEL_COMMIT}"
    echo "modules_commit=${MODULES_COMMIT}"
    echo "ksu_commit=${KSU_COMMIT}"
    echo "susfs_ref=${SUSFS_REF}"
    echo "susfs_commit=${SUSFS_COMMIT}"
    echo "susfs_patch=${SUSFS_PATCH_FILE}"
    if [[ -f out/System.map ]]; then
      grep -E 'susfs_(init|show_version|get_enabled_features)' out/System.map | head -n 20 || true
    fi
    if [[ -f out/vmlinux ]]; then
      strings out/vmlinux | grep -E 'susfs is initialized! version:|CMD_SUSFS_SHOW_VERSION|CONFIG_KSU_SUSFS_' | head -n 20 || true
    fi
  } | tee susfs-proof.txt
}

verify_resukisu_susfs_hook_mode() {
  test -f build.log || {
    echo "::error::build.log is missing, cannot verify ReSukiSU hook mode."
    exit 1
  }

  if grep -Eq 'using KSU_TRACEPOINT_HOOK|using Tracepoint Syscall Redirect Hook' build.log; then
    echo "::error::ReSukiSU fell back to KSU_TRACEPOINT_HOOK, so the manager will not detect susfs inline mode."
    exit 1
  fi

  if grep -Eq 'using KSU_MANUAL_HOOK|using Manual Hook' build.log; then
    echo "::error::ReSukiSU fell back to KSU_MANUAL_HOOK, so this build is not the expected susfs inline mode."
    exit 1
  fi

  grep -Eq 'using SUSFS_INLINE_HOOK|using SuSFS Inline hook' build.log || {
    echo "::error::ReSukiSU did not report SUSFS_INLINE_HOOK in build.log."
    exit 1
  }

  {
    echo "==== RESUKISU SUSFS HOOK PROOF ===="
    echo "kernel_branch=${KERNEL_BRANCH}"
    echo "kernel_commit=${KERNEL_COMMIT}"
    echo "modules_commit=${MODULES_COMMIT}"
    echo "ksu_commit=${KSU_COMMIT}"
    echo "susfs_ref=${SUSFS_REF}"
    echo "susfs_commit=${SUSFS_COMMIT}"
    grep -nE 'using SUSFS_INLINE_HOOK|using SuSFS Inline hook|using KSU_TRACEPOINT_HOOK|using Tracepoint Syscall Redirect Hook|using KSU_MANUAL_HOOK|using Manual Hook' build.log || true
  } | tee susfs-hook-proof.txt
}
