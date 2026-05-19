# Phase 3-4 Integration: OBS to Packer Image Build

Session: 2026-05-14

## Problem

User asked: "阶段1-3的产物怎么进入阶段4的Intewell-unified-packer镜像构建"

Need to connect RPM build pipeline (stages 1-3) to image build (stage 4).

## Solution: Dual-Mode Architecture

### Mode A: Manual/Scheduled Build
- Use case: Release builds, batch updates
- Trigger: Manual script or Cron
- Flow: OBS repo → Packer config → dnf install → ISO output

### Mode B: Auto-trigger Build
- Use case: Continuous integration, rapid validation
- Trigger: OBS webhook on build completion
- Flow: OBS build done → Webhook → Packer auto-build → Feishu notification

## Directory Migration

User requirement: Move all data from `/var/ftp` to `/home/nando/AICICD/data` for portability.

### Migration Script Pattern

```bash
#!/bin/bash
# Key steps:
# 1. Create new directory structure
mkdir -p "$NEW_DATA_DIR"/{repos,images/{iso,flash,container},logs/{obs,sync,packer}}

# 2. Use rsync for data migration
rsync -av "$OLD_REPO_PATH/" "$NEW_REPO_PATH/"

# 3. Update service configs (env files, docker-compose)
sed -i "s|$OLD_PATH|$NEW_PATH|g" "$CONFIG_FILE"

# 4. Create symlink for backward compatibility
ln -sf "$NEW_REPO_PATH" "$OLD_REPO_PATH"

# 5. Restart services with new mount paths
docker stop sync-service && docker rm sync-service
docker run -d --name sync-service --network host \
  -v "$NEW_REPO_PATH:/var/ftp/intewell/rpms" \
  -e REPO_BASE_PATH=/var/ftp/intewell/rpms \
  sync-service:latest
```

### New Directory Structure

```
/home/nando/AICICD/data/
├── repos/              # RPM repository (from /var/ftp/intewell/rpms)
│   └── home_Admin/
│       ├── x86_64/
│       ├── aarch64/
│       └── loongarch64/
├── images/             # Image output
│   ├── iso/
│   ├── flash/
│   └── container/
└── logs/               # Log directory
    ├── obs/
    ├── sync/
    └── packer/
```

## Packer Integration Module

### Webhook Receiver (Mode B)

Location: `packer-integration/webhook-receiver/app.py`

Key endpoints:
- `/health` - Health check
- `/webhook/obs-build` - OBS build completion webhook
- `/webhook/manual-trigger` - Manual trigger for testing
- `/builds` - Query recent build logs (Redis)

Port: 8092

### Manual Build Script (Mode A)

Location: `packer-integration/scripts/manual-build.sh`

```bash
# Usage
./manual-build.sh <arch> <board> [config_name]

# Example
./manual-build.sh aarch64 S5000C main_base_aarch64-S5000C-obs.json
```

Key steps:
1. Check OBS repo availability
2. Refresh repo metadata
3. Check local cache (kernel/rootfs)
4. Execute Packer build
5. Copy ISO output to project data directory

### OBS Repo Configuration

Template: `packer-integration/config/obs-repo.template`

```ini
[Intewell_OBS]
name=Intewell OBS Repository
baseurl=http://localhost:5252/home:Admin/openEuler_22.03_LTS/$basearch/
enabled=1
gpgcheck=0
metadata_expire=1h
priority=1
```

Copy to: `Intewell-unified-packer/_internal/appset.d/Intewell_OBS.repo`

### OBS Package Appset

Template: `packer-integration/config/obs-packages.rpm.list`

Copy to: `Intewell-unified-packer/_internal/prebuild_cache/all_appsets/<arch>/obs-packages/`

## Service Ports Summary

| Service | Port | Purpose |
|---------|------|---------|
| GitLab | 8080 | Code repository |
| OBS API | 4455 | OBS Server API |
| OBS Repo | 5252 | OBS HTTP repository |
| sync-service | 8090 | Artifact sync |
| quality-gate | 8081 | Quality checks |
| cve-scanner | 8083 | CVE scanning |
| Redis | 6380 | Cache/queue |
| packer-webhook | 8092 | Packer webhook receiver |

## Key Configuration Patterns

### Project-to-Config Mapping

```python
PROJECT_CONFIG_MAP = {
    "home:Admin": {
        "enabled": True,
        "auto_build": True,  # Mode B enabled
        "configs": {
            "aarch64": ["main_base_aarch64-S5000C-obs.json"],
            "x86_64": ["main_base_x86_64-obs.json"],
        }
    },
    "Intewell:Release": {
        "enabled": True,
        "auto_build": False,  # Manual only
        "configs": {...}
    }
}
```

### Build Output Handling

```python
def copy_build_output(arch, config):
    """Copy ISO to project data directory"""
    output_dir = f"{PACKER_DIR}/out/package/{arch}/{board}"
    target_dir = f"{PROJECT_ROOT}/data/images/iso/{arch}/{board}"
    os.makedirs(target_dir, exist_ok=True)
    shutil.copy2(iso_file, target_dir)
```

## Pitfalls

### 1. rsync Not Installed
**Symptom**: Migration script fails with "rsync: 未找到命令"
**Fix**: `sudo dnf install -y rsync`

### 2. OBS Data Directory Permissions
**Symptom**: `chown: Operation not permitted` on OBS directories
**Cause**: OBS service runs as obs user (UID 103), creates files with that ownership
**Fix**: Skip chown on OBS directories, or use sudo for those specific paths

### 3. Docker Container Mount Path Update
**Symptom**: sync-service still writes to old path after migration
**Cause**: Container was not recreated with new mount
**Fix**: Stop, remove, and recreate container with new `-v` mount path

## Files Created

- `packer-integration/webhook-receiver/app.py` - Webhook receiver service
- `packer-integration/webhook-receiver/Dockerfile` - Container image
- `packer-integration/webhook-receiver/requirements.txt` - Dependencies
- `packer-integration/scripts/manual-build.sh` - Manual build trigger
- `packer-integration/scripts/integrated-build.sh` - Full pipeline script
- `packer-integration/config/obs-repo.template` - OBS repo config
- `packer-integration/config/obs-packages.rpm.list` - Package list
- `packer-integration/README.md` - Module documentation
- `scripts/migrate-data-dir.sh` - Directory migration script
- `docs/architecture/phase3-to-phase4-integration.md` - Full design document (37KB)

## Related

- `obs-build-service` skill - OBS deployment
- `cicd-pipeline-services` skill - Pipeline microservices
- Intewell-unified-packer location: `/home/nando/Intewell-unified-packer/_internal`