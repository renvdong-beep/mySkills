# Quality Gate Service Implementation Reference

Complete implementation of quality gate service for RPM package validation.

## Quality Checks

| Check | Purpose | Tool |
|-------|---------|------|
| Version | Validate version format | rpm -qip |
| Dependency | Verify dependencies resolvable | repoclosure |
| Signature | Check GPG signature | rpm -qK |
| File Conflict | Detect file conflicts | rpm -qpl |

## Version Check Pattern

```python
import re

VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(-\d+(\.\d+)?)?$")

def check_version(package: str, rpm_file: str, repo_path: str) -> CheckResult:
    """Check version format compliance"""
    rpm_path = Path(repo_path) / rpm_file
    
    # Query RPM info
    result = subprocess.run(["rpm", "-qip", str(rpm_path)], capture_output=True, text=True)
    
    # Parse version from output
    version = None
    release = None
    for line in result.stdout.split("\n"):
        if line.startswith("Version:"):
            version = line.split(":", 1)[1].strip()
        elif line.startswith("Release:"):
            release = line.split(":", 1)[1].strip()
    
    # Validate format
    if not VERSION_PATTERN.match(version):
        return CheckResult(status="warn", details=f"Non-standard version: {version}")
    
    return CheckResult(status="pass", details=f"Version: {version}-{release}")
```

## Dependency Check Pattern

```python
def check_dependencies(package: str, rpm_file: str, repo_path: str) -> CheckResult:
    """Verify all dependencies are resolvable"""
    rpm_path = Path(repo_path) / rpm_file
    
    # Get dependency list
    result = subprocess.run(["rpm", "-qpR", str(rpm_path)], capture_output=True, text=True)
    dependencies = [line.strip() for line in result.stdout.split("\n") if line.strip()]
    
    # Filter rpmlib dependencies (internal)
    dependencies = [d for d in dependencies if not d.startswith("rpmlib(")]
    
    # Use repoclosure to verify
    result = subprocess.run(
        ["repoclosure", "-r", repo_path, "-p", str(rpm_path)],
        capture_output=True, text=True, timeout=120
    )
    
    if "unresolved" in result.stderr.lower():
        return CheckResult(status="fail", details="Unresolved dependencies")
    
    return CheckResult(status="pass", details=f"All dependencies resolvable ({len(dependencies)} total)")
```

## Signature Check Pattern

```python
def check_signature(package: str, rpm_file: str, repo_path: str) -> CheckResult:
    """Verify GPG signature"""
    rpm_path = Path(repo_path) / rpm_file
    
    result = subprocess.run(["rpm", "-qK", str(rpm_path)], capture_output=True, text=True)
    
    if "NOT OK" in result.stdout:
        return CheckResult(status="warn", details="RPM is not signed", data={"signed": False})
    
    if "OK" in result.stdout:
        return CheckResult(status="pass", details="Signature valid", data={"signed": True})
    
    return CheckResult(status="skip", details="No GPG key available")
```

## CVE Scan Trigger Pattern

```python
def trigger_cve_scan(package: str, rpm_file: str, repo_path: str) -> dict:
    """Trigger CVE scan service"""
    payload = {
        "package": package,
        "rpm_file": rpm_file,
        "repo_path": repo_path
    }
    
    response = requests.post(
        CVE_SCANNER_URL,
        json=payload,
        timeout=300  # CVE scan may be slow
    )
    
    return response.json()
```

## Result Model

```python
from pydantic import BaseModel
from typing import Dict, Optional

class CheckResult(BaseModel):
    status: str  # pass, fail, warn, skip
    details: str
    data: Optional[dict] = None

class QualityGateResult(BaseModel):
    status: str  # pass, fail
    project: str
    package: str
    arch: str
    checks: Dict[str, CheckResult]
    timestamp: str
```

## Dockerfile

```dockerfile
FROM openeuler/openeuler:24.03-lts

RUN dnf install -y \
    python3 python3-pip \
    rpm-build createrepo_c repoclosure \
    curl \
    && dnf clean all

WORKDIR /app
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8081
HEALTHCHECK CMD curl -f http://localhost:8081/health || exit 1

CMD ["python3", "app.py"]
```

## Common Issues

1. **repoclosure not found**: Install in Dockerfile
2. **rpm query fails**: Check rpm-build is installed
3. **Signature always skip**: Import GPG keys or accept unsigned packages

## Full Implementation

See project file: `/home/nando/AICICD/03-sync-quality-gate/quality-gate/app.py`