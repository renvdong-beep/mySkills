# OBS API Hostname Issue — Detailed Analysis

## Problem

When OBS runs inside a Docker container, the `/build/{project}/{repository}/{arch}/{package}` API endpoint returns HTTP 400 with error:

```
unknown host 'container-hostname.mshome.net'
```

This happens even when `BSConfig.pm` has `$hostname = 'localhost'`.

## Root Cause

OBS has two layers:
1. **Backend (bs_srcserver, bs_repserver)** — Perl daemons that read `BSConfig.pm`
2. **Frontend (Rails API)** — Ruby on Rails app that proxies requests to backend

The Rails API generates internal URLs using `Socket.gethostname` (the container's system hostname), NOT the `$hostname` from `BSConfig.pm`. When the Rails API receives a request for `/build/...`, it:
1. Looks up which backend server handles the request
2. Constructs an internal URL using the container hostname
3. Tries to proxy the request to that URL
4. Fails because the hostname is unresolvable from outside the container

## Affected Endpoints

- `GET /build/{project}/{repository}/{arch}/{package}` — List binaries (returns 400)
- `GET /build/{project}/{repository}/{arch}/{package}/{filename}` — Download binary (returns 400)
- These work fine for sub-projects but fail for integration projects with `_link` packages

## Workarounds

### 1. Sync from Sub-Projects (Recommended)

Modify sync-service `sync-all` to:
- Use `/source/{project}` API to get package list (this endpoint works)
- Sync each package from its sub-project (`home:Admin:pkgname`)
- Sub-project `/build/` API works because builds are published there directly

```python
# Modified sync-all logic
url = f"{OBS_API_URL}/source/{project}"  # Works!
response = requests.get(url, auth=auth)
packages = [entry.get("name") for entry in root.findall(".//entry")]

for package in packages:
    sub_project = f"{project}:{package}"  # home:Admin:pkgname
    # Sync from sub_project instead of integration project
```

### 2. Use /published/ API

Access published RPMs via:
```
GET /published/{project}/{repo}/{arch}/{filename}
```
This may bypass the hostname issue as it reads directly from the published repo directory.

### 3. Fix OBS Container Hostname

Set the container hostname to something resolvable:
```bash
docker run --hostname=localhost ...
```
Or add to docker-compose:
```yaml
hostname: localhost
```

## Verification

After applying workaround, verify:
```bash
# Should return XML with binary list
curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin:hello-world/standard/x86_64/hello-world"

# Should NOT return "unknown host"
curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin/standard/x86_64/hello-world"
```

## Session Reference

- Discovered: 2026-05-15 during multi-package parallel CI/CD testing
- Impact: sync-service sync-all returned "No binaries found" for all packages
- Fix applied: Modified sync-service to sync from sub-projects
