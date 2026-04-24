# OnePlus Snapdragon Kernel Builder

A GitHub Actions workflow repository for building OnePlus kernels for Snapdragon 8 Gen 1, 8 Gen 2, and 8 Gen 3 devices.

This repository does not ship kernel source code. Instead, it gives you a beginner-friendly GitHub Actions form that can:

- choose the target platform
- pull kernel source and matching modules from supported upstream repositories
- auto-select a suitable branch and Clang version for most common cases
- apply the selected KernelSU variant
- build `Image`
- package an `AnyKernel3` flashable zip
- publish artifacts to GitHub Releases and workflow artifacts

## Supported Platforms

### Snapdragon 8 Gen 1

- SoC: `sm8450`
- Typical devices: OnePlus 10T / Ace Pro
- Recommended source in this workflow: `lineage-ovaltine-dev`
- Kernel config preset: `vendor/waipio_GKI.config` + `vendor/oplus/waipio_GKI.config`

### Snapdragon 8 Gen 2

- SoC: `sm8550`
- Typical devices: OnePlus 11 / 12R
- Recommended source in this workflow: `LineageOS`
- Also supports:
  - `crDroid`
  - `OnePlus 12R development`
- Kernel config preset: `vendor/kalama_GKI.config` + `vendor/oplus/kalama_GKI.config`

### Snapdragon 8 Gen 3

- SoC: `sm8650`
- Typical devices: OnePlus 12
- Recommended source in this workflow: `LineageOS`
- Also supports:
  - `crDroid`
- Kernel config preset: `vendor/pineapple_GKI.config` + `vendor/oplus/pineapple_GKI.config`

## Features

- Supports multiple OnePlus Snapdragon platforms in one workflow
- Auto-resolves the real repo owner, SoC, branch, and build config from simpler UI choices
- Supports multiple AOSP Clang toolchain versions
- Auto-selects a recommended Clang version based on the resolved branch
- Uses `ccache` to speed up repeated builds
- Supports `KernelSU`, `KernelSU-Next`, `KowSU`, and `ReSukiSU`
- Supports selected `susfs` presets
- Builds both raw `Image` and an `AnyKernel3` flashable zip
- Creates a GitHub Release automatically
- Uploads build logs, `.config`, `Image`, and zip files as workflow artifacts

## Action Inputs

The workflow is designed so that people who do not know the repo layout can still use it safely.

### Platform

Choose the chipset and typical device family:

- `Snapdragon 8 Gen 1 (SM8450 / OnePlus 10T / Ace Pro)`
- `Snapdragon 8 Gen 2 (SM8550 / OnePlus 11 / 12R)`
- `Snapdragon 8 Gen 3 (SM8650 / OnePlus 12)`

### Source

Choose where the kernel source should come from:

- `Recommended source for this platform`
- `LineageOS / community source`
- `crDroid source`
- `OnePlus 12R development source (SM8550 only)`

The workflow validates unsupported combinations automatically.

### Branch Mode

- `Use the recommended branch automatically`
- `I want to type the branch name myself`

If you choose automatic mode, the workflow reads the upstream repository default branch for you.

If you choose manual mode, fill in `kernel_branch` yourself, for example:

- `lineage-23.2`
- `lineage-23.0`
- `16.0`

### Clang Version

You can either:

- keep `Recommended (auto-select based on branch)`
- or force a specific Clang version manually

The automatic mode maps common branch names to the matching Clang generation whenever possible.

### Root Solution

Available choices:

- `No root changes`
- `Official KernelSU`
- `KernelSU-Next`
- `KowSU`
- `ReSukiSU`
- `ReSukiSU + susfs`
- `ReSukiSU + susfs + KPM`

## Important Notes

- `KernelSU-Next-with-susfs` is intentionally not exposed in the workflow.
- `ReSukiSU + susfs` and `ReSukiSU + susfs + KPM` now use platform-aware `susfs4ksu` branches automatically:
- `SM8450` -> `gki-android13-5.10`
- `SM8550` + `lineage-20` / Android 13 style branches -> `gki-android13-5.15`
- `SM8550` + `lineage-21+` / Android 14+ style branches -> `gki-android14-5.15`
- `SM8650` -> `gki-android14-6.1`
- The workflow now keeps `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` disabled by default so `susfs` is easier to verify in managers and build artifacts.
- The workflow now performs both source-level and binary-level `susfs` verification for `susfs` presets.
- This workflow requires both the main kernel repository and the matching `-modules` repository to have the same branch.

## Usage

### 1. Fork This Repository

Fork this repository to your own GitHub account.

### 2. Open the Workflow

Go to:

`Actions` -> `Build OnePlus Kernel` -> `Run workflow`

### 3. Recommended Beginner Setup

If you just want the easiest path:

1. Choose your `Platform`
2. Leave `Source` as `Recommended source for this platform`
3. Leave `Branch Mode` as `Use the recommended branch automatically`
4. Leave `Clang Version` as `Recommended (auto-select based on branch)`
5. Pick the `Root Solution` you want

### 4. Wait for CI to Finish

The workflow will:

1. install build dependencies
2. resolve your friendly UI selections into the real build profile
3. validate repo and branch availability
4. restore Clang and `ccache`
5. clone kernel and modules repositories
6. apply the selected KernelSU variant
7. generate `gki_defconfig` and the final `.config`
8. build `Image`
9. package `AnyKernel3`
10. create a GitHub Release
11. upload workflow artifacts

## Build Outputs

Successful builds produce:

- `Image`
- `<soc>_<ksu_type>_<timestamp>.zip`

The workflow also uploads:

- `build.log`
- `susfs-source-proof.txt` when a `susfs` preset is used
- `susfs-proof.txt` when a `susfs` preset is used
- final `out/.config`
- built `Image`
- final zip package

## Source Mapping Used by the Workflow

The workflow resolves friendly source choices to the actual upstream org automatically.

Examples:

- `SM8450` + `Recommended source for this platform` -> `lineage-ovaltine-dev`
- `SM8550` + `Recommended source for this platform` -> `LineageOS`
- `SM8650` + `Recommended source for this platform` -> `LineageOS`

## Environment

GitHub Actions runner setup:

- `ubuntu-latest`
- timeout: `120` minutes
- swap: `16GB`
- Clang: cached per resolved version
- `ccache`: reused across repeated builds

Main build dependencies:

- `bc`
- `bison`
- `flex`
- `libssl-dev`
- `libelf-dev`
- `libdw-dev`
- `build-essential`
- `lz4`
- `python3`
- `curl`
- `ccache`
- `dwarves`
- `cpio`
- `gcc-aarch64-linux-gnu`

## Known Limitations

- This repository only provides the CI build pipeline and does not include kernel source code.
- Build success depends on the availability and compatibility of the selected upstream branch.
- `susfs` compatibility still depends on upstream kernel tree drift, so even with platform-specific patch selection some branches may still need manual adaptation.
- Some upstreams are community-maintained rather than official LineageOS repositories.
- The Release step depends on GitHub token permissions.

## Suggested Future Improvements

- add more source presets per platform
- add platform-specific troubleshooting notes
- show known-good branch examples directly in the workflow summary
- add screenshots for beginners
- add per-platform flashing warnings
