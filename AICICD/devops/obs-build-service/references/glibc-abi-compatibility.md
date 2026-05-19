# glibc ABI Compatibility: OBS Build Environment vs Packer Rootfs

## Problem Statement

When building RPMs in OBS and installing them into a Packer-generated ISO rootfs,
the glibc versions must be compatible. If the OBS build environment has a newer
glibc than the rootfs, compiled binaries may reference ABI symbols that don't exist
at runtime, causing `version 'GLIBC_X.YZ' not found` errors or segfaults.

## Compatibility Rule

**glibc is forward-compatible but NOT backward-compatible.**

- Program compiled against glibc-X → runs on glibc-Y where Y >= X ✅
- Program compiled against glibc-X → runs on glibc-Y where Y < X ❌

This is because glibc uses symbol versioning. Each new glibc release adds new
versioned symbols (e.g., GLIBC_2.34, GLIBC_2.35) while keeping old ones.
A binary records the highest symbol version it needs; the runtime glibc must
provide at least that version.

## Current State (Intewell Project, 2026-05-14)

| Component | openEuler Version | glibc Package | Highest ABI Symbol |
|-----------|-------------------|---------------|-------------------|
| OBS DoD Repository | 24.03 LTS SP3 | glibc-2.38-29.oe2403 | GLIBC_2.34 |
| Packer Rootfs | 24.03 LTS SP1 | glibc-2.38-47.oe2403sp1 | GLIBC_2.35 |

Currently compatible: SP3's GLIBC_2.34 <= SP1's GLIBC_2.35 ✅

But fragile: if SP3 introduces GLIBC_2.38 symbols in a future update,
programs compiled in OBS will fail on SP1 rootfs.

## Recommended Fix

Align OBS DoD repository version with Packer rootfs base version.

Change the DoD download URL in the OBS sub-project meta:
```xml
<!-- From SP3 -->
<download arch="aarch64" url="https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS-SP3/everything/aarch64/" repotype="rpmmd"/>

<!-- To SP1 (matching Packer rootfs) -->
<download arch="aarch64" url="https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS-SP1/everything/aarch64/" repotype="rpmmd"/>
```

## Version Lock Matrix

Maintain in project configuration:
```
BASE_VERSION    = openEuler-24.03-LTS-SP1
OBS_DOD_URL     = https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS-SP1/everything/$arch/
PACKER_ROOTFS   = rootfs_openeuler_24.03-lts-sp1_aarch64
REPO_GLIBC_VER  = glibc-2.38-47.oe2403sp1
```

Any version upgrade must update ALL entries simultaneously.

## Diagnostic Commands

```bash
# Check RPM's required glibc symbols
rpm -qp --requires <rpm_file> | grep libc.so

# Check binary's required glibc symbol versions
rpm2cpio <rpm_file> | cpio -idmv
readelf -V usr/bin/<binary> | grep GLIBC
objdump -T usr/bin/<binary> | grep GLIBC | awk '{print $5}' | sort -V | uniq

# Check rootfs glibc's provided symbol versions
docker run --rm --platform linux/arm64 <rootfs_image> \
  bash -c "objdump -T /lib64/libc.so.6 | grep GLIBC_2 | awk '{print \$5}' | sort -V | uniq | tail -10"

# Check rootfs glibc package version
docker run --rm --platform linux/arm64 <rootfs_image> rpm -q glibc
```

## Key Insight

The OBS DoD version and Packer rootfs version are currently set independently
by different configuration mechanisms. They MUST be kept in sync through a
single source of truth (the version lock matrix) to prevent ABI mismatches.
