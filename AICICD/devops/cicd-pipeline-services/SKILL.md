---
name: cicd-pipeline-services
description: Implement CI/CD pipeline microservices - sync services, quality gates, CVE scanners, and artifact management for RPM-based systems.
tags: [cicd, pipeline, fastapi, microservices, rpm, obs, quality-gate, cve, artifacts]
---

# CI/CD Pipeline Microservices

Implement microservices for CI/CD pipelines targeting RPM-based systems (openEuler, CentOS, RHEL). Covers artifact synchronization, quality gates, CVE scanning, and integration with OBS (Open Build Service).

## Triggers

- Building CI/CD pipeline stages
- Implementing artifact sync services
- Creating quality gate checks
- CVE/vulnerability scanning integration
- FastAPI microservices for DevOps

## Architecture Pattern

```
Build System (OBS/Jenkins)
        │
        │ Build Complete Event
        ▼
┌─────────────────┐
│  Sync Service   │  ← Download artifacts
│  (Port 8080)    │  ← Sync to repository
└─────────────────┘  ← Update metadata
        │
        │ Trigger Check
        ▼
┌─────────────────┐
│ Quality Gate    │  ← Version check
│  (Port 8081)    │  ← Dependency check
└─────────────────┘  ← File conflict check
        │
        │ CVE Scan
        ▼
┌─────────────────┐
│ CVE Scanner     │  ← NVD/OSV query
│  (Port 8083)    │  ← Vulnerability report
└─────────────────┘
        │
        ▼
┌─────────────────┐
│   Notifier      │  ← Feishu/WeChat/Slack
└─────────────────┘
```

## Service Templates

### 1. Sync Service (FastAPI)

**Purpose**: Download build artifacts and sync to local repository

**Key features**:
- REST API for sync triggers
- Artifact download with retry
- Repository metadata update (createrepo_c)
- Redis caching for sync status
- Background task execution

**Dependencies**: `fastapi`, `uvicorn`, `requests`, `redis`, `pydantic`

**Port**: 8080

### 2. Quality Gate Service (FastAPI)

**Purpose**: Validate package quality before release

**Checks**:
- Version format (X.Y.Z-release)
- Dependency resolution (repoclosure)
- GPG signature verification
- File conflict detection

**Dependencies**: `fastapi`, `uvicorn`, `requests`, `pydantic`, `rpm-build`, `createrepo_c`

**Port**: 8081

### 3. CVE Scanner Service (FastAPI)

**Purpose**: Scan packages for known vulnerabilities

**Data sources**:
- NVD (National Vulnerability Database)
- OSV (Open Source Vulnerabilities)

**Features**:
- Package info extraction
- CVE database query
- Severity filtering
- Result caching (7 days)

**Dependencies**: `fastapi`, `uvicorn`, `requests`, `pydantic`, `rpm-build`

**Port**: 8083

## Implementation Checklist

### Phase 1: Service Skeleton
- [ ] Create FastAPI app with health endpoint
- [ ] Add Pydantic models for request/response
- [ ] Configure environment variables
- [ ] Add logging

### Phase 2: Core Logic
- [ ] Implement main business logic
- [ ] Add error handling
- [ ] Add retry logic for external calls
- [ ] Implement caching (Redis/file)

### Phase 3: Integration
- [ ] Add background task support
- [ ] Implement notification triggers
- [ ] Add Dockerfile
- [ ] Create docker-compose.yml

### Phase 4: Testing
- [ ] Health check endpoint
- [ ] Main flow test
- [ ] Error case test
- [ ] Integration test

## Common Pitfalls

### 56. GitLab webhook 返回 internal error
**问题**: GitLab 容器无法访问宿主机 IP 上的 webhook-server，返回 `internal error`。

**解决方案**: 
- GitLab Runner 和 webhook-server 都使用 `host` 网络模式
- 在 CI Pipeline 的 build job 中调用 webhook-server 创建 OBS 项目
- webhook payload 必须包含 `before`、`user_name`、`commits` 字段

**验证**: test126 Pipeline #230 success, OBS x86_64 + aarch64 published (2026-05-19)

### 57. webhook payload 缺少必需字段
**问题**: webhook-server 返回 `400 Bad Request`，因为 webhook payload 缺少必需字段。

**错误信息**:
```
3 validation errors for GitLabPushEvent
before: Field required
commits: Field required
user_name: Field required
```

**解决方案**: 在 CI 模板中添加完整 payload:
```yaml
curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"object_kind\": \"push\",
    \"before\": \"abc123\",
    \"after\": \"${CI_COMMIT_SHA}\",
    \"ref\": \"refs/heads/main\",
    \"user_name\": \"ci-bot\",
    \"project\": {\"id\": ${CI_PROJECT_ID}, \"name\": \"${CI_PROJECT_NAME}\"},
    \"repository\": {\"name\": \"${CI_PROJECT_NAME}\"},
    \"commits\": [{\"id\": \"${CI_COMMIT_SHA}\", \"message\": \"CI trigger\"}]
  }"
```

### 58. GitLab Runner 配置丢失
**问题**: 修改 Runner 网络模式后配置文件丢失，Runner 无法连接 GitLab。

**解决方案**: 
- 备份配置文件: `/home/nando/AICICD/deployments/docker-compose/configs/gitlab/config.toml`
- 恢复命令:
```bash
docker run --rm -v /home/nando/AICICD/deployments/docker-compose/configs/gitlab:/config -v /srv/gitlab-runner/config:/output alpine:latest sh -c 'cp /config/config.toml /output/config.toml'
```

### 1. Missing createrepo_c
**Symptom**: Repository metadata update fails
**Fix**: `dnf install -y createrepo_c`

### 2. CVE API Rate Limits
**Symptom**: NVD returns 403 Forbidden
**Fix**: 
- Add NVD_API_KEY environment variable
- Implement request caching
- Use OSV as fallback

### 3. Redis Connection Issues
**Symptom**: Sync status not cached
**Fix**: 
- Check Redis is running: `redis-cli ping`
- Use fallback to file cache if Redis unavailable

### 4. RPM Query in Container
**Symptom**: `rpm: command not found` in quality gate
**Fix**: Install `rpm-build` in Dockerfile:
```dockerfile
RUN dnf install -y rpm-build createrepo_c
```

### 5. Background Tasks Not Running
**Symptom**: Notifications not sent
**Fix**: Use FastAPI BackgroundTasks correctly:
```python
@app.post("/sync")
async def sync(req: SyncRequest, background_tasks: BackgroundTasks):
    # ... sync logic ...
    background_tasks.add_task(send_notification, result)
    return result
```

### 6. RPM Metadata Parsing Format
**Symptom**: Version/Release not found when parsing `rpm -qip` output
**Cause**: Output format is `Version     : 1.0.0` (variable spaces between key and value), so `line.startswith("Version:")` fails
**Fix**: Split on `:` and strip both sides:
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

### 7. RPM Signature Check Command Compatibility
**Symptom**: `rpm -qK` returns "rpmkeys: --query: unknown option" on some systems
**Cause**: Different RPM versions have different command syntax
**Fix**: Use `rpm -qp --qf` instead:
```python
# Check signature info
code, stdout, stderr = run_command([
    "rpm", "-qp", "--qf", "%{SIGPGP:pgpsig}", str(rpm_path)
])
signature = stdout.strip()
if not signature or signature == "(none)":
    # Package is not signed
    return CheckResult(status="warn", details="RPM is not signed")
```

### 8. Docker Container Cannot Access Host Services
**Symptom**: Service in container cannot connect to OBS API on host (connection refused / no route)
**Cause**: Docker bridge network isolates containers from host
**Fix**: Use `--network host` mode:
```bash
docker run -d --name sync-service --network host \
  -e OBS_API_URL=http://localhost:4455 \
  sync-service:latest
```
**Note**: With host networking, container shares host's network stack, so `localhost` refers to the host.

### 8a. GitLab Runner Job Containers Cannot Access Host
**Symptom**: GitLab CI job fails with "Could not connect to server" or "Could not resolve host: host.docker.internal"
**Cause**: GitLab Runner creates job containers with bridge network by default; `host.docker.internal` only works on Docker Desktop (Mac/Windows), not Linux
**Fix**: Configure Runner to use host network for job containers:
```bash
# Edit runner config inside container
docker exec gitlab-runner sh -c "sed -i '/volumes = \\[.*\\]/a\\    network_mode = \\\"host\\\"' /etc/gitlab-runner/config.toml"
docker restart gitlab-runner
```
**Alternative**: Add `extra_hosts` to runner config:
```toml
[runners.docker]
  extra_hosts = ["host.docker.internal:host-gateway"]
```
**CI variables**: Use `localhost` URLs since job container shares host network:
```yaml
variables:
  OBS_API_URL: "http://localhost:4455"
  SYNC_URL: "http://localhost:8090"
```

### 9. Port 8080 Already in Use
**Symptom**: Sync service fails to start with "address already in use"
**Cause**: Port 8080 commonly used by GitLab, Jenkins, or other services
**Fix**: Use alternative port (e.g., 8090) and configure via environment variable:
```python
# In app.py
port = int(os.getenv("PORT", "8090"))
uvicorn.run(app, host="0.0.0.0", port=port)
```
```bash
docker run -e PORT=8090 -p 8090:8090 sync-service:latest
```

