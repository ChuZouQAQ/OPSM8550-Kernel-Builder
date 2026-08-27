# scripts/

Shell implementation used by the GitHub Actions workflows.

## Top-level scripts

| Script | Purpose |
| --- | --- |
| `check-upstreams.sh` | Resolves all supported profiles against live upstream refs for the scheduled health workflow. |
| `resolve-profile.sh` | Resolves a valid device/source profile, branch, toolchain, add-ons, and every upstream input to exact commits. |
| `clone-sources.sh` | Fetches exact kernel and modules commits in parallel and prepares the official OnePlus layout when required. |
| `download-clang.sh` | Downloads an AOSP Clang directory from an exact pinned Gitiles commit. |
| `compile-kernel.sh` | Applies integrations, generates config, performs validation-only runs or a full ccache-backed build, and reports timing/cache metrics. |
| `make-anykernel-zip.sh` | Creates a device-checked AnyKernel3 ZIP, provenance manifest, release notes, raw Image asset, and SHA-256 checksums. |
| `publish-diagnostics.sh` | Appends config, SUSFS proof, and NoMount proof files to the job summary. |

## Shared libraries

- `lib/profile-data.sh` contains pure profile, root, Clang, SUSFS, and Android
  version mappings. It performs no network access and is covered by offline tests.
- `lib/git-helpers.sh` provides bounded retries for upstream ref lookup and fetches.
- `lib/anykernel-helpers.sh` applies and verifies device/version protection in
  AnyKernel3 properties.
- `lib/kernel-helpers.sh` edits and verifies Kconfig values and source insertions.
- `lib/ksu-setup.sh` checks out the selected KernelSU implementation at the
  exact resolved commit and connects it to the kernel driver tree.
- `lib/susfs-apply.sh` applies SUSFS at an exact commit, repairs explicitly
  recognized upstream drift, enforces the supported version floor, and rejects
  unknown conflicts.
- `lib/nomount-setup.sh` integrates an exact NoMount commit into the kernel fs
  Kconfig/Makefile only for the explicit experimental preset.
- `lib/verify.sh` performs source, config, hook-mode, and binary verification.

## Tests

`tests/profile-data-test.sh` verifies all supported profile mappings and keeps
the workflow dropdown synchronized with the mapping library. It also checks
representative root, Clang, SUSFS, NoMount, and Android version decisions.

The push/PR validation workflow runs Bash syntax checks, ShellCheck, these
offline tests, and actionlint. The scheduled upstream-health workflow performs
network resolution for every profile plus patch/config and targeted integration
object compilation for all three supported SoC generations.

## Conventions

- Top-level scripts use `set -euo pipefail`.
- Library files are sourced and do not enable shell options themselves.
- Exact upstream commits are resolved before clone/fetch operations.
- Full builds pass ccache compiler launchers on the `make` command line and use
  deterministic Kbuild metadata for repeatability.
- Unknown device/source pairs, invalid branch names, patch rejects, missing
  configs, and missing root/SUSFS/NoMount signatures fail closed.
