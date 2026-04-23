# kernel_opsm8550

A GitHub Actions workflow repository for building OnePlus `sm8550` kernels.

This repository does not include the kernel source itself. Its main purpose is to let you manually trigger CI, pull the kernel source and matching modules repository from a selected upstream, build with the chosen AOSP Clang toolchain and KernelSU variant, package the result, and publish the artifacts automatically.

## Features

- Pulls `android_kernel_oneplus_sm8550` from multiple upstream repositories
- Automatically pulls the matching `android_kernel_oneplus_sm8550-modules` repository
- Supports multiple AOSP Clang toolchain versions
- Uses `ccache` to speed up repeated builds
- Supports `KernelSU`, `KernelSU-Next`, `KowSU`, and `ReSukiSU`
- Supports selected `susfs` combinations
- Generates both `Image` and an `AnyKernel3` flashable zip
- Creates a GitHub Release automatically
- Uploads build logs and key outputs as workflow artifacts

## Currently Supported

### Kernel Source

- `LineageOS`
- `crdroidandroid`
- `OnePlus12R-development`

The upstream URLs follow this format:

```text
https://github.com/<kernel_source>/android_kernel_oneplus_sm8550.git
https://github.com/<kernel_source>/android_kernel_oneplus_sm8550-modules.git
```

### Clang Versions

- `clang-r416183b1`
- `clang-r450784d`
- `clang-r487747c`
- `clang-r536225`
- `clang-r547379`
- `clang-r563880c`

### KernelSU Variants

- `None`
- `Official-KernelSU`
- `KernelSU-Next`
- `KowSU`
- `ReSukiSU`
- `ReSukiSU-with-susfs`
- `ReSukiSU-with-susfs-KPM`

Notes:

- `KernelSU-Next-with-susfs` is intentionally not exposed in the workflow input list.
- As documented in the workflow on April 23, 2026, the upstream entry points for that option were not stable: the previously used raw setup URL returned `404` in GitHub Actions, and the referenced repository did not expose a cloneable `next-susfs` branch.

## Workflow Location

Main workflow file:

- [.github/workflows/build.yml](./.github/workflows/build.yml)

## Usage

### 1. Fork This Repository

Fork this repository to your own GitHub account first.

### 2. Trigger the Workflow Manually

In your GitHub repository, go to:

`Actions` -> `Compile Kernel` -> `Run workflow`

Then fill in the inputs as needed:

- `clang_version`: the AOSP Clang version to build with
- `kernel_source`: the selected upstream source
- `kernel_branch`: the target branch, for example `lineage-23.2`
- `ksu_type`: the KernelSU variant to use

### 3. Wait for the Build to Finish

The workflow will automatically perform these steps:

1. Install dependencies
2. Validate the workflow inputs
3. Download or restore the Clang cache
4. Restore the `ccache` cache
5. Clone the kernel and modules repositories
6. Inject the selected KernelSU and `susfs` changes when needed
7. Generate `gki_defconfig` and the final `.config`
8. Build `Image`
9. Package `AnyKernel3`
10. Create a GitHub Release and upload build artifacts

## Build Outputs

When the build succeeds, the workflow produces:

- `Image`
- `sm8550_<ksu_type>_<timestamp>.zip`

These files are uploaded to the GitHub Release, and key outputs are also uploaded as workflow artifacts.

Release name format:

```text
sm8550_<kernel_source>-<kernel_branch>_<ksu_type>_<timestamp>
```

## Implementation Notes

### 1. Automatic Modules Repository Handling

The workflow does not only clone the main kernel repository. It also clones:

```text
android_kernel_oneplus_sm8550-modules
```

This is required because the current target kernel trees depend on the sibling modules repository during `defconfig` and `Kconfig` resolution.

### 2. Built-In `susfs` Compatibility Handling

The workflow includes several compatibility adjustments, such as:

- injecting `susfs_def.h` into `task_mmu.c` when needed
- handling different KernelSU directory layouts
- patching `Kconfig` and `Makefile` automatically
- enabling `CONFIG_KSU_SUSFS` and related options automatically

### 3. Extra Config for `ReSukiSU-with-susfs-KPM`

When `ReSukiSU-with-susfs-KPM` is selected, the workflow also enables:

- `CONFIG_KPM`
- `CONFIG_KALLSYMS`
- `CONFIG_KALLSYMS_ALL`

## Environment

GitHub Actions runner setup:

- `ubuntu-latest`
- timeout: `120` minutes
- swap: `16GB`
- Clang: cached per selected version
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

## Recommendations

- Do not leave `kernel_branch` empty, or the workflow will fail immediately.
- `LineageOS` and `OnePlus12R-development` usually work best with `lineage-*` branches.
- If the selected upstream branch does not exist, the clone step will fail.
- If you use a `susfs` combination, prefer the options that are explicitly supported by the current workflow.

## Known Limitations

- This repository only provides the CI build pipeline and does not include the kernel source itself.
- Build success depends on the availability and compatibility of the selected upstream branch.
- The `susfs` patches depend on the upstream code structure, so further adaptation may be required if upstream changes significantly.
- The Release step depends on GitHub token permissions for publishing artifacts.

## Use Cases

This repository is useful for:

- quickly verifying whether a specific `sm8550` kernel branch can build in GitHub Actions
- generating test kernels for different KernelSU variants
- automatically producing `Image` and a flashable `AnyKernel3` zip

## Suggested Future Improvements

If you plan to keep maintaining this project, consider adding:

- a supported device list
- recommended branch combinations
- a troubleshooting section for common build failures
- example Release screenshots
- flashing risk notes and warnings