### 10. Manual Pipeline Stages Break Automation
**Symptom**: Pipeline stops at certain stage, requires manual button click to continue
**Cause**: `.gitlab-ci.yml` contains `when: manual` directive
**User expectation**: CI/CD pipelines should be fully automated end-to-end
**Fix**: Remove `when: manual` from all stages:
```yaml
# Before (requires manual trigger)
sync:
  stage: sync
  when: manual  # REMOVE THIS

# After (automatic)
sync:
  stage: sync
  # No when: manual - runs automatically after previous stage
```
**Note**: If you need approval gates, implement them as separate quality gate services with automated checks, not manual buttons.

### 11. CI Pipeline Missing Multi-Arch Sync Jobs
**Symptom**: OBS builds succeed for aarch64 but RPMs never reach the local repo; ISO build can't find the package
**Cause**: `.gitlab-ci.yml` only has a single `sync` job for one architecture (typically x86_64), missing aarch64/loongarch64 sync
**Fix**: Split sync into parallel per-arch jobs:
```yaml
sync-x86_64:
  stage: sync
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - 'curl -X POST $SYNC_URL/sync -H "Content-Type: application/json" -d "{\"project\": \"home:Admin\", \"package\": \"hello-world\", \"repository\": \"openEuler_24_03\", \"arch\": \"x86_64\"}"'
  dependencies: [obs-trigger]

sync-aarch64:
  stage: sync
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - 'curl -X POST $SYNC_URL/sync -H "Content-Type: application/json" -d "{\"project\": \"home:Admin\", \"package\": \"hello-world\", \"repository\": \"openEuler_24_03\", \"arch\": \"aarch64\"}"'
  dependencies: [obs-trigger]
```
**After sync**: Must run `createrepo_c` on the repo directory to update repodata, then rebuild ISO.

### 13. Full Pipeline Must Be Visible in GitLab CI
**Symptom**: OBS builds succeed and ISO contains the package, but no pipeline shows in GitLab CI for the aarch64 build
**Cause**: The CI pipeline was tested manually (curl to OBS API, manual sync) without going through GitLab's CI/CD pipeline. The user expects to see the complete chain in GitLab.
**Fix**: Always verify the full chain through GitLab CI, not just individual service calls:
1. Push code to GitLab (triggers pipeline)
2. Verify pipeline jobs appear and succeed in GitLab UI/API
3. Verify OBS build triggered by CI (not manual)
4. Verify sync triggered by CI (not manual)
5. Then proceed to ISO build
**Key**: The pipeline is not "working" until it's visible and passing in GitLab CI.

### 14. createrepo_c Must Be Re-Run After sync-service Copies New RPMs
**Symptom**: Packer ISO build installs old version of package, not the one just synced
**Cause**: sync-service copies RPM files but doesn't regenerate repodata. dnf reads repodata to find available packages, so new RPMs are invisible until createrepo_c runs.
**Fix**: After sync-service completes, run `createrepo_c /path/to/repo/`. The HTTP server automatically serves updated metadata (no restart needed).
**Integration**: Add a post-sync hook or CI step:
```yaml
sync-aarch64:
  script:
    - 'curl -X POST $SYNC_URL/sync -H "Content-Type: application/json" -d "..."'
    - ssh $BUILD_HOST 'createrepo_c /home/nando/AICICD/data/repos/obs-aarch64/'
```

### 12. GitLab API File Update When git clone Fails
**Symptom**: `git clone` returns 503 or connection refused even though GitLab API works
**Cause**: GitLab may be restarting or nginx not fully ready; git protocol needs more services than API
**Fix**: Use GitLab REST API to update files directly:
```bash
# Encode file content as JSON
CONTENT_JSON=$(python3 -c "import json; print(json.dumps(open('/tmp/file.yml').read()))")

# Update file via API
curl -s -X PUT "http://localhost:8080/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  -d "{\"branch\": \"main\", \"content\": $CONTENT_JSON, \"commit_message\": \"Update CI config\"}"
```
**Note**: This creates a commit and triggers a pipeline automatically. URL-encode file paths (e.g., `hello-world%2Fhello-world.spec`).

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| OBS_API_URL | http://localhost:4455 | OBS API endpoint |
| OBS_USER | Admin | OBS username |
| OBS_PASSWORD | admin123 | OBS password |
| REPO_BASE_PATH | /var/ftp/repo | Local repository path |
| REDIS_URL | redis://localhost:6379 | Redis connection |
| QUALITY_GATE_URL | http://localhost:8081/check | Quality gate endpoint |
| CVE_SCANNER_URL | http://localhost:8083/scan | CVE scanner endpoint |
| NOTIFIER_URL | http://localhost:8082/notify | Notification endpoint |
| CVE_CACHE_PATH | /var/cache/cve-scanner | CVE cache directory |
| SEVERITY_THRESHOLD | HIGH | CVE severity threshold |
| NVD_API_KEY | (empty) | NVD API key for higher rate limit |

## Docker Compose Template

```yaml
version: '3.8'

services:
  sync-service:
    build: ./sync-service
    ports: ["8080:8080"]
    environment:
      - OBS_API_URL=http://obs-server:4455
      - REDIS_URL=redis://redis:6379
    volumes:
      - rpm-repo:/var/ftp/repo
    depends_on: [redis]

  quality-gate:
    build: ./quality-gate
    ports: ["8081:8081"]
    volumes:
      - rpm-repo:/var/ftp/repo

  cve-scanner:
    build: ./cve-scanner
    ports: ["8083:8083"]
    volumes:
      - cve-cache:/var/cache/cve-scanner

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

volumes:
  rpm-repo:
  cve-cache:
```

## Testing Commands

```bash
# Health checks
curl http://localhost:8080/health
curl http://localhost:8081/health
curl http://localhost:8083/health

# Sync package
curl -X POST http://localhost:8080/sync \
  -H "Content-Type: application/json" \
  -d '{"project":"home:Admin","package":"hello-world","repository":"openEuler_24_03","arch":"x86_64"}'

# Quality gate check
curl -X POST http://localhost:8081/check \
  -H "Content-Type: application/json" \
  -d '{"project":"home:Admin","package":"hello-world","arch":"x86_64","repo_path":"/var/ftp/repo","new_rpms":["hello-world-1.0.0-1.x86_64.rpm"]}'

# CVE scan
curl -X POST http://localhost:8083/scan \
  -H "Content-Type: application/json" \
  -d '{"package":"hello-world","rpm_file":"hello-world-1.0.0-1.x86_64.rpm","repo_path":"/var/ftp/repo"}'
```

## References

- `references/sync-service-template.md` - Complete sync service implementation
- `references/quality-gate-template.md` - Complete quality gate implementation
- `references/cve-scanner-template.md` - Complete CVE scanner implementation
- `references/quality-gate-debug-session.md` - Debug session: RPM parsing, signature check, Docker networking (2026-05-13)
- `references/gitlab-obs-pipeline-integration.md` - Full pipeline integration: GitLab Runner network config, CI automation, end-to-end verification (2026-05-13)
- `references/architecture-diagram-tracking.md` - Pattern for tracking architecture diagram completeness and progress reports
- `references/progress-documentation-session.md` - Pattern for documenting progress in AGENTS.md, debug docs, and progress reports (2026-05-13)
- `references/phase3-to-phase4-integration.md` - OBS to Packer integration: dual-mode architecture, directory migration, webhook receiver (2026-05-14)
- `references/webhook-auto-onboard-v2.md` - Webhook server v2.1 auto-onboard flow: package detection, OBS sub-project creation, CI variable setup, template upload, pipeline trigger (2026-05-15)
- `references/intewell-yaml-config.md` - intewell.yaml schema, build targets (iso/rpm-only), fallback behavior, CI variables
- `references/automation-iron-law.md` - Automation iron law, GitLab webhook PostgreSQL fix, Docker API version compatibility, OBS health check pattern (2026-05-18)
- `references/gitlab-webhook-localhost-issue.md` - GitLab webhook localhost URL doesn't trigger, must use IP address (2026-05-18)
- `references/iso-build-integration.md` - ISO build integration: build_in_docker.sh path, working directory, permission issues, verification steps (2026-05-18)
- `references/iso-build-genisoimage-fix.md` - ISO build genisoimage fix: unreachable repo, Docker-in-Docker path, working directory, complete trigger_iso_build() implementation (2026-05-18)
- `references/ci-template-dynamic-package-name.md` - CI template reads package.name from intewell.yaml at runtime, solves CI variable timing issue (2026-05-19)
- `templates/intewell.yaml` - intewell.yaml template for build target selection
- `templates/intewell-ci-rpm-only.yml` - CI template for rpm-only target (6 stages)
- `templates/intewell-ci-template.yml` - CI template (6 stages, CI_PROJECT_NAME auto-mapping)
- `templates/intewell-multi-package-ci.yml` - Universal CI/CD pipeline template for multi-package parallel builds
- `scripts/add-test-package.sh` - One-click add test package and trigger full-chain build
- `scripts/check-and-fix-obs.sh` - OBS service health check and auto-repair
- `references/ci-variable-timing-complete-fix.md` - Complete solution for CI variable timing issue: dynamic package.name reading, commit SHA for intewell.yaml, skip CI template upload, automation scripts (2026-05-19)
- `references/gitlab-webhook-network-isolation.md` - GitLab webhook "internal error" due to container network isolation, OBS auto-creation in CI template, complete solution (2026-05-19)
- `references/gitlab-webhook-internal-error-solution.md` - Complete solution for GitLab webhook "internal error": host network mode, CI template webhook trigger, payload fields, verification (2026-05-19)
- `scripts/intewell-push.sh` - git push + auto webhook trigger wrapper (2026-05-19)
- `scripts/trigger-webhook.sh` - Fallback webhook trigger when GitLab fails (2026-05-19)

