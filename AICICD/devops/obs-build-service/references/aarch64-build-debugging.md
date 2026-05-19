# aarch64 Build Debugging Session (2026-05-14)

## Context
Building `hello-world` RPM for aarch64 architecture via OBS with qemu-aarch64-static emulation on an x86_64 host.

## Debugging Timeline

### Phase 1: Worker idle, not receiving jobs
- **Symptom**: Worker2 registered as idle, dispatch showed it, but no jobs assigned
- **Root cause 1**: `dispatch.badhosts` file contained `aarch64:worker-2-aarch64` from a previous failed build
- **Fix**: `rm -f /srv/obs/run/dispatch.badhosts` + restart dispatch
- **Lesson**: Any build failure causes dispatch to mark the worker as badhost. Always check badhosts.

### Phase 2: Dispatch assigns job but Worker stays idle
- **Symptom**: Foreground dispatch output showed `assignjob aarch64/home:Admin::standard::hello-world -> aarch64:worker-2-aarch64`, but Worker state remained idle
- **Root cause**: Worker2 was restarted and got a new HTTP port, but the idle file still had the old port. Dispatch tried to PUT /build to the old port.
- **Fix**: Kill Worker2, clear idle file, restart Worker2 so it re-registers with correct port
- **Lesson**: When restarting workers, always clear `/srv/obs/workers/idle/` entries first

### Phase 3: "Permission denied" on build script
- **Symptom**: Worker received job, started build, but logfile showed `/var/run/obs/worker2/build/build: Permission denied`
- **Root cause**: `BUILD_ROOT=/var/cache/obs-worker/2` was owned by `obsrun`, but the `build` script requires it to be owned by `root`
- **Fix**: `chown root:root /var/cache/obs-worker/2`
- **Lesson**: The "Permission denied" error is misleading — it's not about the build script's execute permission, it's about BUILD_ROOT ownership

### Phase 4: "gcc: command not found" in chroot
- **Symptom**: Build started successfully, 138 packages installed in chroot, but `%build` phase failed with `gcc: command not found`
- **Root cause (two-part)**:
  1. hello-world.spec used `gcc` in `%build` but had no `BuildRequires: gcc`
  2. DoD `:full` directory was missing `gmp` and `isl` RPMs (gcc dependencies)
- **Fix**: Added `BuildRequires: gcc` to spec + downloaded gmp/isl to :full
- **Lesson**: Always declare BuildRequires explicitly. Verify DoD :full has all transitive dependencies.

## Key Commands Reference

### Foreground Worker startup (for debugging)
```bash
docker exec obs-server-test bash -c '
  cd /usr/lib/obs/server
  timeout 60 perl bs_worker --root /var/cache/obs-worker/2 \
    --statedir /var/run/obs/worker2 \
    --arch aarch64 --id worker-2-aarch64 \
    --reposerver http://localhost:5252 \
    --srcserver http://localhost:5352 \
    --nocodeupdate 2>&1
'
```

### Check Worker state and port
```bash
docker exec obs-server-test bash -c '
  cat /var/run/obs/worker2/state
  netstat -tlnp | grep perl
  cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | grep port
'
```

### Download missing RPMs to DoD :full
```bash
REPO_URL="https://dl-cdn.openeuler.openatom.cn/openEuler-24.03-LTS/OS/aarch64/Packages"
# List available packages
curl -s "${REPO_URL}/" | grep -o 'href="gcc[^"]*"'
# Download inside container
docker exec obs-server-test bash -c "
  cd /srv/obs/build/home:Admin:openEuler24.03/standard/aarch64/:full/
  curl -sLO '${REPO_URL}/gmp-6.3.0-2.oe2403.aarch64.rpm'
  curl -sLO '${REPO_URL}/isl-0.24-2.oe2403.aarch64.rpm'
  chown obsrun:obsrun *.rpm
"
```

### Full reset sequence (when everything is stuck)
```bash
docker exec obs-server-test bash -c '
  # Kill worker
  kill $(pgrep -f "worker-2-aarch64") 2>/dev/null
  # Clear state
  rm -f /srv/obs/workers/idle/aarch64:worker-2-aarch64
  rm -f /srv/obs/run/dispatch.badhosts
  rm -f /var/run/obs/worker2/job
  # Fix BUILD_ROOT ownership
  chown root:root /var/cache/obs-worker/2
  # Restart dispatch
  kill $(pgrep bs_dispatch) 2>/dev/null
  rm -f /srv/obs/run/bs_dispatch.lock
'
# Restart worker
docker exec -d obs-server-test bash -c '
  cd /usr/lib/obs/server
  perl bs_worker --root /var/cache/obs-worker/2 \
    --statedir /var/run/obs/worker2 \
    --arch aarch64 --id worker-2-aarch64 \
    --reposerver http://localhost:5252 \
    --srcserver http://localhost:5352 \
    --nocodeupdate
'
# Restart dispatch
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_dispatch'
# Trigger rebuild
curl -s -X POST -H "Content-Length: 0" -u Admin:admin123 \
  "http://localhost:4455/build/home:Admin?cmd=rebuild&package=hello-world&repository=standard&arch=aarch64"
```

## openEuler 24.03 LTS aarch64 Package Version Notes
- gmp: 6.3.0-2 (NOT 6.2.1-7 which is from older releases)
- isl: 0.24-2 (NOT 0.17-19 which is from older releases)
- gcc: 12.3.1-30
- Always verify exact filenames from repository listing before downloading
