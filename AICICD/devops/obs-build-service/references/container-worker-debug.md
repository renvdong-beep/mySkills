# OBS Container Worker Debug Session Log

**Date**: 2026-05-13
**Container**: obs-server-test
**Project**: Intewell CI/CD (AICICD)

## Problem Chain & Resolution

### Issue 1: Package Status "excluded"
- **Symptom**: hello-world package showed `excluded` status
- **Investigation**: Claude Code CLI analyzed OBS code, found `findfile` function issue
- **Root cause**: Project config had `Type: rpm` but OBS expects `Type: spec`
- **Fix**: Changed project meta to use `Type: spec`
- **Result**: Status changed to `blocked` (downloading DoD packages)

### Issue 2: DoD Meta File Missing
- **Symptom**: Worker failed to get DoD package binaries
- **Investigation**: Worker logs showed meta file requests failing
- **Fix**: Created empty .meta files for DoD packages
- **Result**: DoD packages started downloading

### Issue 3: Worker Build.pm Not Found
- **Symptom**: 
  ```
  Can't locate Build.pm in @INC (@INC entries checked: /var/run/obs/worker1/build ...)
  ```
- **Investigation**: 
  - Worker creates symlink: `build -> ../../build`
  - In container, `/var/run` is symlink to `/run`
  - So `../../build` resolves to `/run/build` not `/var/run/obs/build`
- **Fix**:
  ```bash
  mkdir -p /var/run/obs/build
  cp -r /usr/lib/obs/server/build/* /var/run/obs/build/
  ```
- **Result**: Worker could now find Build.pm

### Issue 4: hostname Command Not Found
- **Symptom**: Build log showed `hostname: command not found`
- **Fix**: `docker exec obs-server-test dnf install -y hostname`
- **Result**: Build progressed further

### Issue 5: chroot rpm Not Found (UNRESOLVED)
- **Symptom**: 
  ```
  chroot: failed to run command 'rpm': No such file or directory
  ```
- **Investigation**: 
  - Packages downloaded to `/var/cache/obs-worker/1/.pkgs/`
  - init_buildsystem trying to initialize chroot environment
  - rpm binary not available in chroot
- **Status**: Build environment initialization failing
- **Next steps**: Investigate init_buildsystem, DoD configuration, and preinstall packages

## Key File Locations

| Path | Purpose |
|------|---------|
| `/usr/lib/obs/server/` | OBS server binaries |
| `/usr/lib/obs/server/build/` | Build scripts (Build.pm, etc.) |
| `/var/run/obs/worker<N>/` | Worker state directory |
| `/var/run/obs/build/` | Build scripts for workers (must be created) |
| `/var/cache/obs-worker/<N>/` | Worker build cache/chroot |
| `/srv/obs/jobs/<arch>/` | Job queue |
| `/srv/obs/jobs/<arch>/.logfile.badhost/` | Badhost error logs |
| `/srv/obs/repos/` | Repository storage |

## Service Management

```bash
# Check running services
docker exec obs-server-test ps aux | grep bs_

# Start Redis
docker exec obs-server-test redis-server --daemonize yes

# Start OBS services
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_srcserver --port 5352 --daemonize'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_repserver --daemonize'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_sched x86_64'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_dispatch'

# Start workers
docker exec -d obs-server-test bash -c 'for i in 1 2; do cd /usr/lib/obs/server && perl bs_worker --root /var/cache/obs-worker/${i} --statedir /var/run/obs/worker${i} --arch x86_64 --id worker-${i}-x86_64 --reposerver http://localhost:5252 --nocodeupdate; done'
```

## API Endpoints

```bash
# API base: http://<host>:4455
# Credentials: Admin/admin123

# Build status
curl -u Admin:admin123 "http://192.168.137.103:4455/build/home:Admin/_result"

# Build log
curl -u Admin:admin123 "http://192.168.137.103:4455/build/home:Admin/openEuler_24_03/x86_64/hello-world/_log"

# Trigger rebuild
curl -u Admin:admin123 -X POST -H "Content-Length: 0" \
  "http://192.168.137.103:4455/build/home:Admin?cmd=rebuild&package=hello-world"
```

## Lessons Learned

1. **Container symlinks are tricky**: `/var/run` → `/run` means relative symlinks may resolve differently than expected
2. **Dispatcher caches badhost**: Must restart dispatcher after fixing worker issues
3. **OBS expects build type names**: Use `Type: spec` not `Type: rpm`
4. **Build environment needs full toolchain**: Container must have rpm, hostname, and other build tools available for chroot
