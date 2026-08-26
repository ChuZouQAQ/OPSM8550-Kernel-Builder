# scripts/

Build pipeline scripts invoked by `.github/workflows/build.yml`. Splitting the
logic out of the YAML gives us proper shell syntax highlighting, makes the
files `shellcheck`-friendly, and keeps each step small enough to read in one
sitting.

## Top-level scripts

| Script | Triggered by workflow step | Purpose |
| --- | --- | --- |
| `select-matrix.sh` | `prepare` job | Maps the selected root solution to one concrete build variant. |
| `resolve-profile.sh` | `Resolve build profile` | Maps inputs to SoC / repo / branch / clang / susfs settings; exports to `$GITHUB_ENV` and `$GITHUB_OUTPUT`. |
| `download-clang.sh` | `Download AOSP Clang` | Downloads the selected AOSP Clang tarball into `toolchains/<version>/`. Skipped on cache hit. |
| `clone-sources.sh` | `Clone kernel source` | Clones kernel + matching `-modules` repos in parallel; moves the official kernel sibling into `kernel_platform/msm-kernel` after both clones finish. |
| `compile-kernel.sh` | `Compile kernel` | Full build orchestration: env, KSU install, susfs apply, defconfig merge, `make Image`, verifications. |
| `make-anykernel-zip.sh` | `Make AnyKernel3 zip` | Clones (or reuses a cached) `AnyKernel3`, drops in `Image`, packages the flashable zip. |
| `publish-diagnostics.sh` | `Publish susfs diagnostics` | Appends a susfs diagnostics section to the job summary. |

## Shared libraries (`lib/`)

`compile-kernel.sh` sources these instead of inlining 500+ lines of shell:

- `lib/kernel-helpers.sh` — small utilities: config value edit, line insertion, driver-dir detection.
- `lib/ksu-setup.sh` — installs the selected KSU variant (Official / Next / KowSU / ReSukiSU) at the exact commit resolved during profile setup.
- `lib/susfs-apply.sh` — checks out `susfs4ksu` at the resolved commit, applies the patch with known vendor-drift recovery, and handles KernelSU/ReSukiSU compatibility.
- `lib/verify.sh` — source-level, binary-level, and ReSukiSU hook-mode verifications.

## Conventions

- Every top-level script starts with `set -euo pipefail` and documents its
  required environment variables.
- Library files under `lib/` are sourced, not executed, and never call `exit`
  before declaring that explicitly.
- No script assumes a specific working directory; `compile-kernel.sh` is the
  one place that `cd`s into the kernel tree, which keeps the rest of the
  pipeline composable.
