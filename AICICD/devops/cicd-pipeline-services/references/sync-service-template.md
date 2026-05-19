# Sync Service Implementation Reference

Complete implementation of artifact sync service for OBS to local repository synchronization.

## Key Features

1. **OBS Integration**: Download RPM artifacts from OBS API
2. **Repository Management**: Sync to local FTP/HTTP repository
3. **Metadata Update**: Automatic createrepo_c execution
4. **Quality Gate Trigger**: Trigger quality checks after sync
5. **Redis Caching**: Cache sync status for status queries
6. **Background Tasks**: Async notification and metadata update

## Core Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | /health | Health check |
| POST | /sync | Sync single package |
| GET | /status/{project}/{package}/{arch} | Get sync status |
| POST | /sync-all/{project}/{repository}/{arch} | Sync all packages |

## Implementation Pattern

```python
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
import requests
import redis

app = FastAPI(title="Sync Service")
redis_client = redis.from_url(REDIS_URL)

class SyncRequest(BaseModel):
    project: str
    package: str
    repository: str
    arch: str

@app.post("/sync")
async def sync_package(sync_req: SyncRequest, background_tasks: BackgroundTasks):
    # 1. Get artifact list from OBS
    binaries = list_build_binaries(sync_req.project, sync_req.package, ...)
    
    # 2. Download each artifact
    for filename in binaries:
        content = download_rpm(...)
        sync_to_repo(project, package, arch, filename, content)
    
    # 3. Update repository metadata (background)
    background_tasks.add_task(update_repo_metadata, repo_path)
    
    # 4. Trigger quality gate (background)
    background_tasks.add_task(trigger_quality_gate, ...)
    
    return {"status": "success", "synced_files": [...]}
```

## OBS API Integration

```python
def list_build_binaries(project: str, package: str, repository: str, arch: str) -> list:
    """Get list of build artifacts from OBS"""
    url = f"{OBS_API_URL}/build/{project}/{repository}/{arch}/{package}"
    response = requests.get(url, auth=(OBS_USER, OBS_PASSWORD))
    
    # Parse XML response
    import xml.etree.ElementTree as ET
    root = ET.fromstring(response.content)
    
    binaries = []
    for entry in root.findall(".//binary"):
        filename = entry.get("filename")
        if filename and (filename.endswith(".rpm") or filename.endswith(".src.rpm")):
            binaries.append(filename)
    
    return binaries

def download_rpm(project: str, package: str, repository: str, arch: str, filename: str) -> bytes:
    """Download RPM file from OBS"""
    url = f"{OBS_API_URL}/build/{project}/{repository}/{arch}/{package}/{filename}"
    response = requests.get(url, auth=(OBS_USER, OBS_PASSWORD), timeout=300)
    
    if response.status_code == 200:
        return response.content
    return None
```

## Repository Management

```python
def sync_to_repo(project: str, package: str, arch: str, filename: str, content: bytes) -> tuple:
    """Sync file to local repository"""
    from pathlib import Path
    
    repo_path = Path(REPO_BASE_PATH) / project.replace(":", "_") / arch
    repo_path.mkdir(parents=True, exist_ok=True)
    
    target_file = repo_path / filename
    with open(target_file, "wb") as f:
        f.write(content)
    
    return str(target_file), True

def update_repo_metadata(repo_path: str):
    """Update repository metadata with createrepo_c"""
    import subprocess
    subprocess.run(["createrepo_c", "--update", repo_path], timeout=120)
```

## Dockerfile

```dockerfile
FROM openeuler/openeuler:24.03-lts

RUN dnf install -y \
    python3 python3-pip \
    createrepo_c curl \
    && dnf clean all

WORKDIR /app
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app.py .
RUN mkdir -p /var/ftp/intewell/rpms

ENV OBS_API_URL=http://obs-server:4455
ENV REPO_BASE_PATH=/var/ftp/intewell/rpms

EXPOSE 8080
HEALTHCHECK --interval=30s CMD curl -f http://localhost:8080/health || exit 1

CMD ["python3", "app.py"]
```

## Common Issues

1. **createrepo_c not found**: Install in Dockerfile
2. **OBS auth fails**: Check OBS_USER/OBS_PASSWORD env vars
3. **Redis connection fails**: Graceful degradation to no-cache mode
4. **Large files timeout**: Increase requests timeout to 300s+

## Full Implementation

See project file: `/home/nando/AICICD/03-sync-quality-gate/sync-service/app.py`