# Worker Port Mismatch After Restart

## Problem

When an OBS Worker process is restarted, it binds to a new random HTTP port.
The idle file (`/srv/obs/workers/idle/<arch>:<workerid>`) still records the
**old** port from the previous Worker instance. Dispatch reads the idle file
and tries to HTTP PUT `/build` to the old port, which fails silently.

## Symptoms

- Worker state shows `idle`
- Dispatch logs show `assignjob <arch>/<package> -> <arch>:<workerid>`
- Worker never receives the job (no log output)
- Package stays in `scheduled` state indefinitely
- After timeout, Worker may appear in `dispatch.badhosts`

## Diagnosis

```bash
# 1. Check Worker's actual listening ports
docker exec obs-server-test bash -c 'netstat -tlnp | grep perl'

# 2. Check idle file's recorded port
docker exec obs-server-test bash -c 'cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | head -5'

# 3. Compare - if ports differ, this is the problem
```

## Fix

```bash
# 1. Kill old Worker
docker exec obs-server-test bash -c 'kill $(pgrep -f "worker-2-aarch64")'
sleep 2

# 2. Clear stale idle entry (critical!)
docker exec obs-server-test rm -f /srv/obs/workers/idle/aarch64:worker-2-aarch64

# 3. Restart Worker (it will register with new port)
docker exec -d obs-server-test bash -c 'cd /usr/lib/obs/server && perl bs_worker \
  --root /var/cache/obs-worker/2 --statedir /var/run/obs/worker2 \
  --arch aarch64 --id worker-2-aarch64 \
  --srcserver http://localhost:5352 --reposerver http://localhost:5252 --nocodeupdate'

# 4. Verify port match after restart
sleep 3
docker exec obs-server-test bash -c 'netstat -tlnp | grep perl'
docker exec obs-server-test bash -c 'cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | head -3'
```

## Root Cause Analysis

The Worker HTTP server (`BSServer::server` in bs_worker) binds to a random
ephemeral port on startup. It then writes its address (including port) to the
idle file under `/srv/obs/workers/idle/`. When the Worker process is killed
and restarted, the OS assigns a different ephemeral port, but the old idle
file entry persists until the new Worker overwrites it.

If the old idle file is not cleaned up before restart, there's a race
condition: dispatch may read the stale idle file before the new Worker
registers, and attempt to connect to the old (now-closed) port.

## Prevention

Always clear idle entries before restarting Workers:

```bash
docker exec obs-server-test rm -f /srv/obs/workers/idle/<arch>:<workerid>
```

Or use a wrapper script that handles cleanup automatically.
