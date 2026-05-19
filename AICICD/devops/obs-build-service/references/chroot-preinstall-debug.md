# OBS Build Environment Debugging - Complete Session

## Summary

This reference documents a complete debugging session that resolved 29 issues to achieve successful RPM builds in OBS 2.10.15 on openEuler 24.03.

## Issue Resolution Chain

### Phase 1: Service Startup Issues

| Issue | Symptom | Resolution |
|-------|---------|------------|
| Redis not running | Scheduler/dispatcher fail | `redis-server --daemonize yes` |
| API auth failure | 401 Unauthorized | Password is `admin123`, not default `admin` |
| Container hostname | `unknown host '0aa3e4b07ae2.mshome.net'` | Set `$hostname = 'localhost'` in BSConfig.pm |

### Phase 2: Project Configuration

| Issue | Symptom | Resolution |
|-------|---------|------------|
| Type: rpm | Package status `excluded` | Change to `Type: spec` |
| No build type | `no build type (project)` | Add `_config` file with `Type: spec` |
| DoD not enabled | Scheduler ignores download repos | Add `$enable_download_on_demand = 1` to BSConfig.pm |
| zstd not supported | XML parse error on .zst files | Patch bs_dodup to add zstd support |

### Phase 3: Worker Issues

| Issue | Symptom | Resolution |
|-------|---------|------------|
| Build.pm not found | `Can't locate Build.pm` | Create `/var/run/obs/build` and fix symlink |
| Worker badhost | Dispatcher marks worker bad | Clear `/srv/obs/jobs/x86_64/.logfile.badhost`, restart dispatcher |
| hostname missing | `hostname: command not found` | `dnf install -y hostname` |

### Phase 4: chroot Environment Issues

| Issue | Symptom | Resolution |
|-------|---------|------------|
| rpm not in chroot | `chroot: failed to run command 'rpm'` | Add `Preinstall: rpm` |
| Dynamic linker missing | `No such file or directory` for existing file | Add glibc to Preinstall with Order constraints |
| librpm.so.9 missing | Shared library error | Add rpm-libs and dependencies to Preinstall |
| Directory conflict | `Can't replace existing directory` | Disable bsdtar, use GNU tar |
| su missing | `chroot: failed to run command 'su'` | Add `util-linux` to Preinstall |
| ld not found | `cannot find 'ld'` | Add `chkconfig` to Preinstall |

## Final Working Configuration

```
Type: spec
Required: rpm-build
Preinstall: rpm util-linux chkconfig
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
Order: filesystem:bash
Prefer: filesystem
ExpandFlags: preinstallexpand
```

## Key Insights

### Preinstall Order Matters

OBS's dependency resolver can reorder packages, breaking assumptions. The `Order:` directive is essential for:
- `filesystem` must install before any package that creates directories
- `glibc` creates `/lib64` which conflicts with `filesystem`
- `chkconfig` must install before `binutils` for alternatives to work

### bsdtar vs GNU tar

bsdtar (libarchive) is stricter about directory conflicts:
- GNU tar: silently merges directories
- bsdtar: fails with "Can't replace existing directory"

For OBS builds with complex preinstall chains, GNU tar is more reliable.

### Worker Build Symlink

The Worker creates `build -> ../../build` symlink which fails in containers where `/var/run` is a symlink to `/run`:
- Expected: `/var/run/obs/worker1/build` -> `/var/run/obs/build`
- Actual: `/run/obs/worker1/build` -> `/run/build` (doesn't exist)

Solution: Create `/var/run/obs/build` directory with Build.pm before starting Worker.

## Verification Commands

```bash
# Check build status
curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin/_result"

# Check build log
curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin/openEuler_24_03/x86_64/hello-world/_log"

# Check worker state
docker exec obs-server-test cat /var/run/obs/worker1/state

# List build artifacts
curl -s -u Admin:admin123 "http://localhost:4455/build/home:Admin/openEuler_24_03/x86_64/hello-world"
```

## Build Success Indicators

```
Wrote: /home/abuild/rpmbuild/SRPMS/hello-world-1.0.0-2.1.src.rpm
Wrote: /home/abuild/rpmbuild/RPMS/x86_64/hello-world-1.0.0-2.1.x86_64.rpm
<status package="hello-world" code="succeeded"/>
```
