# Sync-Service Architecture (2026-05-15)

## Overview

sync-service 同步 OBS 构建的 RPM 到本地仓库，支持多包合并到集成项目仓库。

## Key Design Decisions

### 1. Sync from sub-projects, not integration project

OBS integration project (`home:Admin`) has `_link` packages that cause API hostname issues.
sync-all uses `/source/{project}` API to get package list, then syncs from sub-projects (`home:Admin:pkgname`).

### 2. Auto-merge RPMs to integration repo

After syncing from sub-projects, sync-all copies RPMs to the integration project repo directory
(`home_Admin/standard/{arch}/`) and runs `createrepo_c` to update repodata.

### 3. Fedora base image for createrepo_c

Debian slim image does not have `createrepo_c` package. Changed to `fedora:41` base image
which includes `createrepo_c` natively.

## Directory Structure

```
/data/repos/
├── home_Admin/                    # Integration project repo (merged)
│   └── standard/
│       ├── x86_64/
│       │   ├── hello-world-1.0.0-1.x86_64.rpm
│       │   ├── demo-app-1.0.0-1.x86_64.rpm
│       │   └── repodata/
│       └── aarch64/
│           ├── hello-world-1.0.0-1.aarch64.rpm
│           ├── demo-app-1.0.0-1.aarch64.rpm
│           └── repodata/
├── home_Admin_hello-world/        # Sub-project repo (individual)
│   ├── x86_64/
│   └── aarch64/
└── home_Admin_demo-app/           # Sub-project repo (individual)
    ├── x86_64/
    └── aarch64/
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/obs-build-status/{project}/{package}` | GET | Check OBS build status |
| `/sync-all/{project}/{repository}/{arch}` | POST | Sync all packages from sub-projects + merge + createrepo_c |
| `/update-repo/{arch}` | POST | Update repo metadata |

## Docker Run

```bash
docker run -d --name sync-service --network host \
  -e OBS_API_URL=http://localhost:4455 \
  -e OBS_USERNAME=Admin \
  -e OBS_PASSWORD=admin123 \
  -e REPO_BASE_PATH=/data/repos \
  -v /home/nando/AICICD/data/repos:/data/repos \
  sync-service:latest
```
