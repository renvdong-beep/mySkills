# Webhook Auto-Onboard v2.0 — New Package Automatic Integration

**Updated**: 2026-05-15

## Overview

When a developer pushes a new package to GitLab, the webhook-server automatically:
1. Detects the new package
2. Reads `intewell.yaml` config from repo root
3. Creates OBS sub-project
4. Sets GitLab CI variables
5. Uploads CI template (based on build target)
6. Enables Runner
7. Triggers Pipeline

## Flow

```
Developer push → GitLab Webhook → webhook-server /gitlab/push
  → detect packages (scan repo for .spec directories)
  → read intewell.yaml (build.target = iso or rpm-only)
  → create OBS sub-project (home:Admin:pkgname) with _meta + _config + _link
  → set GitLab CI/CD variables (PACKAGE_NAME, PACKAGE_DIR, BUILD_TARGET)
  → upload CI template (.gitlab-ci.yml) based on build target
  → enable Runner for project
  → trigger Pipeline
```

## intewell.yaml Config

```yaml
package:
  name: test1
  version: 1.0.0

build:
  target: iso          # iso | rpm-only (default: rpm-only)
  arch:
    - x86_64
    - aarch64
```

- `target: iso` → 8-stage pipeline (includes ISO build)
- `target: rpm-only` → 6-stage pipeline (stops at update-repo)

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/gitlab/push` | POST | GitLab push webhook receiver |
| `/manual/onboard` | POST | Manual trigger for testing |
| `/health` | GET | Health check |
| `/status` | GET | Service status |

## Manual Onboard (for testing)

```bash
curl -X POST http://localhost:8091/manual/onboard \
  -H "Content-Type: application/json" \
  -d '{"project_id": 1, "package_name": "test1", "package_dir": "test1"}'
```

## GitLab Webhook Setup

1. Enable local requests: `gitlab_rails['allow_local_requests_from_hooks_and_services'] = true` in `/etc/gitlab/gitlab.rb`
2. Run `gitlab-ctl reconfigure`
3. Add webhook using host IP (NOT localhost):
   ```bash
   curl -X POST "http://localhost:8080/api/v4/projects/$ID/hooks" \
     --header "PRIVATE-TOKEN: $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"url": "http://192.168.137.103:8091/gitlab/push", "push_events": true}'
   ```

## OBS Sub-Project Creation Details

When creating a new OBS sub-project, the webhook-server:

1. Creates `_meta` XML with `<description>` element (mandatory, otherwise OBS returns 500):
   ```xml
   <project name="home:Admin:pkgname">
     <title>pkgname package build</title>
     <description>pkgname package build for Intewell CI/CD</description>
     <repository name="standard">
       <path project="home:Admin:openEuler24.03-SP1" repository="standard"/>
       <arch>x86_64</arch>
       <arch>aarch64</arch>
     </repository>
   </project>
   ```

2. Sets `_config` with openEuler build config (Type: spec, Preinstall, Order directives)

3. Creates `_link` package in integration project `home:Admin`

## CI Template Selection

- `build.target = iso` → Uses template with 8 stages including `iso-build`
- `build.target = rpm-only` → Uses template with 6 stages (no iso-build)
- No `intewell.yaml` → Defaults to `rpm-only` template

## Key Pitfalls

1. OBS _meta XML must include `<description>` element after `<title>` — missing it causes 500 error
2. GitLab Webhook URL must use host IP (192.168.137.103), not localhost — GitLab rejects localhost URLs
3. GitLab must have `allow_local_requests_from_hooks_and_services = true` enabled
4. OBS sub-project must have `_config` set immediately after creation
5. Dockerfile CMD must use `CMD ["python", "app.py"]` (not hardcoded uvicorn port) so PORT env var works