**Symptom**: 通过 API 上传 `.gitlab-ci.yml` 后 Pipeline 直接 failed，YAML 中 `${VAR}` 变成空字符串

**Root cause**: Python/shell 变量替换会解释 YAML 中的 `${}` 语法

**Fix**: 使用 base64 编码上传:
```bash
CI_B64=$(base64 -w 0 /tmp/ci.yml)
curl -s -X PUT "http://localhost:8080/api/v4/projects/1/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  -d "{\"branch\":\"main\",\"content\":\"$CI_B64\",\"encoding\":\"base64\",\"commit_message\":\"Update CI\"}"
```

### 14. CI 模板应使用 PACKAGE_NAME/PACKAGE_DIR 变量

**Symptom**: CI_PROJECT_NAME 与实际包目录名不匹配导致 `cd` 失败

**Root cause**: GitLab 仓库名 (intewell-test) 可能与包目录名 (hello-world) 不同

**Fix**: 添加 PACKAGE_NAME 和 PACKAGE_DIR 变量，默认值为 CI_PROJECT_NAME，可在 GitLab CI/CD Settings 覆盖:
```yaml
variables:
  PACKAGE_NAME: "${CI_PROJECT_NAME}"
  PACKAGE_DIR: "${CI_PROJECT_NAME}"
```

### 15. OBS 二进制文件上传必须用 -T 参数

**Symptom**: OBS PUT 上传 tar.gz 后文件为 0 字节

**Root cause**: `--data-binary @-` 管道方式上传二进制文件会丢失数据

**Fix**: 必须用 `-T` 文件上传:
```bash
# 正确
curl -s -u Admin:admin123 -X PUT \
  "http://localhost:4455/source/project/package/file.tar.gz" \
  -T /path/to/file.tar.gz

# 错误 (0字节)
cat file.tar.gz | curl -s -u Admin:admin123 -X PUT \
  "http://localhost:4455/source/project/package/file.tar.gz" \
  --data-binary @-
```

### 16. CI Template Variable Mapping — CI_PROJECT_NAME ≠ Package Name

**Symptom**: OBS trigger fails with `unknown_project` because `OBS_PROJECT` resolves to `home:Admin:intewell-test` (GitLab repo name) instead of `home:Admin:hello-world` (OBS package name)

**Root cause**: GitLab CI YAML `variables:` section evaluates `${CI_PROJECT_NAME}` at pipeline creation time. If the GitLab repo name differs from the OBS package name, the mapping is wrong. Setting `OBS_PROJECT: "home:Admin:${CI_PROJECT_NAME}"` in YAML variables hardcodes the repo name.

**Fix**: Do NOT define `OBS_PROJECT` in YAML variables. Instead, use `PACKAGE_NAME` (set as per-project CI/CD variable in GitLab UI/API) directly in script commands:
```yaml
# WRONG — hardcodes repo name
variables:
  OBS_PROJECT: "home:Admin:${CI_PROJECT_NAME}"

# CORRECT — use PACKAGE_NAME in scripts
obs-trigger:
  script:
    - curl ... "${OBS_API_URL}/source/home:Admin:${PACKAGE_NAME}/${PACKAGE_NAME}/..."
```
Set `PACKAGE_NAME` and `PACKAGE_DIR` as GitLab CI/CD variables per project:
```bash
curl -X POST "http://localhost:8080/api/v4/projects/$ID/variables" \
  -H "Content-Type: application/json" \
  -d '{"key":"PACKAGE_NAME","value":"hello-world"}'
curl -X POST "http://localhost:8080/api/v4/projects/$ID/variables" \
  -H "Content-Type: application/json" \
  -d '{"key":"PACKAGE_DIR","value":"hello-world"}'
```

### 17. OBS Tarball Must Include Package-Version Subdirectory

**Symptom**: OBS build fails in `%prep` with `cd: demo-app-1.0.0: No such file or directory`

**Root cause**: RPM `%setup -q` macro expects the tarball to contain a `Name-Version/` top-level directory. Creating tarball with `tar -czvf pkg.tar.gz .` from inside the source directory produces flat content (no subdirectory).

**Fix**: Create tarball with the `Name-Version/` directory structure:
```yaml
# WRONG — flat tarball, %setup -q fails
build:
  script:
    - cd ${PACKAGE_DIR}
    - tar -czvf ../${PACKAGE_NAME}-1.0.0.tar.gz .

# CORRECT — includes Name-Version/ subdirectory
build:
  script:
    - |
      mkdir -p /tmp/${PACKAGE_NAME}-1.0.0
      cp -r ${PACKAGE_DIR}/* /tmp/${PACKAGE_NAME}-1.0.0/
      cd /tmp && tar -czvf ${PACKAGE_NAME}-1.0.0.tar.gz ${PACKAGE_NAME}-1.0.0/
      mv ${PACKAGE_NAME}-1.0.0.tar.gz $CI_PROJECT_DIR/
```

### 18. New OBS Sub-Project Must Have _config Set

**Symptom**: OBS build in new sub-project fails or shows unexpected behavior (missing preinstall packages, wrong build type)

**Root cause**: New OBS sub-projects created via API have empty `_config` by default. They inherit nothing — no `Type: spec`, no `Preinstall`, no `Order` directives.

**Fix**: Always set `_config` when creating a new sub-project, using the same config as the working base project:
```bash
curl -s -u Admin:admin123 -X PUT --data-binary @- \
  "http://localhost:4455/source/home:Admin:NEW-PKG/_config" << 'EOF'
Type: spec
Required: rpm-build
Preinstall: rpm util-linux chkconfig
Order: filesystem:glibc
Order: filesystem:setup
Order: filesystem:libgcc
Order: filesystem:bash
Prefer: filesystem
ExpandFlags: preinstallexpand
EOF
```

### 19. GitLab Runner concurrent Limit Blocks Parallel Pipelines

**Symptom**: Multiple pipelines triggered simultaneously but only one runs at a time; other jobs stay `pending`

**Root cause**: Runner `config.toml` has `concurrent = 1` (default for single-runner setups)

**Fix**: Increase concurrent limit to support parallel pipelines:
```bash
docker exec gitlab-runner sed -i 's/concurrent = 1/concurrent = 4/' /etc/gitlab-runner/config.toml
docker restart gitlab-runner
```
Set `concurrent` to at least the number of parallel pipelines × jobs per pipeline stage (typically 4-8 for multi-package CI/CD).

### 20. GitLab Runner Not Enabled for New Projects

**Symptom**: Pipeline jobs stay `pending` indefinitely for a new project, even though Runner is online and `run_untagged=true`

**Root cause**: A specific Runner (non-shared) must be explicitly enabled for each project. Creating a new GitLab project does NOT automatically make existing runners available to it.

**Fix**: Enable the runner for the new project via API:
```bash
curl -s --header "PRIVATE-TOKEN: $TOKEN" -X POST \
  "http://localhost:8080/api/v4/projects/$PROJECT_ID/runners" \
  -H "Content-Type: application/json" \
  -d "{\"runner_id\": $RUNNER_ID}"
```
**Verify**: `curl -s --header "PRIVATE-TOKEN: $TOKEN" "http://localhost:8080/api/v4/projects/$PROJECT_ID/runners"` should list the runner.

**Alternative**: Use a shared/group runner instead of a project-specific runner. Shared runners are available to all projects by default.

### 21. OBS API /build/ Endpoint Returns 400 "unknown host" for Integration Projects

**Symptom**: `curl -u Admin:admin123 "http://localhost:4455/build/home:Admin/standard/x86_64/hello-world"` returns `<status code="400"><summary>unknown host 'container-hostname'</summary></status>`

**Root cause**: OBS Rails API generates internal URLs using the container's hostname (e.g., `nando-MS-7E56.mshome.net`). When external clients (sync-service, CI jobs) call the `/build/` API, OBS tries to redirect/proxy to this hostname which is unresolvable outside the container.

**Impact**: sync-service's `list_build_binaries()` and `download_rpm()` fail with 400 errors. `sync-all` returns "No binaries found" for all packages.

**Fix options**:
1. **Sync from sub-projects instead of integration project**: Modify `sync-all` to use `/source/{project}` API to get package list, then sync each package from its sub-project (`home:Admin:pkgname`) where the `/build/` API works correctly.
2. **Use `/published/` API**: Access published RPMs via `GET /published/{project}/{repo}/{arch}/{filename}` which may bypass the hostname issue.
3. **Fix OBS hostname**: Set `OBS_API_HOSTNAME` or equivalent Rails config to use `localhost`.

**Recommended**: Option 1 (sync from sub-projects) is the most reliable and doesn't require OBS container changes.

**Primary fix (verified 2026-05-15)**: Adding `127.0.0.1 $(hostname)` to OBS container's `/etc/hosts` and restarting Rails API resolves the hostname issue completely. This makes `/build/` and `/published/` API endpoints work for ALL projects (both integration and sub-projects). For persistence, add this line to `/start-obs.sh` inside the container. See `obs-build-service` skill pitfall #34 for details.

### 22. sync-service Docker Image Missing createrepo_c

**Symptom**: `update-repo` endpoint returns success but logs show `WARNING - createrepo_c not found, skipping metadata update`. RPMs are synced but `dnf` can't see them because repodata is stale.

**Root cause**: The sync-service Dockerfile uses `python:3.11-slim` (Debian) base image which doesn't have `createrepo_c` in its apt repos. `apt-get install createrepo_c` fails with "Unable to locate package".

