# Intewell-unified-packer Integration with OBS

## Overview

Intewell-unified-packer is a Qt GUI application (PyInstaller-packaged) that builds
Intewell OS images. It uses Docker containers (`--network host --privileged`) to
run the actual build process. The OBS integration adds OBS-built RPMs to the
image via a custom appset + dnf repo.

## Directory Structure

```
Intewell-unified-packer/
├── _internal/                    # Mounted as /userdefos in Docker container
│   ├── build.sh                  # Main build script (runs inside container)
│   ├── build_in_docker.sh        # Docker entry point (runs on host)
│   ├── rootfsmake/               # Build helper scripts
│   │   ├── rootfsgen.sh          # Orchestrates runlist + applist install
│   │   ├── install_runlist.sh    # Installs runlist packages
│   │   ├── install_applist.sh    # Installs applist packages
│   │   └── common/
│   │       └── install_rpmlist.sh # Reads .rpm.list, calls dnf install
│   ├── appset.d/                 # Repo files copied into rootfs
│   │   └── obs.repo              # OBS aarch64 repo config
│   ├── system_cfg/               # JSON build configuration files
│   │   ├── main_base_aarch64-S5000C.json
│   │   └── hello-world-aarch64-S5000C.json
│   ├── docker_24.03_build/       # Docker build image tarballs
│   │   └── aarch64/
│   ├── prebuild_cache/           # ✅ Correct location — visible in container
│   │   └── all_appsets/aarch64/
│   │       └── hello-world.app/
│   └── out/                      # Build output directory
│       └── hello-world-aarch64-S5000C/
│           ├── rootfs/           # Extracted rootfs with installed packages
│           ├── appset_path/      # Copied appset directories
│           └── image_base_path/  # ISO staging area
└── prebuild_cache/               # ⚠️ OUTSIDE _internal/ — NOT visible in container!
    └── all_appsets/aarch64/      #    Duplicate, never used, wastes 5.1GB disk
```

## Appset Format

Each `.app` or `.env` directory contains `.rpm.list` files:
```
hello-world.app/
└── hello-world.rpm.list    # Content: "hello-world" (one package name per line, no version)
```

## JSON Configuration Format

```json
{
  "applist": ["hello-world.app"],
  "runlist": ["main.project"],
  "arch": "aarch64",
  "board": ["S5000C"],
  "kernel_version": ["6.12.y"],
  "kernel_config": "intewell-S5000C-rt_defconfig",
  "prebuild_dir": "local_cache"
}
```

## Build Flow

1. `build_in_docker.sh <config.json>` starts Docker container
2. Container mounts `_internal/` → `/userdefos`
3. `build.sh` runs inside container:
   a. Parse JSON config → set APPLIST, RUNLIST, ARCH, BOARD
   b. Extract rootfs tarball
   c. Copy `_internal/appset.d/*.repo` → rootfs `/etc/yum.repos.d/`
   d. `process_prebuild`: Copy appsets from prebuild_cache to appset_path
   e. `install_component` → `rootfsgen.sh`:
      - Install runlist (main.project) via chroot dnf
      - Install applist (hello-world.app) via chroot dnf
   f. Pack rootfs → rootfs.tar.gz
   g. `pack.sh` → genisoimage → ISO

## OBS Integration Steps

1. Build RPM in OBS (e.g., hello-world-1.0.0-3.1.aarch64.rpm)
2. Create local dnf repo:
   ```bash
   mkdir -p /home/nando/AICICD/data/repos/obs-aarch64/
   cp /path/to/hello-world-*.rpm /home/nando/AICICD/data/repos/obs-aarch64/
   createrepo_c /home/nando/AICICD/data/repos/obs-aarch64/
   ```
3. Start HTTP server (MUST cd into repo directory first):
   ```bash
   cd /home/nando/AICICD/data/repos/obs-aarch64 && python3 -m http.server 8082
   ```
4. Create obs.repo in `_internal/appset.d/`:
   ```ini
   [obs-aarch64]
   name=OBS aarch64 Repository
   baseurl=http://localhost:8082/
   enabled=1
   gpgcheck=0
   ```
5. Create appset under `_internal/prebuild_cache/all_appsets/aarch64/`:
   ```
   hello-world.app/hello-world.rpm.list  →  content: "hello-world"
   ```
6. Create JSON config in `_internal/system_cfg/`
7. Run: `bash build_in_docker.sh <config.json>`

## ISO Output Location

```
_internal/out/package/<arch>/<board>/<kernel>-<defconfig>.iso
```

## ISO Verification

```bash
# Extract ROOTFS.TGZ from ISO
isoinfo -i <iso_file> -x "/DATA/ROOTFS.TGZ;1" > /tmp/rootfs.tgz

# Verify package binary exists
tar tzf /tmp/rootfs.tgz | grep "hello-world"
# Expected: ./usr/bin/hello-world
```

## Critical Pitfalls

### 1. prebuild_cache Mount Visibility
The Docker container only sees files under `_internal/`. Appsets placed in the
project-root `prebuild_cache/` (outside `_internal/`) will NOT be found. The
`cp -rf $LOCAL_APPSET_CACHE/* $APPSET_PATH/$ARCH/` step silently skips missing
directories, resulting in empty dnf install commands.

**Fix**: Place appsets under `_internal/prebuild_cache/all_appsets/<arch>/`.

