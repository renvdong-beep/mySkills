# Quality Gate Debug Session - 2026-05-13

## Issue: RPM Metadata Parsing Failure

### Symptom
Quality gate returned "Version not found in RPM metadata" when checking hello-world-1.0.0-2.1.x86_64.rpm

### Root Cause
`rpm -qip` output format has variable spacing between key and value:
```
Name        : hello-world
Version     : 1.0.0
Release     : 2.1
```

The code used `line.startswith("Version:")` which fails because the line starts with `Version     ` (with trailing spaces).

### Debug Process
```bash
# Check raw output format
docker exec cve-scanner rpm -qip /var/ftp/intewell/rpms/home_Admin/x86_64/hello-world-1.0.0-2.1.x86_64.rpm | od -c | head -20

# Shows: V e r s i o n (spaces) : 1 . 0 . 0
```

### Fix
Changed parsing logic to split on `:` and strip both sides:

```python
for line in stdout.split("\n"):
    if ":" in line:
        parts = line.split(":", 1)
        if len(parts) == 2:
            key = parts[0].strip()
            value = parts[1].strip()
            if key == "Version":
                version = value
            elif key == "Release":
                release = value
```

---

## Issue: RPM Signature Check Command Not Working

### Symptom
`rpm -qK` returned "rpmkeys: --query: unknown option"

### Root Cause
Different RPM versions have different command syntax. On openEuler 24.03 with RPM 4.18.2, `rpm -qK` is not supported.

### Fix
Use `rpm -qp --qf` to query signature information:

```python
code, stdout, stderr = run_command([
    "rpm", "-qp", "--qf", "%{SIGPGP:pgpsig}", str(rpm_path)
])
signature = stdout.strip()
if not signature or signature == "(none)":
    return CheckResult(status="warn", details="RPM is not signed")
```

### Test Command
```bash
rpm -qp --qf '%{SIGPGP:pgpsig}\n' /path/to/package.rpm
# Output: (none) for unsigned packages
```

---

## Issue: Docker Container Cannot Access Host Services

### Symptom
Sync service in container returned connection refused when trying to access OBS API at http://192.168.137.103:4455

### Root Cause
Docker bridge network isolates containers from host network. The container could not reach the host's IP address.

### Debug Process
```bash
# From container, test OBS API access
docker exec sync-service curl -s http://192.168.137.103:4455/build
# Returns: exit code 7 (connection refused)

# From host, same test works
curl -s http://192.168.137.103:4455/build
# Returns: XML response
```

### Fix
Use `--network host` mode so container shares host's network stack:

```bash
docker run -d --name sync-service --network host \
  -e OBS_API_URL=http://localhost:4455 \
  sync-service:latest
```

With host networking, `localhost` inside the container refers to the host.

---

## Issue: Port 8080 Already in Use

### Symptom
Sync service failed to start with "address already in use" on port 8080

### Root Cause
Port 8080 was already used by GitLab running on the same host.

### Fix
1. Changed default port to 8090 in app.py
2. Made port configurable via environment variable:

```python
# In app.py
port = int(os.getenv("PORT", "8090"))
uvicorn.run(app, host="0.0.0.0", port=port)
```

```bash
# Start with custom port
docker run -e PORT=8090 -p 8090:8090 sync-service:latest
```

---

## Final Verification

All quality gate checks passed after fixes:

```json
{
    "status": "pass",
    "checks": {
        "version": {"status": "pass", "details": "Version: 1.0.0-2.1"},
        "dependency": {"status": "pass", "details": "All dependencies resolvable (4 total)"},
        "signature": {"status": "warn", "details": "RPM is not signed"},
        "file_conflict": {"status": "pass", "details": "No file conflicts (1 files)"},
        "cve": {"status": "pass", "details": "No CVEs found"}
    }
}
```

Note: Signature check returns "warn" for unsigned packages, which is acceptable for test packages. Production packages should be signed.