**Fix**: Use a **Fedora base image** which includes `createrepo_c` via dnf:
```dockerfile
FROM fedora:41
RUN dnf install -y python3 python3-pip createrepo_c curl && dnf clean all
WORKDIR /app
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8090
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8090"]
```
Then rebuild and restart: `docker build -t sync-service:latest . && docker stop sync-service && docker rm sync-service && docker run ...`

**Pitfall**: The Fedora image is larger than python:3.11-slim (~400MB vs ~150MB) but necessary for createrepo_c. Build time is also longer due to dnf metadata download.

### 23. sync-service REPO_BASE_PATH Must Match Container Mount Point

**Symptom**: sync-service reports success but RPMs don't appear in the expected host directory

**Root cause**: `REPO_BASE_PATH` env var points to a path inside the container (e.g., `/var/ftp/intewell/rpms`) that doesn't match the Docker volume mount. The files are written inside the container but not visible on the host.

**Fix**: Ensure `REPO_BASE_PATH` matches the mount destination:
```bash
# If mounting: -v /home/nando/AICICD/data/repos:/data/repos
# Then set:    -e REPO_BASE_PATH=/data/repos
# NOT:         -e REPO_BASE_PATH=/home/nando/AICICD/data/repos  (host path, not visible in container)
```

### 24. sync-all Now Auto-Merges RPMs to Integration Repo + createrepo_c

**Symptom**: After `sync-all`, RPMs appear in `home_Admin_hello-world/x86_64/` and `home_Admin_demo-app/x86_64/` (per-package directories) AND in the integration project repo `home_Admin/standard/x86_64/`. repodata is automatically updated.

**How it works**: The `sync-all` endpoint now:
1. Downloads RPMs from each sub-project to per-package directories
2. Merges all RPMs into the integration project repo (`home_Admin/standard/<arch>/`)
3. Runs `createrepo_c` on the integration repo (if createrepo_c is available in container)

**If createrepo_c is not available**: The merge step still works, but repodata won't be updated. Run createrepo_c on the host manually:
```bash
createrepo_c /home/nando/AICICD/data/repos/home_Admin/standard/x86_64
createrepo_c /home/nando/AICICD/data/repos/home_Admin/standard/aarch64
```

**Legacy approach** (before auto-merge was implemented):
```bash
INTEGRATION_REPO=/home/nando/AICICD/data/repos/home_Admin/standard
for pkg_dir in /home/nando/AICICD/data/repos/home_Admin_*; do
  cp ${pkg_dir}/x86_64/*.rpm ${INTEGRATION_REPO}/x86_64/ 2>/dev/null
  cp ${pkg_dir}/aarch64/*.rpm ${INTEGRATION_REPO}/aarch64/ 2>/dev/null
done
createrepo_c ${INTEGRATION_REPO}/x86_64
createrepo_c ${INTEGRATION_REPO}/aarch64
```

### 28. CI/CD Full Flow: 6 CI Steps + ISO Trigger (铁律)

**User correction (铁律)**: The complete CI/CD flow is:

```
push → build → obs-trigger → obs-wait → sync → quality-gate → update-repo → [ISO构建]
  阶段1        阶段2              阶段3                    阶段4
```

- **CI Pipeline: 6 stages ending at update-repo** — this is what goes in `.gitlab-ci.yml`
- **ISO build: triggered by webhook-server after Pipeline success** — only when `intewell.yaml` has `target: iso`
- **After a developer pushes code with target=iso, the system MUST automatically generate an ISO. No manual triggers.**
- **ISO build is executed by Packer standalone script, NOT as a CI Pipeline stage**
- This rule is in AGENTS.md 铁律 section and must be followed in all CI template designs.
**How ISO trigger works**: webhook-server monitors Pipeline status after triggering it. When Pipeline succeeds and `build_target=iso`, webhook-server calls `trigger_iso_build()` which runs `integrated-build.sh` on the host.

**Do NOT add iso-build as a CI Pipeline stage** — it requires Docker socket access, host filesystem mounts, and long build times that are incompatible with CI Runner containers.

### 42. Always Read Existing Architecture Docs Before Proposing Solutions (铁律)

**Rule**: The project has detailed architecture docs in `/home/nando/AICICD/docs/architecture/` and debug records in `/home/nando/AICICD/docs/debug/`. Before proposing a new solution or workflow, READ the existing docs first. The user has already designed many solutions (e.g., webhook integration, dual-track CI/CD) and expects you to build on them, not reinvent them.

**User corrections** (multiple sessions):
- "我们之前设计架构你阅读一下呢" — read existing architecture docs instead of proposing new solutions from scratch
- "你阅读下有关的文档记录呢？又成功全流程调试的记录吗？不要自己再次探索了" — read existing debug/session records for proven workflows before re-exploring

**Mandatory checklist before ANY CI/CD task**:
1. Read `docs/architecture/` for existing designs
2. Read `docs/debug/` for previously solved problems and verified workflows
3. Check `session_search` for past sessions that successfully completed similar tasks
4. Check `01-source-trigger/`, `03-sync-quality-gate/`, `packer-integration/` for existing services
5. Check `docker ps` for running services
6. Check GitLab project webhooks: `curl -s --header "PRIVATE-TOKEN: $TOKEN" "http://localhost:8080/api/v4/projects/$ID/hooks"`

### 43. Automation Iron Law — Manual Steps Must Become Scripts (铁律)

**User correction (2026-05-18)**: "有需要手动的问题，就应该设置为自动化脚本，保证全链路自动化流程。不允许手动介入！"

**Rule**: When you encounter ANY manual step during debugging or operation, immediately create an automation script. The project铁律 is: **full automation from push to ISO, no manual intervention allowed**.

**Actions required when finding manual steps**:
1. Create automation script in `/home/nando/AICICD/scripts/`
2. Document the problem and solution in `docs/debug/`
3. Update existing automation scripts if the fix affects them

**Example scripts created** (2026-05-18):
- `scripts/add-test-package.sh` — One-click add test package + trigger full-chain build
- `scripts/full-chain-test.sh` — Full-chain automated test (env check + code creation + Pipeline monitoring + ISO verification)
- `scripts/check-and-fix-obs.sh` — OBS service health check and auto-repair
- `scripts/setup-gitlab-webhook.sh` — GitLab webhook auto-configuration

**Key signal**: If you find yourself manually running `docker restart`, `curl -X POST`, or any command more than once, that's a signal to create a script.

**See**: `references/automation-iron-law.md` for detailed pitfalls and fixes including:
- GitLab webhook PostgreSQL configuration
- Docker API version compatibility
- Webhook server branch name handling bug
- OBS service health check pattern
- Real-time debug documentation

### 44. webhook-server Environment Variables Required

**Symptom**: webhook-server returns 404 "Project Not Found" when calling GitLab API, or detects wrong package name

**Root cause**: webhook-server container missing required environment variables, especially `GITLAB_TOKEN`

**Required environment variables**:
```bash
docker run -d --name webhook-server \
  --network host \
  -e GITLAB_URL=http://localhost:8080 \
  -e GITLAB_TOKEN=glpat-xxxxx \
  -e OBS_API_URL=http://localhost:4455 \
  -e OBS_USER=Admin \
  -e OBS_PASSWORD=admin123 \
  -e DOCKER_API_VERSION=1.39 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  webhook-server:latest
```

**Diagnosis**: Check if GITLAB_TOKEN is set:
```bash
docker exec webhook-server python3 -c "import os; print('GITLAB_TOKEN:', os.getenv('GITLAB_TOKEN', 'EMPTY'))"
```

If empty, the GitLab API calls will fail with 404 or return wrong data.

### 45. webhook-server Should NOT Trigger Pipeline — Only Monitor

**Symptom**: Each push creates 2-3 duplicate Pipelines (source=push and source=api)

**Root cause**: webhook-server's `onboard_and_build()` function calls `trigger_pipeline()` which creates a new Pipeline via API, while GitLab's push event also automatically triggers a Pipeline

**Fix**: webhook-server should only monitor the Pipeline that GitLab automatically creates, not trigger a new one:
```python
# In onboard_and_build(), replace:
pipeline_id = trigger_pipeline(project_id, ref)

# With:
pipeline_id = get_latest_pipeline_id(project_id, ref)
```

Where `get_latest_pipeline_id()` waits for GitLab to create the Pipeline (usually within a few seconds after push):
```python
def get_latest_pipeline_id(project_id: int, ref: str = None) -> Optional[int]:
    """Get the latest Pipeline ID (don't trigger new Pipeline)"""
    if ref is None:
        ref = get_default_branch(project_id)
    # Wait for Pipeline to be created (GitLab push event takes a few seconds)
    import time
    for _ in range(10):
        result = gitlab_api("get", f"/projects/{project_id}/pipelines?ref={ref}&per_page=1")
        if result and len(result) > 0:
            return result[0]["id"]
        time.sleep(1)
    return None
```

**Result**: Only 1 Pipeline per push (source=push), webhook-server monitors it and triggers ISO build on success.

### 46. GitLab Runner pull_policy Must Be if-not-present

**Symptom**: CI build job takes 400+ seconds, stuck on "Pulling docker image"

**Root cause**: GitLab Runner default `pull_policy = "always"` tries to pull images from registry even when they exist locally

**Fix**: Configure Runner to use local images when available:
```bash
# Add to runner config.toml
docker exec gitlab-runner bash -c 'cat >> /etc/gitlab-runner/config.toml << EOF
    pull_policy = ["if-not-present"]
EOF'
docker restart gitlab-runner
```

