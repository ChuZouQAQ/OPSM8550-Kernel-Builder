# OnePlus Snapdragon Kernel Builder

GitHub Actions workflow for building OnePlus kernels for Snapdragon 8 Gen 1, 8 Gen 2, and 8 Gen 3 devices.

This repository only contains the CI pipeline and workflow UI. It does not ship kernel source code. The workflow helps you:

- pick a supported OnePlus Snapdragon platform
- resolve the matching upstream kernel and `-modules` repositories
- auto-detect a suitable branch and Clang version for common cases
- apply the selected KernelSU / ReSukiSU variant
- build a raw `Image`
- package an `AnyKernel3` flashable zip
- publish build outputs to both GitHub Releases and workflow artifacts

## Supported Platforms

| Platform | SoC | Typical devices | Recommended source | Kernel config presets |
| --- | --- | --- | --- | --- |
| Snapdragon 8 Gen 1 | `sm8450` | OnePlus 10T / Ace Pro | `lineage-ovaltine-dev` | `vendor/waipio_GKI.config` + `vendor/oplus/waipio_GKI.config` + `vendor/debugfs.config` |
| Snapdragon 8 Gen 2 | `sm8550` | OnePlus 11 / 12R | `LineageOS` | `vendor/kalama_GKI.config` + `vendor/oplus/kalama_GKI.config` + `vendor/debugfs.config` |
| Snapdragon 8 Gen 3 | `sm8650` | OnePlus 12 | `LineageOS` | `vendor/pineapple_GKI.config` + `vendor/oplus/pineapple_GKI.config` |

Additional source presets:

- `SM8550`: `crDroid`, `OnePlus 12R development`
- `SM8650`: `crDroid`

## Highlights

- Single workflow covering multiple OnePlus Snapdragon generations
- Beginner-friendly workflow inputs that resolve to real repo, branch, SoC, and config values
- AOSP Clang caching plus `ccache` reuse for faster repeat builds
- Built-in support for `KernelSU`, `KernelSU-Next`, `KowSU`, and `ReSukiSU`
- Platform-aware `susfs` branch selection for supported presets
- Source-level and binary-level `susfs` verification
- Automatic `AnyKernel3` packaging, GitHub Release creation, and artifact upload

## Workflow Inputs

The workflow is designed so you can build without memorizing the upstream repo layout.

### Platform

Choose one of:

- `Snapdragon 8 Gen 1 (SM8450 / OnePlus 10T / Ace Pro)`
- `Snapdragon 8 Gen 2 (SM8550 / OnePlus 11 / 12R)`
- `Snapdragon 8 Gen 3 (SM8650 / OnePlus 12)`

### Source

Available presets:

- `Recommended source for this platform`
- `LineageOS / community source`
- `crDroid source`
- `OnePlus 12R development source (SM8550 only)`

Unsupported combinations are rejected automatically.

### Branch Mode

- `Use the recommended branch automatically`
- `I want to type the branch name myself`

Auto mode reads the upstream default branch directly from the selected repo.

Manual mode expects a branch such as:

- `lineage-23.2`
- `lineage-23.0`
- `16.0`

### Clang Version

You can keep `Recommended (auto-select based on branch)` or force a manual preset:

- `clang-r563880c (Android 16 / LineageOS 23.2+ era)`
- `clang-r547379 (Android 16 / LineageOS 23.0 era)`
- `clang-r536225 (Android 15 / LineageOS 22.2 era)`
- `clang-r487747c (Android 14 / LineageOS 21 era)`
- `clang-r450784d (Android 13 / LineageOS 20 era)`
- `clang-r416183b1 (Android 12 / LineageOS 19.1 era)`

When auto mode is selected, the workflow maps common branch names to the matching Clang generation and falls back to `clang-r563880c` if it cannot infer a safer default.

### Root / KernelSU Preset

Available options:

- `No root changes`
- `Official KernelSU`
- `KernelSU-Next`
- `KowSU`
- `ReSukiSU`
- `ReSukiSU + susfs`
- `ReSukiSU + susfs + KPM`
- `ReSukiSU + susfs (build both: with KPM and without KPM)`

The last option launches two build jobs so you get both `ReSukiSU + susfs` variants in one run.

## Recommended Quick Start

1. Fork this repository to your own GitHub account.
2. Open `Actions` -> `Build OnePlus Kernel` -> `Run workflow`.
3. For the safest first build, keep:
   - `Source`: `Recommended source for this platform`
   - `Branch Mode`: `Use the recommended branch automatically`
   - `Clang Version`: `Recommended (auto-select based on branch)`
4. Pick the root preset you want and start the workflow.

## Workflow Flow

Each build run goes through the same high-level flow:

1. Resolve your platform, source preset, branch, Clang, and root preset into a real build profile.
2. Validate that both the kernel repo and matching `-modules` repo expose the selected branch.
3. Restore cached Clang and `ccache`, or download the required AOSP Clang if needed.
4. Clone the kernel source and matching modules tree.
5. Apply the selected KernelSU / ReSukiSU changes and generate the final kernel config.
6. Build `Image`.
7. Package the output into an `AnyKernel3` zip.
8. Publish the release assets and upload workflow artifacts.

## susfs Behavior

For `ReSukiSU + susfs` presets, the workflow automatically selects a platform-aware `susfs4ksu` branch:

- `SM8450` -> `gki-android13-5.10`
- `SM8550` + Android 13 style branches -> `gki-android13-5.15`
- `SM8550` + Android 14+ style branches -> `gki-android14-5.15`
- `SM8650` -> `gki-android14-6.1`

Additional safeguards:

- `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` is kept disabled by default for easier verification
- source integration is verified before the full build continues
- final binaries are checked for `susfs` signatures
- ReSukiSU builds are validated to ensure `SUSFS_INLINE_HOOK` is used instead of tracepoint or manual fallback modes

## Build Outputs

Successful runs produce:

- `Image`
- `<soc>_<ksu_type>_<timestamp>.zip`

The workflow also uploads:

- `build.log`
- final `out/.config`
- built `Image`
- final zip package
- `susfs-source-proof.txt` when a `susfs` preset is used
- `susfs-hook-proof.txt` when a `susfs` preset is used
- `susfs-proof.txt` when a `susfs` preset is used

The same `susfs` diagnostics are also copied into the GitHub Actions job summary.

## Environment

GitHub Actions runner setup:

- `ubuntu-latest`
- timeout: `120` minutes
- swap: `16GB`
- cached AOSP Clang toolchains
- persistent `ccache` reuse across repeated builds

Main build dependencies installed by the workflow:

- `bc`
- `bison`
- `flex`
- `libssl-dev`
- `libelf-dev`
- `libdw-dev`
- `build-essential`
- `lz4`
- `git`
- `python3`
- `curl`
- `ccache`
- `dwarves`
- `cpio`
- `gcc-aarch64-linux-gnu`
- `zip`

## Important Notes

- `KernelSU-Next-with-susfs` is intentionally not exposed in this workflow.
- The kernel repo and matching `-modules` repo must both provide the same branch.
- Some upstreams are community-maintained rather than official LineageOS repositories.
- Release publishing depends on GitHub token permissions.

## Known Limitations

- This repository only provides the CI workflow, not kernel source code.
- Build success still depends on upstream branch availability and source compatibility.
- `susfs` patching can still break on upstream tree drift and may need manual adaptation on unusual branches.
- A successful CI build does not guarantee that a packaged kernel is safe for your exact device or flashing setup.
