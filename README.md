# OnePlus Snapdragon Kernel Builder

GitHub Actions pipeline for building OnePlus Snapdragon 8 Gen 1, 8 Gen 2,
and 8 Gen 3 kernels. The repository contains the build pipeline, validation,
packaging, and release automation; kernel sources are resolved from upstream
repositories at build time.

## Supported build profiles

The workflow exposes only device/source combinations that are intentionally
configured. This avoids late failures caused by selecting an incompatible SoC
and source independently.

| SoC | Target device | AnyKernel codename check | Source preset |
| --- | --- | --- | --- |
| `sm8450` | OnePlus 10 Pro | `negroni` | OnePlus official |
| `sm8450` | OnePlus 10T / Ace Pro | `ovaltine` | LineageOS community |
| `sm8550` | OnePlus 11 | `salami` | OnePlus official |
| `sm8550` | OnePlus 11 / 12R | `salami`, `aston` | LineageOS |
| `sm8550` | OnePlus 11 / 12R | `salami`, `aston` | crDroid |
| `sm8550` | OnePlus 12R | `aston` | OnePlus 12R development |
| `sm8650` | OnePlus 12 | `waffle` | OnePlus official |
| `sm8650` | OnePlus 12 | `waffle` | LineageOS |
| `sm8650` | OnePlus 12 | `waffle` | crDroid |

The OnePlus 10T community source is intentionally labeled `ovaltine`; it is
not presented as a OnePlus 10 Pro source.

For SM8550 packages, the device check accepts both custom-ROM codenames and
the stock board IDs published by the LineageOS device trees: OnePlus 11 uses
`salami`, `OP591BL1`, or `OP594DL1`; OnePlus 12R uses `aston` or `OP5D35L1`.
The check remains enabled, and a rejected flash prints all four device values
reported to AnyKernel so missing regional aliases can be diagnosed safely.

## Build modes

`Build OnePlus Kernel` offers three modes:

- `Patch/config validation only` clones exact upstream revisions, applies the
  selected KernelSU/SUSFS/NoMount integration, verifies the final config, and
  smoke-compiles the affected SUSFS, VFS, proc, reboot, and NoMount objects
  without spending time on a full kernel compile.
- `Full build (artifact only)` builds and uploads a 14-day workflow artifact.
  This is the default and does not create a permanent GitHub Release.
- `Full build and publish release` builds the same verified artifact, then a
  separate least-privilege job publishes the release.

## Root integrations

Available presets:

- no root changes
- official KernelSU
- KernelSU-Next
- KowSU
- ReSukiSU
- ReSukiSU with SUSFS
- ReSukiSU with SUSFS and NoMount (experimental)

KPM is not exposed because current ReSukiSU no longer supports it. SUSFS
branches are selected from the SoC and Android/kernel branch, and known vendor
include drift is repaired only for explicitly recognized conflicts. Unknown
patch rejects fail closed and are included in diagnostics.

SUSFS builds require upstream v2.2.0 or newer and explicitly verify the
`SUS_MAP` and `OPEN_REDIRECT` features in the final config. The NoMount preset
integrates the exact resolved `master` commit, enables `CONFIG_NOMOUNT=y`, and
checks both source wiring and final kernel signatures. NoMount hooks VFS
operations and is marked experimental by its upstream project, so it remains
an explicit opt-in instead of changing existing build presets.

## Quick start

1. Open `Actions` -> `Build OnePlus Kernel` -> `Run workflow`.
2. Select one device/source profile.
3. Keep automatic branch and Clang selection unless testing a known branch.
4. Select the root integration.
5. Start with `Patch/config validation only` after an upstream update, then run
   a full build when validation passes.
6. Use release mode only for an artifact you intend to keep or distribute.

Manual branch names are validated with Git before they are written to GitHub
Actions environment files. Every kernel, modules, KernelSU, SUSFS, NoMount,
and AnyKernel input is resolved to an exact commit before cloning.

## Build performance

The full build passes `CC="ccache clang"` and host compiler wrappers directly
on every `make` invocation so Kbuild cannot replace the ccache launcher.
Build timestamps, user, and host metadata are deterministic for a given kernel
commit, which improves repeat-build cache hits.

The workflow also:

- clones kernel and modules repositories in parallel at exact commits
- caches the exact pinned AOSP Clang archive
- restores a profile/branch/compiler-specific 3 GB compressed ccache
- reports config, compile, total time, and ccache statistics in the job summary
- uses an adaptive 8/16 GB swap file with low swappiness for full builds

GitHub cache entries are an optimization only. A build remains able to download
or regenerate every cached input.

## Safe packaging and provenance

Generated AnyKernel3 ZIPs enable `do.devicecheck=1` and contain only the
codenames assigned to the selected profile. Android version checking is also
enabled when the selected branch identifies a known Android generation.

Each full build produces `release-assets/` containing:

- a device-checked AnyKernel3 ZIP
- a uniquely named raw `Image`
- `build-info.json` with all exact source commits and the workflow run URL
- `SHA256SUMS`
- generated `release-notes.md`

GitHub Actions uploads these release-ready files as one flat package artifact
and keeps build logs, configuration, SUSFS proofs, and NoMount proofs in a separate diagnostics
artifact. The release job downloads only the package artifact and verifies its
checksums before publishing.

The same `build-info.json` is embedded in the flashable ZIP. Keep a known-good
stock boot image available and never flash a package whose device check does
not match the phone.

## CI security and reliability

The build job has read-only repository permissions and checkout credentials are
not persisted. External kernel Makefiles therefore do not run in a job holding
release write credentials. Release publication runs separately and receives
`contents: write` only after the build artifact succeeds.

Network Git operations use bounded retries. Release creation and asset uploads
are idempotent, time-limited, and retried, preventing a stalled upload from
holding the build runner indefinitely.

All third-party GitHub Actions are pinned to full commit hashes. AOSP Clang
archive URLs are pinned to exact Gitiles commits, and changing the downloader
invalidates the toolchain cache.

## Validation and upstream health

Pushes and pull requests run:

- Bash syntax checks
- ShellCheck at warning severity
- offline tests for all nine profile mappings, root mappings, Clang selection,
  SUSFS selection/version floor, NoMount selection/wiring, Android version
  inference, and workflow option synchronization
- actionlint for all workflow files

`Check upstream health` runs every Monday and can also be started manually. It
resolves exact commits for all nine profiles and performs ReSukiSU + SUSFS +
NoMount patch/config smoke tests on representative SM8450, SM8550, and SM8650
sources.

## Important limitations

- A successful build does not prove that a kernel is safe for every firmware,
  region, or boot stack of the listed device.
- Community sources are not official OnePlus sources.
- Manual or unusual branches may disable Android version checking when their
  version cannot be inferred safely.
- This pipeline builds the raw GKI `Image`; it does not rebuild every vendor
  module or replace device-specific firmware.
- NoMount modifies VFS behavior and upstream labels it experimental. Test its
  dedicated preset on a recoverable device before distributing it.
- Runtime performance tuning is intentionally left at upstream/vendor config
  defaults. Options such as KASAN, LTO mode, scheduler changes, and compiler
  optimization flags require device-specific boot, stability, power, and
  benchmark testing before becoming defaults.
