# GitLab-OBS Pipeline Integration Issues (2026-05-13)

## Overview

After OBS build succeeded, integrating with GitLab CI/CD pipeline revealed additional networking and automation issues.

## Issue 30: GitLab Runner Network Isolation

**Symptom:**
```
curl: (7) Failed to connect to 192.168.137.103 port 4455: Connection refused
```

**Context:**
- OBS Server running on host at port 4455
- GitLab Runner creates job containers with Docker bridge network
- Job container cannot reach host services via host IP

**Root Cause:**
Docker bridge network isolates containers. Even using host IP (192.168.137.103), job container cannot access ports bound to host.

**Solution:**
Configure GitLab Runner to use host network mode for job containers:

```bash
# Edit runner config
docker exec -it gitlab-runner vi /etc/gitlab-runner/config.toml

# Add network_mode = "host" under [runners.docker]
[[runners]]
  executor = "docker"
  [runners.docker]
    image = "python:3.11-slim"
    network_mode = "host"  # ADD THIS

# Restart runner
docker restart gitlab-runner
```

**Verification:**
```bash
# In job container, test connection
curl http://localhost:4455/about
# Should return OBS API info
```

---

## Issue 31: CI Variable URL Configuration

**Symptom:**
```
curl: (7) Failed to connect to localhost port 4455: Connection refused
```

**Context:**
- GitLab Runner configured with `network_mode = "host"`
- CI variables still using host IP: `OBS_API_URL=http://192.168.137.103:4455`

**Root Cause:**
With host network mode, container shares host's network namespace. Inside container, `localhost` refers to host, not container. Using host IP is incorrect.

**Solution:**
Update GitLab CI variables to use `localhost`:

```yaml
# GitLab → Settings → CI/CD → Variables
OBS_API_URL: http://localhost:4455
SYNC_SERVICE_URL: http://localhost:8090
QUALITY_GATE_URL: http://localhost:8081
```

**Why this works:**
- Host network mode: container network = host network
- `localhost` in container = `localhost` on host
- Services bound to host's localhost are accessible

---

## Issue 32: Manual Trigger Blocking Automation

**Symptom:**
Pipeline stops at certain stage, requires manual "Run" button click.

**User Expectation:**
"CI/CD 流程必须全自动，不应有手动触发步骤"

**Root Cause:**
`.gitlab-ci.yml` contains `when: manual` directive on some stages.

**Solution:**
Remove all `when: manual` from pipeline definition:

```yaml
# Before
sync:
  stage: sync
  when: manual  # REMOVE THIS LINE
  script:
    - curl -X POST $SYNC_URL/sync

# After
sync:
  stage: sync
  script:
    - curl -X POST $SYNC_URL/sync
```

**Design Note:**
If approval gates are needed, implement them as automated quality gate services that check conditions programmatically, not as manual buttons.

---

## Full Pipeline Verification

**Pipeline #19 Result:**
```
build        ✅ passed
obs-trigger  ✅ passed
sync         ✅ passed
```

**Build Artifacts:**
- `hello-world-1.0.0-2.1.src.rpm`
- `hello-world-1.0.0-2.1.x86_64.rpm`

**Sync Location:**
`/var/ftp/intewell/rpms/home_Admin/x86_64/`

---

## Configuration Summary

| Component | Configuration | Purpose |
|-----------|---------------|---------|
| GitLab Runner | `network_mode = "host"` | Allow job containers to access host services |
| OBS_API_URL | `http://localhost:4455` | Correct URL for host network mode |
| SYNC_SERVICE_URL | `http://localhost:8090` | Same pattern |
| Pipeline stages | No `when: manual` | Full automation |

---

## Alternative: extra_hosts

If you cannot use host network mode, add `extra_hosts` to runner config:

```toml
[runners.docker]
  extra_hosts = ["host.docker.internal:host-gateway"]
```

Then use `host.docker.internal` in CI variables:

```yaml
OBS_API_URL: http://host.docker.internal:4455
```

**Note:** This works on Linux Docker 20.10+. On older versions or Docker Desktop, behavior differs.