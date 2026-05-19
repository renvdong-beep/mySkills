# OBS API Hostname Fix + Dual-Arch Startup

## Problem

OBS Docker container inherits the host's hostname (e.g., `nando-MS-7E56.mshome.net`).
The OBS Rails API uses `Socket.gethostname` to generate internal URLs for `/build/` and `/published/` endpoints.
When the hostname is not resolvable inside the container, these endpoints return:

```xml
<status code="400"><summary>unknown host 'nando-MS-7E56.mshome.net'</summary></status>
```

This breaks sync-service and any tool that needs to list/download RPMs via the OBS API.

**Note**: The BSConfig.pm `$hostname='localhost'` fix only affects backend daemons (bs_sched, bs_dispatch, bs_worker). The Rails API layer uses a different hostname resolution mechanism.

## Fix

### 1. Add hostname to /etc/hosts (immediate)

```bash
docker exec obs-server-test bash -c 'echo "127.0.0.1 $(hostname)" >> /etc/hosts'
```

This must be done BEFORE starting OBS services. The Rails API reads the hostname at startup.

### 2. Persist in start-obs.sh

Add this right after `set -e` in `/start-obs.sh`:

```bash
# Fix: OBS API hostname resolution (resolves "unknown host" error)
# OBS Rails API uses container hostname to generate internal URLs
# Adding it to /etc/hosts makes it resolvable as 127.0.0.1
echo "127.0.0.1 $(hostname)" >> /etc/hosts
```

### 3. Alternative: Docker --add-host

```bash
docker run --add-host "$(hostname):127.0.0.1" ...
```

This survives container restarts but requires knowing the hostname at `docker run` time.

## Dual-Arch Scheduler + Worker Startup

The default start-obs.sh only starts one scheduler and worker architecture.
For multi-arch builds (x86_64 + aarch64), add to start-obs.sh:

```bash
# Scheduler (x86_64 + aarch64)
perl ${OBS_DIR}/bs_sched x86_64 --daemonize || true
perl ${OBS_DIR}/bs_sched aarch64 --daemonize || true

# Worker 1: x86_64
perl ${OBS_DIR}/bs_worker --instance 1 --arch x86_64 --nocodeupdate \
  --root ${WORKER_DIR} --reposerver http://localhost:5252 \
  --statedir ${WORKER_DIR}/state_1 --hostlabel "x86_64" &

# Worker 2: aarch64 (QEMU emulation)
perl ${OBS_DIR}/bs_worker --instance 2 --arch aarch64 --nocodeupdate \
  --root ${WORKER_DIR} --reposerver http://localhost:5252 \
  --statedir ${WORKER_DIR}/state_2 --hostlabel "aarch64" &
```

**Important**: `--nocodeupdate` flag is required for aarch64 worker to prevent OBS from trying to update the worker code (which fails in Docker).

## Verification

```bash
# Test the /build/ API endpoint
curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin:hello-world/standard/x86_64/hello-world"

# Should return XML with binary list, not "unknown host"
```
