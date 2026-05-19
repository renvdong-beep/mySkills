# start-obs.sh Blocking Fix — `& disown` Pattern

## Problem

OBS container's `/start-obs.sh` blocks after starting `bs_srcserver --daemonize`.
Only `bs_srcserver` starts; all subsequent services (bs_repserver, bs_sched, bs_dispatch, bs_worker, Rails API) never start.

## Root Cause

`perl bs_srcserver --daemonize` does NOT fully detach from the parent shell.
It keeps stdout open, causing the bash script to block waiting for the process to complete.
The `--daemonize` flag only forks the process but doesn't close file descriptors.

## Fix

For ALL perl backend commands in `/start-obs.sh`:

1. Redirect stdout+stderr to log files
2. Background with `&`
3. Detach from shell with `disown`
4. Disable `set -e` to prevent early exit

### Before (blocks script)
```bash
set -e
perl ${OBS_DIR}/bs_srcserver --port 5352 --daemonize || true
perl ${OBS_DIR}/bs_repserver --port 5252 --daemonize 2>&1 || true
perl ${OBS_DIR}/bs_sched x86_64 --daemonize || true
perl ${OBS_DIR}/bs_sched aarch64 --daemonize || true
perl ${OBS_DIR}/bs_dispatch --daemonize || true
```

### After (non-blocking)
```bash
# set -e  # Disabled: allow individual services to fail
perl ${OBS_DIR}/bs_srcserver --port 5352 --daemonize > /var/log/obs/bs_srcserver.log 2>&1 &
disown
perl ${OBS_DIR}/bs_repserver --port 5252 --daemonize > /var/log/obs/bs_repserver.log 2>&1 &
disown
perl ${OBS_DIR}/bs_sched x86_64 --daemonize > /var/log/obs/bs_sched_x86_64.log 2>&1 &
disown
perl ${OBS_DIR}/bs_sched aarch64 --daemonize > /var/log/obs/bs_sched_aarch64.log 2>&1 &
disown
perl ${OBS_DIR}/bs_dispatch --daemonize > /var/log/obs/bs_dispatch.log 2>&1 &
disown
```

### Workers (in for loop)
```bash
for i in 1 2; do
    perl ${OBS_DIR}/bs_worker --nocodeupdate --server http://localhost:5252 \
        --root /var/cache/obs/worker --arch x86_64 --arch aarch64 \
        --jobs 1 --id worker-${i} > /var/log/obs/bs_worker_${i}.log 2>&1 &
    disown
done
```

### Rails API
```bash
cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0 -d > /var/log/obs/rails.log 2>&1 &
disown
```

## Persistence

After modifying `/start-obs.sh` inside the container:
```bash
docker commit obs-server-test obs-server:latest
```

Then recreate the container with the committed image so `/start-obs.sh` changes survive restarts.

## Verification

After `docker restart obs-server-test`, wait ~120 seconds and check:
```bash
docker exec obs-server-test bash -c 'ps aux | grep -E "bs_|rails|worker" | grep -v grep | wc -l'
# Expected: 12+ processes
```
