# intewell.yaml — Build Target Configuration

## Overview

Developers place `intewell.yaml` in the GitLab repository root to configure build targets.
The webhook-server reads this file during push events and decides whether to trigger ISO build after Pipeline success.

## Schema

```yaml
package:
  name: test1           # Package name (maps to OBS project home:Admin:<name>)
  version: 1.0.0        # Package version

build:
  target: iso           # iso | rpm-only (default: rpm-only)
  arch:                 # Optional, default: both architectures
    - x86_64
    - aarch64
```

## Build Targets (铁律)

| target | CI Pipeline | After Pipeline |
|--------|-------------|----------------|
| `rpm-only` | 6 stages: build → obs-trigger → obs-wait → sync → quality-gate → update-repo | Stop |
| `iso` | 6 stages: build → obs-trigger → obs-wait → sync → quality-gate → update-repo | webhook-server triggers Packer ISO build |

**Key**: CI Pipeline is the SAME for both targets (6 stages to update-repo). The difference is what happens AFTER the Pipeline succeeds:
- `target: iso` → webhook-server monitors Pipeline, on success calls `trigger_iso_build()` which runs `integrated-build.sh`
- `target: rpm-only` → Pipeline completes, no further action

**ISO build is NOT a CI Pipeline stage** — it requires Docker socket, host filesystem mounts, and long build times incompatible with CI Runner containers.

## Fallback Behavior

When no `intewell.yaml` exists:
- `target` defaults to `rpm-only`
- Package name detected from repository directory structure (directories containing `.spec` files)
- Architecture defaults to both x86_64 and aarch64

## CI Variables Set by webhook-server

After reading intewell.yaml, the webhook-server saves these GitLab CI/CD variables:
- `PACKAGE_NAME` — from config or auto-detected
- `PACKAGE_DIR` — same as PACKAGE_NAME
- `PACKAGE_VERSION` — from config or "1.0.0"
- `BUILD_TARGET` — "iso" or "rpm-only"

## webhook-server API

Manual onboard with build target:
```bash
curl -X POST http://localhost:8091/manual/onboard \
  -H "Content-Type: application/json" \
  -d '{"project_id": 1, "package_name": "test1", "package_dir": "test1", "build_target": "iso"}'
```

Manual ISO build trigger:
```bash
curl -X POST http://localhost:8091/trigger-iso-build \
  -H "Content-Type: application/json" \
  -d '{"package_name": "test1"}'
```

Pipeline completion → ISO trigger:
```bash
curl -X POST http://localhost:8091/pipeline-iso-trigger \
  -H "Content-Type: application/json" \
  -d '{"project_id": 1, "pipeline_id": 93, "package_name": "test1"}'
```