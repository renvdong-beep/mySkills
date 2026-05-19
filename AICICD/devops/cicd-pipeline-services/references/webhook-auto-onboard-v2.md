# Webhook Server v2.1 — Auto-Onboard + ISO Build Trigger

## Flow

```
Developer push → GitLab Webhook → webhook-server /gitlab/push
  → detect packages (scan repo for .spec directories)
  → read intewell.yaml (build target: iso | rpm-only)
  → create OBS sub-project (home:Admin:pkgname) with _meta + _config
  → set GitLab CI/CD variables (PACKAGE_NAME, PACKAGE_DIR, BUILD_TARGET)
  → upload CI template (.gitlab-ci.yml) — same 6-stage template for all targets
  → enable Runner for project
  → trigger Pipeline
  → if target=iso: monitor Pipeline status, on success trigger Packer ISO build
```

## ISO Build Trigger

When `intewell.yaml` has `target: iso`, webhook-server:
1. Starts `check_pipeline_and_trigger_iso()` in the background task
2. Polls Pipeline status every 30 seconds (max 30 minutes)
3. On Pipeline success: calls `trigger_iso_build()` which runs `integrated-build.sh` via subprocess
4. On Pipeline failure/cancel: skips ISO build, sends notification

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/gitlab/push` | POST | GitLab push webhook handler |
| `/manual/onboard` | POST | Manual onboard trigger (for testing) |
| `/trigger-iso-build` | POST | Direct ISO build trigger |
| `/pipeline-iso-trigger` | POST | Pipeline completion → ISO trigger |
| `/health` | GET | Health check |

## Key Files

- `app.py` — Main FastAPI application with onboard logic + ISO trigger
- `ci_templates.py` — intewell.yaml parser + CI template generator
- `config.py` — Service configuration

## Pitfalls

1. **OBS API 500 on sub-project creation**: OBS requires `<description>` after `<title>` in _meta XML
2. **BackgroundTasks cannot nest**: `onboard_and_build` runs as BackgroundTask; ISO monitoring must run synchronously within it (not as another BackgroundTask)
3. **Pipeline may take 5-10 minutes**: obs-wait stage polls sync-service for build status
4. **Packer ISO build takes 20-40 minutes**: `integrated-build.sh` runs on host via subprocess.Popen