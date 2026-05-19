# OBS aarch64 Cross-Architecture Build Debugging

## Session: 2026-05-14

## Problem Chain
aarch64 hello-world build blocked → "downloading 2 dod packages" → doddata placeholder → unresolvable deps → Worker build script missing → Worker idle

## Resolution Chain

### Step 1: DoD Placeholder (d0d0d0d0) Blocking Downloads
- `BSSched/DoD.pm` `readparsed()` forces all DoD package hdrmd5 to `d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0`
- Even when `:full` has real RPMs, solv pkgid remains placeholder → Scheduler thinks download needed
- Fix: Kill `bs_dodup`, delete `doddata` + `doddata.cookie`, restart scheduler
- After fix: solv regenerated from `:full` RPMs (50KB vs 5MB), real pkgids used

### Step 2: Unresolvable Dependencies After doddata Removal
- Error: "nothing provides python-pip-wheel needed by python3, nothing provides python-setuptools-wheel needed by python3"
- `python3-3.11.6-2.oe2403` Requires: `python-pip-wheel`, `python-setuptools-wheel`
- LTS `python-setuptools-68.0.0-1` does NOT PROVIDES `python-setuptools-wheel`
- SP3 `python-setuptools-68.0.0-2.oe2403sp3` DOES PROVIDES `python-setuptools-wheel`
- Same pattern for `python-pip-wheel` vs `python3-pip`
- Fix: Replace with SP3 versions in `:full` directory

### Step 3: Worker build/build Script Missing
- Worker calls `system("$statedir/build/build", @args)` to execute builds
- `$statedir/build/build` must be an executable script from `/usr/lib/build/`
- In container, this directory is not auto-populated
- Fix: `cp -a /usr/lib/build/ /var/run/obs/worker2/build/` (trailing slash on source!)
- Pitfall: `cp -a /usr/lib/build /var/run/obs/worker2/build` creates nested dir

### Step 4: binfmt_misc Not Mounted in Container
- qemu-aarch64-static exists but binfmt not registered inside container
- Host has registration but container doesn't inherit the mount
- Fix: `mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc`
- Must be re-done after container restart

### Step 5: Worker Idle Despite Scheduled Build
- Worker started without `--srcserver` parameter
- Cannot receive job dispatch from srcserver
- Fix: Add `--srcserver http://localhost:5352` to worker startup

## Key Commands Reference

```bash
# Check build status
docker exec obs-server-test cat /srv/obs/build/home:Admin/standard/aarch64/:packstatus | strings

# Check worker state
docker exec obs-server-test cat /var/run/obs/worker2/state

# Check build log
docker exec obs-server-test cat /srv/obs/build/home:Admin/standard/aarch64/hello-world/logfile

# Trigger rebuild
curl -s -X POST -H "Content-Length: 0" -u Admin:admin123 \
  "http://localhost:4455/build/home:Admin?cmd=rebuild&package=hello-world&repository=standard&arch=aarch64"

# Kill doddata + restart scheduler (fix DoD placeholder)
docker exec obs-server-test bash -c '
  pkill -f "bs_sched aarch64"; pkill -f "bs_dodup"; sleep 2
  rm -f /srv/obs/build/home:Admin:openEuler24.03/standard/aarch64/:full/doddata
  rm -f /srv/obs/build/home:Admin:openEuler24.03/standard/aarch64/:full/doddata.cookie
  rm -f /srv/obs/build/home:Admin:openEuler24.03/standard/aarch64/:full.solv
  rm -f /srv/obs/build/home:Admin/standard/aarch64/:full.solv
  rm -f /srv/obs/build/home:Admin/standard/aarch64/:packstatus
  rm -f /srv/obs/build/home:Admin/standard/aarch64/:schedulerstate
  rm -f /srv/obs/build/home:Admin/standard/aarch64/:depends
'
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && ./bs_sched aarch64'

# Verify RPM provides
rpm -qp --provides <rpm_file> | grep -i wheel

# Mount binfmt_misc in container
docker exec obs-server-test mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc

# Setup worker build directory
docker exec obs-server-test bash -c 'rm -rf /var/run/obs/worker2/build; cp -a /usr/lib/build/ /var/run/obs/worker2/build/'
```

## openEuler Package Version Matrix

| Package | LTS (24.03) | SP3 | Key Difference |
|---------|-------------|-----|----------------|
| python3 | 3.11.6-2 | 3.11.6-20 | Both need python-pip-wheel, python-setuptools-wheel |
| python-setuptools | 68.0.0-1 | 68.0.0-2 | SP3 PROVIDES python-setuptools-wheel, LTS does NOT |
| python-pip-wheel | N/A (python3-pip-23.3.1-1) | 23.3.1-7 | SP3 has separate python-pip-wheel package |