**Result**: Build job completes in ~5 seconds when image is cached locally.

### 47. Duplicate GitLab Webhooks Create Duplicate Pipelines

**Symptom**: Each push triggers multiple Pipelines (3-4)

**Root cause**: `setup-gitlab-webhook.sh` script creates a new webhook every time without checking if one already exists

**Fix**: Check for existing webhook before creating:
```bash
# Check if webhook already exists
EXISTING=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/hooks" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | \
  python3 -c "import sys,json; hooks=json.load(sys.stdin); print(any(h['url']=='$WEBHOOK_URL' for h in hooks))")

if [ "$EXISTING" = "True" ]; then
  echo "Webhook already exists, skipping creation"
else
  curl -X POST "$GITLAB_URL/api/v4/projects/$PROJECT_ID/hooks" ...
fi
```

**See**: `scripts/setup-gitlab-webhook.sh` for complete implementation.

**Key**: If a past session or debug doc already contains the solution, USE IT directly. Do not re-derive or re-explore. The project has extensive records of what works and what doesn't — leverage them.

### 48. ISO Build Script Must Run on Host, Not in Container (铁律)

**Symptom**: ISO build fails with `build.sh: No such file or directory` when `build_in_docker.sh` runs inside webhook-server container

**Root cause**: `build_in_docker.sh` creates its own specialized Docker container for ISO building. It expects to find `build.sh` and other scripts in its working directory. When run inside another container (webhook-server), the paths don't match and dependencies are missing.

**铁律**: `build_in_docker.sh` MUST be executed on the host machine, NOT inside any container!

**Fix**: webhook-server triggers ISO build by creating a temporary container that runs on the host via docker.sock:
```python
def trigger_iso_build(package_name: str, iso_configs: list) -> dict:
    PACKER_DIR = os.getenv("PACKER_DIR", "/home/nando/Intewell-unified-packer")
    for config in iso_configs:
        container_name = f"iso-trigger-{package_name}-{config.replace('.json','')}"
        # Run on host via docker.sock - creates a container that executes build_in_docker.sh
        cmd = f"docker run -d --name {container_name} --rm -v {PACKER_DIR}:/packer -v /var/run/docker.sock:/var/run/docker.sock -w /packer alpine:latest sh -c 'apk add bash && bash build_in_docker.sh {config}'"
        subprocess.Popen(cmd, shell=True)
```

**Key**: The temporary container runs ON THE HOST (via docker.sock), not nested inside webhook-server. It mounts the Packer directory and has access to docker.sock to create the actual ISO build container.

### 49. OBS Rails API Requires /app Symlink

**Symptom**: OBS Rails API (port 4455) returns 500 with `MissingTemplate: Missing partial models/_project`

**Root cause**: Rails searches `/app/views/` but OBS installs views at `/srv/www/obs/api/app/views/`

**Fix**: Create symlink in OBS container:
```bash
docker exec obs-server-test ln -s /srv/www/obs/api/app /app
```

Add to `/start-obs.sh` for persistence, then `docker commit`.

### 50. GitLab Webhook URL Must Use IP Address, Not localhost (Critical)

**Symptom**: Webhook created with `localhost` URL but events list empty after push, webhook-server never receives events

**Root cause**: GitLab's webhook trigger mechanism doesn't work with `localhost` URLs even with `allow_local_requests=true`

**Fix**: Use actual IP address:
```bash
IP=$(hostname -I | awk '{print $1}')
curl -X POST "http://localhost:8080/api/v4/projects/$ID/hooks" \
  --form "url=http://${IP}:8091/gitlab/push" --form "push_events=true"
```

**Verified**: Pipeline #167 full chain success after changing webhook URL from localhost to 192.168.137.103.

### 51. ISO Build Script Path Must Be /packer/_internal/build_in_docker.sh

**Symptom**: ISO build fails with `build.sh: No such file or directory` when triggered by webhook-server

**Root cause**: webhook-server was calling `build_in_docker.sh` from `/packer/` root, but the script is at `/packer/_internal/build_in_docker.sh`. The `build_in_docker.sh` script expects to find `build.sh` in its working directory.

**Fix**: Update webhook-server `trigger_iso_build()` to use correct path and working directory:
```python
# WRONG - script not found
build_script = os.path.join(PACKER_DIR, "build_in_docker.sh")
cmd = f"docker run ... -w /packer ... bash build_in_docker.sh {config}"

# CORRECT - script in _internal directory
build_script = os.path.join(PACKER_DIR, "_internal", "build_in_docker.sh")
cmd = f"docker run ... -w /packer/_internal ... bash build_in_docker.sh {config}"
```

**Key**: The working directory (`-w`) must match where `build_in_docker.sh` and `build.sh` are located (`/packer/_internal/`).

**See**: `references/iso-build-integration.md` for complete ISO build flow, permission issues, and verification steps.

### 52. ISO Build Container Missing genisoimage — Must Use External Repo

**Symptom**: ISO build fails with `genisoimage: command not found` during `pack.sh` execution

**Root cause**: 
1. `rootfs_openeuler` container's default repo points to internal FTP server (e.g., `192.168.11.33`) which is unreachable
2. Container doesn't have `genisoimage` pre-installed
3. `build.sh` tries to install it via `dnf -y install genisoimage` but fails due to unreachable repo

**Fix**: Delete default repo files and use accessible mirror (e.g., Aliyun) before installing genisoimage:
```python
# In webhook-server trigger_iso_build()
packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"
repo_content = "[OS]\\nname=OS\\nbaseurl=https://mirrors.aliyun.com/openeuler/openEuler-24.03-LTS-SP1/OS/aarch64/\\nenabled=1\\ngpgcheck=0"

cmd = f"docker run -d --name {container_name} --privileged --network host --platform {platform} " \
      f"-v {packer_internal_path}:/userdefos -w /userdefos {docker_image} /bin/bash -c " \
      f"'rm -f /etc/yum.repos.d/*.repo && echo -e \"{repo_content}\" > /etc/yum.repos.d/openeuler.repo " \
      f"&& dnf -y install genisoimage && bash build.sh {config} 2>&1 | tee {log_file}'"
```

**Key points**:
1. `rm -f /etc/yum.repos.d/*.repo` — Remove default repos pointing to unreachable internal servers
2. Use accessible public mirror (Aliyun, TUNA, etc.) for the architecture matching the config
3. `-w /userdefos` — Set working directory so `build.sh` is found
4. Install genisoimage BEFORE running build.sh

**Verified**: test100 full-chain automation succeeded with webhook-server v3.4 (2026-05-18)

### 53. Docker-in-Docker Volume Mount Path Mismatch

**Symptom**: ISO build container can't find files that exist in webhook-server container's mounted volume

**Root cause**: When webhook-server container has `/packer` mounted from host's `/home/nando/Intewell-unified-packer`, and it starts a new container with `-v /packer/_internal:/userdefos`, the new container receives an EMPTY directory because `/packer` only exists inside webhook-server's namespace, not on the host.

**Fix**: Always use the HOST's actual path for volume mounts when starting containers from within another container:
```python
# WRONG - /packer only exists in webhook-server container's namespace
cmd = f"docker run ... -v /packer/_internal:/userdefos ..."

# CORRECT - use host's actual path
packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"  # Host path
cmd = f"docker run ... -v {packer_internal_path}:/userdefos ..."
```

**Key**: Docker socket (`/var/run/docker.sock`) allows creating sibling containers on the host. Volume mount paths are resolved on the HOST, not in the calling container.

### 54. CI Variable Setting Needs Logging for Verification

**Symptom**: CI variables (PACKAGE_NAME, PACKAGE_DIR) appear to not update after webhook-server processes a push event, but no error is logged

**Root cause**: `set_gitlab_ci_variables()` function in webhook-server has no logging output on success, making it impossible to verify if variables were actually set

**Fix**: Add logging to the function:
```python
def set_gitlab_ci_variables(project_id: int, package_name: str, package_dir: str) -> bool:
    """设置 GitLab CI/CD 变量"""
    logger.info(f"设置CI变量: PACKAGE_NAME={package_name}, PACKAGE_DIR={package_dir}")
    success = True
    for key, value in [("PACKAGE_NAME", package_name), ("PACKAGE_DIR", package_dir)]:
        # 先删除旧变量
        requests.delete(
            f"{GITLAB_URL}/api/v4/projects/{project_id}/variables/{key}",
            headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
            timeout=10
        )
        # 创建新变量
        result = gitlab_api("post", f"/projects/{project_id}/variables", {
            "key": key,
            "value": value
        })
        if not result:
            success = False
            logger.error(f"Failed to set CI variable {key}={value}")
        else:
            logger.info(f"CI变量 {key}={value} 设置成功")
    return success
```

**Verification**: After webhook processing, check logs for:
```
设置CI变量: PACKAGE_NAME=test100, PACKAGE_DIR=test100
CI变量 PACKAGE_NAME=test100 设置成功
CI变量 PACKAGE_DIR=test100 设置成功
```

**Manual verification**:
```bash
curl -s "http://localhost:8080/api/v4/projects/1/variables/PACKAGE_NAME" \
  --header "PRIVATE-TOKEN: $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('value'))"
```

### 55. CI Template Must Read package.name from intewell.yaml Dynamically

