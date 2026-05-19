# OBS Dispatch→Worker Job Assignment Debugging (2026-05-14)

## Session Context

Debugging why `worker-2-aarch64` stays idle despite build being `scheduled`. This document traces the complete dispatch→worker job assignment flow and identifies three root causes.

## The Three Root Causes

### 1. Badhost Marking (Primary Blocker)

After previous build failures (build/build script missing, Permission denied), `bs_dispatch` marked `aarch64:worker-2-aarch64` as a badhost. The badhost data is stored in two locations:

- `/srv/obs/run/dispatch.badhosts` — binary Storable format, contains entries like:
  - `aarch64/home:Admin::standard::hello-world-<hash>/aarch64:worker-2-aarch64`
  - `home:Admin/hello-world/aarch64/aarch64:worker-2-aarch64`
- `/srv/obs/jobs/aarch64/.logfile.badhost/<jobid>` — text format: "build on worker-2-aarch64 did not create a logfile"

**Fix**: Delete both files and restart dispatch. Dispatch caches badhosts in memory, so just deleting the file without restarting dispatch won't work.

### 2. Missing --srcserver Parameter

Worker2 was started without `--srcserver http://localhost:5352`. The `--srcserver` parameter is described in bs_worker source as "default value used if buildinfo does not contain srcserver element". While the buildinfo XML does contain `<srcserver>`, the Worker needs this parameter for initial connection.

### 3. Worker Code Check (Potential Blocker)

When dispatch assigns a job via HTTP PUT `/build`, it sends `workercode` and `buildcode` parameters (MD5 hashes of `/usr/lib/obs/server/` and `$statedir/build/` directories). If these don't match the Worker's current codes, the Worker enters `rebooting` state and cycles back to idle without building.

## Dispatch→Worker Flow (Source Code Trace)

### bs_dispatch Main Loop (line 826-1412)

```
while (1) {
  # Read finished jobs
  # Read idle workers from /srv/obs/workers/idle/
  # Parse worker filename: format "hostarch:workerid" (e.g., "aarch64:worker-2-aarch64")
  # Map idle workers to architectures via BSCando::cando
  #   aarch64 => [aarch64, aarch64_ilp32, armv8l:linux32, ...]
  #   x86_64 => [x86_64, i586:linux32, i686:linux32]
  # Read jobs from /srv/obs/jobs/<arch>/
  # Sort jobs by priority/load
  # For each job, find matching idle worker
  # Call assignjob()
  # sleep(1) unless $assigned
}
```

### assignjob() Function (line 239-370)

1. Lock job file: create `$job:status` with code="dispatching"
2. Read buildinfo XML from job file
3. Calculate workercode and buildcode MD5s
4. Read worker info from `/srv/obs/workers/idle/<idlename>`
5. HTTP PUT to `http://<worker_ip>:<worker_port>/build` with:
   - Content-Type: text/xml
   - Body: buildinfo XML
   - Query params: `port=5252`, `workercode=<md5>`, `buildcode=<md5>`, `registerserver=http://localhost:5252`
6. If PUT succeeds:
   - Move worker from idle/ to building/
   - Write job:status with code="building"
   - Return 'assigned'
7. If PUT fails:
   - Check error type: "cannot build anything" → remove worker from idle
   - "cannot build this repository/package" → add to badhost
   - Other RPC error → move worker to down/

### bs_worker HTTP Server (line 3700-3730)

Worker runs as HTTP server with dispatch table:
```
'PUT:/build $jobid:? buildcode:? workercode:? port:? registerserver:? nobadhost:? *:?' => \&startbuild
```

### startbuild() Function (line 3465-3530)

1. Read job data from request body → `job.new.$$`
2. Check state: `die("I am not idle!\n")` unless state eq 'idle'
3. Check workercode: if different, download new code from `http://<peer>:<port>/getworkercode`, set state=rebooting, die
4. Read buildinfo XML from job file
5. Check buildcode: if different, download new code from `http://<peer>:<port>/getbuildcode`
6. Rename `job.new.$$` → `job`
7. If hostcheck enabled, run hostcheck script
8. Return from HTTP server → main loop begins build

### BSServer::server() Return (line 3730-3740)

After `startbuild()` succeeds, BSServer::server() returns with ($state, $buildinfo, $registerserver). Worker then:
- Prints "got job, run build..."
- Calls `dobuild($buildinfo)` which runs `$statedir/build/build` script

## Key Debugging Commands

```bash
# Run dispatch in foreground to see assignment logs
docker exec obs-server-test timeout 5 perl /usr/lib/obs/server/bs_dispatch 2>&1
# Output: "assignjob aarch64/<job> -> aarch64:worker-2-aarch64"
# Output: "assigned 1 jobs"

# Check if Worker received job
docker exec obs-server-test cat /var/run/obs/worker2/job | head -5
# Should show buildinfo XML with <srcserver>, <reposerver>, <bdep> entries

# Check Worker state
docker exec obs-server-test cat /var/run/obs/worker2/state
# <workerstate state="idle"/> = not building (problem!)
# <workerstate state="building"/> = building (good!)

# Check badhosts
docker exec obs-server-test cat /srv/obs/run/dispatch.badhosts | strings
docker exec obs-server-test ls /srv/obs/jobs/aarch64/.logfile.badhost/

# Check idle worker registration
docker exec obs-server-test ls /srv/obs/workers/idle/
docker exec obs-server-test cat /srv/obs/workers/idle/aarch64:worker-2-aarch64 | strings | head -3
# Expected: <worker hostarch="aarch64" ip="127.0.0.1" port="XXXXX" registerserver="http://localhost:5252" workerid="worker-2-aarch64">

# Test Worker HTTP endpoint
docker exec obs-server-test curl -s http://127.0.0.1:<worker_port>/ 2>&1
# Expected: <status code="400"><summary>unknown request</summary></status>
# (Worker is listening but only accepts specific endpoints)

# Check BSCando architecture compatibility
docker exec obs-server-test cat /usr/lib/obs/server/BSCando.pm
# aarch64 => [aarch64, aarch64_ilp32, armv8l:linux32, ...]
# x86_64 => [x86_64, i586:linux32, i686:linux32]
```

## Session Findings

1. **Dispatch DOES assign jobs** — confirmed by foreground run showing "assignjob" and "assigned 1 jobs" repeatedly
2. **Worker DOES receive job file** — `/var/run/obs/worker2/job` contains full buildinfo XML
3. **Worker state remains idle** — despite receiving job, Worker doesn't transition to building
4. **Badhost was the primary blocker** — cleared by deleting dispatch.badhosts and .logfile.badhost
5. **After clearing badhost, dispatch assigns but Worker still idle** — suggests code check or other issue preventing Worker from executing

## Next Steps (Unresolved)

- Run Worker in foreground to see code check output and error messages
- Verify Worker's `$statedir/build/` directory is in sync with `/usr/lib/build/`
- Consider restarting Worker with `--srcserver http://localhost:5352` parameter