### 2. Duplicate prebuild_cache Directories
Some Packer distributions ship both `<project-root>/prebuild_cache/` and
`_internal/prebuild_cache/`. These are independent directories (different inodes,
not symlinks). The outer one is NEVER used by the build (TOPDIR = _internal,
Docker mounts only _internal). It can waste significant disk space (5.1GB observed).

**How to detect**: `ls -lid <project-root>/prebuild_cache _internal/prebuild_cache`
— if inodes differ, they're duplicates.

**How to verify safe deletion**: 
```bash
diff <(find outer/prebuild_cache -type f | sed 's|outer/prebuild_cache||' | sort) \
     <(find _internal/prebuild_cache -type f | sed 's|_internal/prebuild_cache||' | sort)
```
If outer only has files that also exist in inner (or files you've already copied),
safe to `rm -rf outer/prebuild_cache/`.

### 3. HTTP Server Working Directory
`python3 -m http.server` serves files relative to CWD. If started from the wrong
directory, `repodata/repomd.xml` returns 404 even though the file exists on disk.
Always `cd` into the repo root before starting.

**Verification**: `curl -s http://localhost:8082/repodata/repomd.xml | head -3`
should return XML, not HTML error page.

**Common mistake**: Starting `python3 -m http.server 8082` from `/home/nando/AICICD/`
instead of `/home/nando/AICICD/data/repos/obs-aarch64/`. The server will serve
the wrong directory and repodata paths will 404.

### 4. runlist Failure Cascades
When `main.project` (runlist) references packages unavailable in the configured
repos (e.g., `qt`, `firewall-config` on a minimal OBS repo), dnf throws
`PackagesNotAvailableError`. The `install_rpmlist.sh` script does NOT exit on
failure — it continues to the next step. But if the appset wasn't copied (see
pitfall 1), the applist install gets an empty RPM list.

**Fix for testing**: Create a minimal JSON config with only the applist, or
create a runlist that only contains packages available in your repos.

### 5. Container Network
Packer uses `--network host`, so `localhost` in obs.repo points to the host
machine. The HTTP repo server must be running on the host before starting
the build. If the server dies mid-build, dnf will fail with "Cannot download
repomd.xml".

### 6. createrepo_c Must Be Re-Run After RPM Sync
When sync-service copies a new RPM to the HTTP repo directory, the existing
repodata does NOT include it. Must run `createrepo_c /path/to/repo/` to
regenerate repodata. The HTTP server automatically serves the updated metadata
(no restart needed since python http.server reads from filesystem on each request).

## Full Pipeline (Verified 2026-05-14)

End-to-end chain confirmed working:

```
GitLab push (spec + source code)
    → GitLab CI Pipeline #23
        → build: tar source package
        → obs-trigger: PUT spec + tar.gz to OBS API
        → sync-x86_64: POST to sync-service (arch=x86_64)
        → sync-aarch64: POST to sync-service (arch=aarch64)
    → OBS aarch64 build: hello-world-1.0.0-3.1.aarch64.rpm
    → sync-service: copy RPM to /home/nando/AICICD/data/repos/obs-aarch64/
    → createrepo_c: regenerate repodata
    → HTTP repo (python3 http.server 8082)
    → Packer build_in_docker.sh
        → dnf install hello-world (from obs-aarch64 repo)
        → genisoimage → ISO (1.2GB)
    → ISO verification: ./usr/bin/hello-world in ROOTFS.TGZ ✅
```

## Session History

- 2026-05-14: Initial OBS+Packer integration. Discovered prebuild_cache mount
  issue, HTTP server CWD gotcha, and runlist failure cascade. ISO generated
  (1.1GB) but hello-world not included due to appset not being visible in
  container. Fix identified but not yet applied.
- 2026-05-14 (session 2): Applied all fixes. Key discovery: project-root
  `prebuild_cache/` was a 5.1GB duplicate of `_internal/prebuild_cache/`
  (different inodes, not a symlink). Deleted the outer duplicate to save disk.
  Copied hello-world.app to `_internal/prebuild_cache/`. Rebuilt ISO —
  hello-world-1.0.0-3.1.aarch64.rpm successfully installed via dnf from
  obs-aarch64 repo. Verified `./usr/bin/hello-world` exists in ISO's
  ROOTFS.TGZ via `isoinfo -x` + `tar tzf`. Full pipeline verified:
  OBS build → sync → HTTP repo → Packer dnf install → ISO.
- 2026-05-14 (session 3): Full end-to-end pipeline from GitLab push to ISO.
  Added sync-aarch64 job to .gitlab-ci.yml (was missing, only had x86_64).
  Updated spec via GitLab API (git clone returned 503). Pipeline #23 all
  stages passed: build + obs-trigger + sync-x86_64 + sync-aarch64.
  Re-ran createrepo_c after sync. Packer ISO rebuilt and verified.
  Key lesson: .gitlab-ci.yml must have per-arch sync jobs for multi-arch
  pipelines.
- 2026-05-14 (session 4): User demanded full pipeline visible in GitLab CI
  (not just manual service calls). Re-ran from GitLab push through to ISO.
  Discovered glibc ABI compatibility issue: OBS DoD points to SP3 but
  Packer rootfs is SP1. Currently compatible (SP3 GLIBC_2.34 <= SP1 GLIBC_2.35)
  but fragile. Fix: align DoD URL to SP1. Also designed multi-package
  multi-developer architecture using OBS project isolation + CI_PROJECT_NAME
  auto-mapping + integration project layer-links.