**Symptom**: Pipeline uses wrong PACKAGE_NAME (previous package's name) even though intewell.yaml has correct package.name

**Root cause**: Timing issue — GitLab push triggers Pipeline immediately, but webhook-server's CI variable update happens AFTER Pipeline has already started. The Pipeline uses stale CI variables.

**User correction (2026-05-19)**: "为什么每次都要你手动触发webhook？我们的目的是自动化运维，不出问题。你应该解决这个CI的问题，并且固化为脚本。"

**Fix**: CI template should read package.name directly from intewell.yaml at runtime, NOT rely on CI variables:

```yaml
build:
  stage: build
  script:
    - |
      # 从 intewell.yaml 动态读取 package.name 和 package.version
      if [ -f "intewell.yaml" ]; then
        PACKAGE_NAME=$(grep -A2 "package:" intewell.yaml | grep "name:" | head -1 | sed 's/.*name: *//')
        PACKAGE_VERSION=$(grep -A2 "package:" intewell.yaml | grep "version:" | head -1 | sed 's/.*version: *//' || echo "1.0.0")
        PACKAGE_DIR="${PACKAGE_NAME}"
        echo "从 intewell.yaml 读取: PACKAGE_NAME=${PACKAGE_NAME}, PACKAGE_VERSION=${PACKAGE_VERSION}"
      else
        PACKAGE_NAME="${CI_PROJECT_NAME}"
        PACKAGE_VERSION="1.0.0"
        PACKAGE_DIR="${CI_PROJECT_NAME}"
      fi
      # 导出到后续 job
      echo "PACKAGE_NAME=${PACKAGE_NAME}" >> build.env
      echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> build.env
      echo "PACKAGE_DIR=${PACKAGE_DIR}" >> build.env
  artifacts:
    paths:
      - "*.tar.gz"
      - "build.env"
```

**Key points**:
1. CI template reads intewell.yaml at build job runtime — no timing issue
2. Exports variables via `build.env` artifact for downstream jobs
3. Downstream jobs use `source build.env` to get correct values
4. CI variables (PACKAGE_NAME, PACKAGE_DIR) are now OBSOLETE — not needed

**Result**: test105 Pipeline correctly used PACKAGE_NAME=test105 without manual webhook trigger.

### 56. webhook-server Must Read intewell.yaml from Commit SHA, Not Branch

**Symptom**: webhook-server reads wrong intewell.yaml (previous commit's content) when processing push event

**Root cause**: webhook-server uses `ref=main` to read intewell.yaml, but the push event's commit may not be the latest on main branch yet. Also, there's a race condition between GitLab updating the branch and webhook-server reading it.

**Fix**: Use the push event's `after` (commit SHA) to read intewell.yaml:

```python
# In detect_packages_from_push() and handle_push_event()
commit_sha = event.after  # push 事件中的最新 commit
resp = requests.get(
    f"{GITLAB_URL}/api/v4/projects/{project_id}/repository/files/intewell.yaml/raw?ref={commit_sha}",
    headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
    timeout=10
)
```

**Key**: The commit SHA is guaranteed to have the correct intewell.yaml content that was just pushed.

### 57. GitLab Webhook Returns "internal error" — Use Fallback Script

**Symptom**: GitLab webhook events show `status: internal error`, webhook-server never receives push events, OBS projects not created

**Root cause**: GitLab's internal webhook mechanism may fail for various reasons (network, configuration, timing). This is a GitLab issue, not webhook-server issue.

**Fix**: Create automation script as fallback:

```bash
#!/bin/bash
# scripts/trigger-webhook.sh — Auto trigger webhook when GitLab fails

WEBHOOK_URL="http://192.168.137.103:8091/gitlab/push"
PROJECT_ID=1

# Get latest commit SHA
SHA=$(curl -s "http://localhost:8080/api/v4/projects/$PROJECT_ID/repository/commits?per_page=1" \
  --header "PRIVATE-TOKEN: $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"object_kind\":\"push\",\"after\":\"$SHA\",\"ref\":\"refs/heads/main\",...}"
```

**User expectation**: Full automation from push to ISO. Manual intervention is NOT allowed (铁律).

### 58. GitLab Project Structure — Packages Are Subdirectories, Not Separate Projects

**Symptom**: User expects `test1`, `test2`, etc. to be directories under `intewell-test` project, but they appear as separate GitLab projects

**Root cause**: Misunderstanding of project structure. The Intewell CI/CD design uses a **single GitLab project** (`intewell-test`) with **multiple package subdirectories** (`test1/`, `test2/`, `test100/`), not separate projects for each package.

### 59. webhook-server Must NOT Upload CI Template — Causes Duplicate Pipelines

**Symptom**: Each push creates 2 Pipelines (one from push, one from CI template update)

**Root cause**: webhook-server's `onboard_and_build()` calls `upload_ci_template()` which updates `.gitlab-ci.yml` via GitLab API. This creates a new commit which triggers another Pipeline.

**User correction (2026-05-19)**: "为什么创建了200和201两个pipline" — user noticed duplicate Pipelines

**Fix**: Skip CI template upload since the template is already in the repository and reads `package.name` dynamically from `intewell.yaml`:

```python
# In onboard_and_build()
# 3. 不再上传 CI 模板 - CI模板已在仓库中，从intewell.yaml动态读取package.name
# result.ci_template_uploaded = upload_ci_template(project_id, build_target, ref)
result.ci_template_uploaded = True  # 跳过CI模板上传
```

**Key**: The CI template in the repository reads `package.name` from `intewell.yaml` at runtime, so there's no need to update it per-package. This eliminates the duplicate Pipeline issue.

### 60. Systematic Debugging Pattern — Analyze → Fix → Verify with New Test (铁律)

**User correction (2026-05-19)**: "有问题就分析问题，然后修改脚本，然后新建test进行自动流程的测试，再新的流程验证问题是否修改成功？不要手动触发CI模板更新"

**铁律**: When encountering CI/CD issues, follow this systematic pattern:

1. **Analyze the root cause** — Check logs, understand the timing/sequence
2. **Fix the code/script** — Modify the actual source, not a workaround
3. **Create new test package** — Use a new test (e.g., test106, test107) to verify the fix
4. **Verify automatically** — Let the automation run, don't manually trigger anything

**Anti-patterns to avoid** (禁止):
- **Manually triggering webhooks** to "fix" issues — this is strictly forbidden
- **Manually updating CI templates** — the template should be in the repo, read dynamically
- **Manually creating OBS projects** — webhook-server should do this automatically
- **Solving one problem while creating another** — verify the complete flow, not just one step

**User expectation**: "不要CI模板的问题没解决，你的修改又造成新的问题" — fixes must not introduce new issues.

### 61. GitLab Webhook "internal error" — Container Network Isolation (SOLVED)

**Symptom**: GitLab webhook events show `status: internal error`, webhook-server never receives push events. GitLab logs show:
```
"exception.class":"Errno::EHOSTUNREACH"
"exception.message":"Failed to open TCP connection to 192.168.137.103:8091 (No route to host)"
```

**Root cause**: GitLab container has internal firewall that blocks connections to other containers and host IP addresses, even when on the same Docker network.

**Attempted fixes that DON'T work**:
- Using `host.docker.internal` — only works on Docker Desktop (Mac/Windows), not Linux
- Using Docker network gateway IP (e.g., `172.28.0.1`) — still blocked
- Adding webhook-server to same network as GitLab — GitLab still can't reach it

**Solution (VERIFIED 2026-05-19)**: Bypass GitLab webhook mechanism entirely. Instead:
1. **GitLab Runner** uses `host` network mode
2. **webhook-server** uses `host` network mode
3. **CI template** calls webhook-server from build job (Runner has host network access)

```yaml
build:
  stage: build
  script:
    - |
      # 触发 webhook-server 创建 OBS 项目
      apk add --no-cache curl
      WEBHOOK_URL="http://192.168.137.103:8091/gitlab/push"
      curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{
          \"object_kind\": \"push\",
          \"before\": \"abc123\",
          \"after\": \"${CI_COMMIT_SHA}\",
          \"ref\": \"refs/heads/main\",
          \"user_name\": \"ci-bot\",
          \"project\": {\"id\": ${CI_PROJECT_ID}, \"name\": \"${CI_PROJECT_NAME}\"},
          \"repository\": {\"name\": \"${CI_PROJECT_NAME}\"},
          \"commits\": [{\"id\": \"${CI_COMMIT_SHA}\", \"message\": \"CI trigger\"}]
        }"
```

**Key points**:
- webhook payload MUST include `before`, `user_name`, `commits` fields (pydantic validation)
- GitLab Runner with `network_mode: host` can access any host service via localhost/IP
- User can now just `git push` — full automation works

**Verified**: test126 Pipeline #230 success, OBS x86_64 + aarch64 published (2026-05-19)

**Alternative (for OBS setup only)**: CI template auto-creates OBS project and package:

```yaml
obs-trigger:
  script:
    - |
      # Check if OBS project exists, create if not
      obs_check=$(curl -s -u "${OBS_USER}:${OBS_PASSWORD}" "${OBS_API}/source/${OBS_PROJECT}/_meta" 2>&1)
      if echo "$obs_check" | grep -q "does not exist\|unknown_project\|404"; then
        curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -X PUT "${OBS_API}/source/${OBS_PROJECT}/_meta" \
          -H "Content-Type: text/xml" \
          -d "<project name='${OBS_PROJECT}'>...</project>"
      fi
    - |
      # Check if OBS package exists, create if not
      pkg_check=$(curl -s -u "${OBS_USER}:${OBS_PASSWORD}" "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/_meta" 2>&1)
      if echo "$pkg_check" | grep -q "does not exist\|unknown_package\|404"; then
        curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -X PUT "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/_meta" \
          -H "Content-Type: text/xml" \
          -d "<package name='${PACKAGE_NAME}' project='${OBS_PROJECT}'>...</package>"
      fi
```

**Fallback script**: `scripts/intewell-push.sh` wraps git push + manual webhook trigger for cases where GitLab webhook fails.

### 62. OBS Project Must Include Repository Config for Builds

**Symptom**: OBS project created successfully, but builds never start. OBS API returns empty `<resultlist/>` for build status. Package shows `code="scheduled"` indefinitely.

**Root cause**: OBS project _meta XML must include `<repository>` element with `<path>` to DoD (Download on Demand) and `<arch>` for each architecture. Without this, OBS has no build environment.

**Fix**: When creating OBS project via API, include complete repository config:

```xml
<project name='home:Admin:pkgname'>
  <title>pkgname package build</title>
  <description>pkgname package build for Intewell CI/CD</description>
  <person userid='Admin' role='maintainer'/>
  <repository name='standard'>
    <path project='home:Admin:openEuler24.03-SP1' repository='standard'/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>
```

**Key elements**:
- `<repository name='standard'>` — repository name (must match DoD config)
- `<path project='...' repository='...'>` — points to DoD project with base packages
- `<arch>` — one element per architecture (x86_64, aarch64)

**Pitfall**: Creating project with only `<title>` and `<description>` succeeds but builds won't run.

### 63. OBS Package Must Be Created Before Uploading Files

**Symptom**: `curl -T file.tar.gz` to OBS API returns 404 with `package 'pkgname' does not exist`, even though project exists.

**Root cause**: OBS requires both project _meta AND package _meta to be set before files can be uploaded. Creating a project does NOT automatically create packages.

**Fix**: Create package _meta before uploading files:

```bash
# Create package _meta
curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -X PUT \
  "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/_meta" \
  -H "Content-Type: text/xml" \
  -d "<package name='${PACKAGE_NAME}' project='${OBS_PROJECT}'><title>${PACKAGE_NAME}</title><description>${PACKAGE_NAME} package</description></package>"

# Then upload files
curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -T "${PACKAGE_NAME}.tar.gz" \
  "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/${PACKAGE_NAME}.tar.gz"
```

**Sequence**: Project _meta → Package _meta → Upload files → Build triggers automatically

### 64. OBS Project `kind` Attribute Must Be Empty

**Symptom**: Creating OBS project returns 400 with `projkind 'package' is illegal`

**Root cause**: OBS project _meta XML must NOT have `kind='package'` attribute. The `kind` attribute is reserved for special project types.

**Wrong**:
```xml
<project name='home:Admin:pkgname' kind='package'>
```

**Correct**:
```xml
<project name='home:Admin:pkgname'>
```

**Note**: Packages have their own _meta with `<package>` root element. Projects use `<project>` without `kind` attribute.

### 65. OBS Build Wait Timeout — First Build Takes Longer

**Symptom**: `obs-wait` job times out (600s) with `all_done=false` even though OBS is building

**Root cause**: First-time OBS builds need to download base images and dependencies, taking 10-20 minutes. Default 600s timeout is insufficient.

**Fix**: Increase timeout in CI template:

```yaml
obs-wait:
  script:
    - elapsed=0
    - while [ $elapsed -lt 1200 ]; do  # 20 minutes
        status=$(curl -s "${SYNC_SERVICE}/obs-build-status/${OBS_PROJECT}/${PACKAGE_NAME}")
        all_done=$(echo "$status" | jq -r '.all_done')
        if [ "$all_done" = "true" ]; then
          exit 0
        fi
        sleep 30
        elapsed=$((elapsed + 30))
      done
    - echo "ERROR: OBS build timed out"
    - exit 1
```

**Note**: Subsequent builds are faster due to caching. Consider 1200s (20 min) for safety.

**Automation script for git push + webhook trigger**:
```bash
#!/bin/bash
# scripts/intewell-push.sh — git push + auto webhook trigger
# Solves GitLab webhook "internal error" issue

git add .
git commit -m "$1"
git push origin main

SHA=$(git rev-parse HEAD)
curl -s -X POST "http://192.168.137.103:8091/gitlab/push" \
  -H "Content-Type: application/json" \
  -d "{\"object_kind\":\"push\",\"after\":\"$SHA\",\"ref\":\"refs/heads/main\",...}"
```

**Example workflow**:
```bash
# 1. Analyze - check logs
docker logs webhook-server 2>&1 | grep test105

# 2. Fix - modify the actual code
# Edit app.py to fix the issue

# 3. Rebuild and deploy
docker build -t webhook-server:v3.8 . && docker restart webhook-server

# 4. Create new test package
mkdir test107 && ... && git push

# 5. Verify - let automation run, check results
sleep 180 && curl -s "http://localhost:8080/api/v4/projects/1/pipelines?per_page=1"
```

**Correct structure**:
```
intewell-test (GitLab project ID=1)
├── intewell.yaml          # Build target config
├── .gitlab-ci.yml         # CI template
├── hello-world/           # Package directory
│   ├── hello-world.c
│   └── hello-world.spec
├── test1/                 # Package directory
│   ├── test1.c
│   └── test1.spec
├── test100/               # Package directory
│   ├── test100.c
│   └── test100.spec
```

**Key**: Each push to `intewell-test` triggers webhook-server which:
1. Reads `intewell.yaml` to get current package name
2. Creates OBS sub-project `home:Admin:<package_name>`
3. Sets CI variables for that package
4. Pipeline builds that specific package

**Do NOT create separate GitLab projects for each package** — they should all live in the same `intewell-test` repository as subdirectories.

- `templates/intewell-multi-package-ci.yml` — Universal CI/CD pipeline template for multi-package parallel builds. Uses `PACKAGE_NAME` (set as per-project CI/CD variable) to auto-map GitLab repo → OBS project. Supports x86_64 + aarch64 dual-arch. Stages: build → obs-trigger → obs-wait → sync → quality-gate → update-repo.

**Fix**: Use `fedora:41` as base image:
```dockerfile
FROM fedora:41
RUN dnf install -y python3 python3-pip createrepo_c curl && dnf clean all
```

The sync-service `sync-all` function now auto-merges RPMs from sub-projects into the integration project repo and runs `createrepo_c` on the merged directory.

### 28. CI/CD Full Flow: 6 CI Steps + ISO Trigger (铁律)

**User correction (铁律)**: The complete CI/CD flow is:

```
push → build → obs-trigger → obs-wait → sync → quality-gate → update-repo → [ISO构建]
  阶段1        阶段2              阶段3                    阶段4
```

- **CI Pipeline: 6 stages ending at update-repo** — this is what goes in `.gitlab-ci.yml`
- **ISO build: triggered by webhook-server after Pipeline success** — only when `intewell.yaml` has `target: iso`
- **After a developer pushes code with target=iso, the system MUST automatically generate an ISO. No manual triggers.**
- **ISO build is executed by Packer standalone script, NOT as a CI Pipeline stage**
- This rule is in AGENTS.md 铁律 section and must be followed in all CI template designs.

### 29. New Package Auto-Onboarding via Webhook Server (v2.0)

The webhook-server (`01-source-trigger/webhook-server/app.py`, port 8091) now handles **automatic new package onboarding** when a developer pushes code to GitLab. The flow:

```
Developer push → GitLab Webhook → webhook-server /gitlab/push
  → detect packages (scan repo for .spec directories)
  → create OBS sub-project (home:Admin:pkgname) with _meta + _config + _link
  → set GitLab CI/CD variables (PACKAGE_NAME, PACKAGE_DIR)
  → upload CI template (.gitlab-ci.yml)
  → enable Runner for project
  → trigger Pipeline
```

**Manual trigger endpoint** (for testing):
```bash
curl -X POST http://localhost:8091/manual/onboard \
  -H "Content-Type: application/json" \
  -d '{"project_id": 1, "package_name": "test1", "package_dir": "test1"}'
```

**GitLab Webhook setup**: Requires `allow_local_requests_from_hooks_and_services = true` in GitLab Admin → Settings → Network. See pitfall #30.

**Architecture doc**: `docs/architecture/webhook-integration-design.md`

### 30. OBS _meta XML Requires <description> Element

**Symptom**: Creating OBS sub-project via API returns 500 Internal Server Error

**Root cause**: OBS validates project _meta XML strictly. After `<title>`, a `<description>` element is mandatory. Without it, OBS returns a validation error that manifests as 500.

**Fix**: Always include `<description>` in _meta XML:
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

### 31. GitLab Webhook URL Must Use IP Address, Not localhost

**Symptom**: 
- GitLab webhook is created successfully with `url: http://localhost:8091/gitlab/push`
- `push_events: true` is enabled
- Webhook events list is empty `[]` after push
- webhook-server never receives push events
- CI variables don't update, OBS projects don't get created

**Root cause**: GitLab's internal webhook trigger mechanism does NOT work with `localhost` URLs, even when `allow_local_requests_from_hooks_and_services=true` is enabled. The webhook is created but never fired.

**Fix**: Use the host's actual IP address (e.g., `192.168.137.103`) instead of `localhost`:
```bash
# Via gitlab.rb (inside GitLab container)
docker exec gitlab bash -c 'echo "gitlab_rails[\"allow_local_requests_from_hooks_and_services\"] = true" >> /etc/gitlab/gitlab.rb'
docker exec gitlab gitlab-ctl reconfigure

# Or via API (may return 500 on some GitLab versions)
curl -s -X PUT "http://localhost:8080/api/v4/application/settings" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allow_local_requests_from_hooks_and_services": true}'
```

Then add webhook using the host IP (not localhost):
```bash
curl -X POST "http://localhost:8080/api/v4/projects/$ID/hooks" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url": "http://192.168.137.103:8091/gitlab/push", "push_events": true}'
```

### 32. OBS Rails API May Crash After Container Restart

**Symptom**: OBS API returns 500 for all requests after `docker restart obs-server-test`. Backend services (bs_sched, bs_repserver) are running but Rails API is down.

**Root cause**: OBS container's `/start-obs.sh` starts backend services but the Rails API process may not auto-start or may crash on restart.

**Fix**: Manually start Rails API:
```bash
docker exec -d obs-server-test bash -c 'cd /srv/www/obs/api && RAILS_ENV=production bundle exec rails server -p 4455 -b 0.0.0.0 -d'
```

**Also**: The hostname fix (`echo "127.0.0.1 $(hostname)" >> /etc/hosts`) must be in `/start-obs.sh` for persistence. See `obs-build-service` skill pitfall #34.

### 33. Dockerfile CMD Overrides Environment Variable PORT

**Symptom**: Service starts on port 8080 despite `PORT=8091` env var being set

**Root cause**: Dockerfile `CMD` explicitly specifies port (e.g., `CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]`), overriding the env var logic in `app.py`'s `__main__` block.

**Fix**: Use `CMD ["python", "app.py"]` in Dockerfile so the app reads PORT from environment:
```dockerfile
# WRONG — hardcodes port, ignores PORT env var
CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]

# CORRECT — app.py reads PORT env var
CMD ["python", "app.py"]
```

In `app.py`:
```python
if __name__ == "__main__":
    port = int(os.getenv("PORT", "8091"))
    uvicorn.run(app, host="0.0.0.0", port=port)
```

### 40. intewell.yaml Build Target Selection (铁律)

**铁律**: Developers place `intewell.yaml` in the repository root to select the build target:

```yaml
package:
  name: test1
  version: 1.0.0

build:
  target: iso          # iso | rpm-only
  arch:                # optional, defaults to dual-arch
    - x86_64
    - aarch64
```

- `target: iso` → CI 6 steps complete → webhook-server automatically triggers Packer ISO build (total 8 steps)
- `target: rpm-only` → CI 6 steps complete → stop (at update-repo)
- No intewell.yaml → defaults to rpm-only, package name auto-detected from repo directory
- **webhook-server reads intewell.yaml and decides whether to trigger ISO build after Pipeline success**
- **ISO build is executed by Packer standalone script, NOT as a CI Pipeline stage**
- CI template is the SAME for both targets (6 stages to update-repo). The difference is what happens AFTER the Pipeline.

**Implementation**: `ci_templates.py` provides `get_ci_template()` which returns the same 6-stage template for both targets. `app.py` function `check_pipeline_and_trigger_iso()` monitors Pipeline status and triggers `trigger_iso_build()` (which runs `integrated-build.sh`) when Pipeline succeeds and `build_target=iso`.
GitLab rejects `http://localhost:*` as a Webhook URL even with `allow_local_requests_from_hooks_and_services=true`. Use the host's LAN IP instead:

```bash
# Wrong
curl -X POST ... -d '{"url": "http://localhost:8091/gitlab/push"}'

# Correct
curl -X POST ... -d '{"url": "http://192.168.137.103:8091/gitlab/push"}'
```

Also must enable: `gitlab_rails['allow_local_requests_from_hooks_and_services'] = true` in `/etc/gitlab/gitlab.rb` + `gitlab-ctl reconfigure`.

### 36. OBS _meta XML Must Include <description> Element

OBS API returns 500 if project/package `_meta` XML is missing `<description>` after `<title>`:

```xml
<!-- Wrong - returns 500 -->
<project name="home:Admin:test1">
  <title>test1 package</title>
  <repository name="standard">

<!-- Correct -->
<project name="home:Admin:test1">
  <title>test1 package</title>
  <description>test1 package for Intewell CI/CD</description>
  <repository name="standard">
```

### 37. webhook-server Auto-Onboard Flow (v2.0)

When a developer pushes a new package directory to GitLab, webhook-server automatically:

1. Detects new packages (scans repo tree for directories containing .spec files)
2. Reads `intewell.yaml` from repo root for build target config
3. Creates OBS sub-project `home:Admin:<pkgname>` with _meta + _config
4. Sets GitLab CI/CD variables (PACKAGE_NAME, PACKAGE_DIR, BUILD_TARGET)
5. Uploads appropriate CI template (.gitlab-ci.yml) based on build target
6. Enables Runner for the project
7. Triggers Pipeline

If the package already exists (OBS sub-project present), skips steps 3-6 and just triggers the Pipeline.

### 38. CI YAML Script Blocks Must Use Pipe Syntax for Multi-line

GitLab CI lint rejects `script:` entries that mix string and array syntax. Use `|` block scalar for multi-line scripts:

```yaml
# Wrong - lint error "script should be a string or a nested array"
script:
  - apk add --no-cache curl jq
  - OBS_PROJECT="home:Admin:${PACKAGE_NAME}"
  - while [ ... ]; do

# Correct - use | block scalar
script:
  - apk add --no-cache curl jq
  - |
    OBS_PROJECT="home:Admin:${PACKAGE_NAME}"
    while [ ... ]; do
```

### 39. OBS Container Restart Auto-Recovery via docker commit

OBS container loses `/etc/hosts` hostname fix and backend services on restart. Fix by modifying `/start-obs.sh` inside the container, then `docker commit` to persist:

```bash
# 1. Modify start-obs.sh inside container (add hostname fix + all backend services)
docker cp /tmp/start-obs.sh obs-server-test:/start-obs.sh

# 2. Commit container as new image
docker commit obs-server-test obs-server:latest

# 3. Recreate with committed image
docker stop obs-server-test && docker rm obs-server-test
docker run -d --name obs-server-test --privileged --network host \
  -v /usr/bin/qemu-aarch64-static:/usr/bin/qemu-aarch64-static \
  -v /home/nando/AICICD/data/obs-srv/obs:/srv/obs \
  -v /home/nando/AICICD/data/obs:/var/obs \
  obs-server:latest
```

The committed image preserves CMD (`/start-obs.sh`), hostname fix, and all service startup logic. `docker restart` re-executes CMD, making OBS fully automated after restart.

### 40. intewell.yaml Build Target Selection (铁律)

**铁律**: Developers place `intewell.yaml` in the repository root to select the build target:

```yaml
package:
  name: test1
  version: 1.0.0

build:
  target: iso          # iso | rpm-only
  arch:                # optional, defaults to dual-arch
    - x86_64
    - aarch64
```

- `target: iso` → CI 6 steps complete → webhook-server automatically triggers Packer ISO build (total 8 steps)
- `target: rpm-only` → CI 6 steps complete → stop (at update-repo)
- No intewell.yaml → defaults to rpm-only, package name auto-detected from repo directory
- **webhook-server reads intewell.yaml and decides whether to trigger ISO build after Pipeline success**
- **ISO build is executed by Packer standalone script, NOT as a CI Pipeline stage**
- CI template is the SAME for both targets (6 stages to update-repo). The difference is what happens AFTER the Pipeline.

**Implementation**: `ci_templates.py` provides `get_ci_template()` which returns the same 6-stage template for both targets. `app.py` function `check_pipeline_and_trigger_iso()` monitors Pipeline status and triggers `trigger_iso_build()` (which runs `integrated-build.sh`) when Pipeline succeeds and `build_target=iso`.
**Pitfall**: When adding a new Python module (e.g., `ci_templates.py`) to a Docker service, you MUST add an explicit `COPY ci_templates.py .` line in the Dockerfile. `COPY . .` may use cached layers and skip the new file. Always rebuild with `--no-cache` after adding new files:
```bash
docker build --no-cache -t service:latest .
```

**Diagnosis**: If a container crashes with `ModuleNotFoundError` for a file that exists in the build context, check that the Dockerfile has an explicit COPY line and that the image was rebuilt without cache.

### 42. Always Read Existing Architecture Docs Before Proposing Solutions

**Rule**: The project has detailed architecture docs in `/home/nando/AICICD/docs/architecture/`. Before proposing a new solution or workflow, READ the existing docs first. The user has already designed many solutions (e.g., webhook integration, dual-track CI/CD) and expects you to build on them, not reinvent them.

**User correction**: "我们之前设计架构你阅读一下呢" — the user explicitly told me to read existing architecture docs instead of proposing new solutions from scratch.

- `templates/intewell-multi-package-ci.yml` — Universal CI/CD pipeline template for multi-package parallel builds. Uses `PACKAGE_NAME` (set as per-project CI/CD variable) to auto-map GitLab repo → OBS project. Supports x86_64 + aarch64 dual-arch. Stages: build → obs-trigger → obs-wait → sync → quality-gate → update-repo.

## Related Skills

- `obs-build-service` - OBS deployment and troubleshooting
- `webhook-subscriptions` - Event-driven pipeline triggers
- `feishu` - Feishu notification integration
- `gitlab-runner-docker` - GitLab Runner Docker executor deployment and troubleshooting
- `gitlab-ci-yaml-upload` - GitLab CI YAML upload via API with base64 encoding
- `intewell-packer` - Intewell OS ISO image build with OBS RPM integration