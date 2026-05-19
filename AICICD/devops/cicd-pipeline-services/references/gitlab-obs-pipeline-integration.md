# GitLab-OBS Pipeline Integration Session (2026-05-13)

## Session Goal
验证 GitLab push → OBS 构建 → 制品同步 → 质量门禁完整链路

## Environment
- Host: openEuler 2403, IP: 192.168.137.103
- GitLab: http://192.168.137.103:8080 (container)
- GitLab Runner: docker executor with `network_mode = "host"`
- OBS Server: http://localhost:4455 (container)
- Sync Service: http://localhost:8090 (container, host network)

## Key Issues Resolved

### 1. GitLab Runner Network Isolation
**Problem**: Job containers could not connect to OBS API (192.168.137.103:4455)
**Error**: `curl: (7) Failed to connect to 192.168.137.103 port 4455: Could not connect to server`
**Root cause**: Runner creates job containers with bridge network
**Solution**: Configure `network_mode = "host"` in runner config
```bash
docker exec gitlab-runner sh -c "sed -i '/volumes = \\[.*\\]/a\\    network_mode = \\\"host\\\"' /etc/gitlab-runner/config.toml"
docker restart gitlab-runner
```

### 2. host.docker.internal Not Available on Linux
**Problem**: `curl: (6) Could not resolve host: host.docker.internal`
**Root cause**: `host.docker.internal` only works on Docker Desktop (Mac/Windows)
**Solution**: Use `localhost` URLs with `network_mode = "host"`, or add `extra_hosts`:
```toml
[runners.docker]
  extra_hosts = ["host.docker.internal:host-gateway"]
```

### 3. Manual Stage Breaks Automation
**Problem**: Pipeline stopped at sync stage, required manual trigger
**User feedback**: "为什么流程中还要手动，我们应该都是自动流程"
**Solution**: Remove `when: manual` from `.gitlab-ci.yml`

## Final Working Configuration

### .gitlab-ci.yml (Simplified)
```yaml
stages:
  - build
  - obs-trigger
  - sync

variables:
  OBS_API_URL: http://localhost:4455
  OBS_USER: Admin
  OBS_PASSWORD: admin123
  OBS_PROJECT: home:Admin
  OBS_PACKAGE: hello-world
  SYNC_URL: http://localhost:8090

build:
  stage: build
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache tar
    - cd hello-world
    - tar -czvf ../hello-world-1.0.0.tar.gz src hello-world.spec Makefile
  artifacts:
    paths: [hello-world-1.0.0.tar.gz]

obs-trigger:
  stage: obs-trigger
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -X PUT -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/source/$OBS_PROJECT/$OBS_PACKAGE/hello-world-1.0.0.tar.gz" --data-binary @hello-world-1.0.0.tar.gz
    - curl -X PUT -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/source/$OBS_PROJECT/$OBS_PACKAGE/hello-world.spec" --data-binary @hello-world/hello-world.spec
  dependencies: [build]

sync:
  stage: sync
  tags: [test]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - 'curl -X POST $SYNC_URL/sync -H "Content-Type: application/json" -d "{\"project\": \"home:Admin\", \"package\": \"hello-world\", \"repository\": \"openEuler_24_03\", \"arch\": \"x86_64\"}"'
  dependencies: [obs-trigger]
```

### GitLab Runner config.toml
```toml
[[runners]]
  executor = "docker"
  [runners.docker]
    image = "python:3.11-slim"
    privileged = true
    volumes = ["/cache"]
    network_mode = "host"  # KEY: allows job containers to access host services
```

## Verification Results

Pipeline #19: **SUCCESS** ✅

| Stage | Status | Details |
|-------|--------|---------|
| build | success | hello-world-1.0.0.tar.gz created |
| obs-trigger | success | Source uploaded to OBS |
| OBS build | succeeded | hello-world-1.0.0-2.1.x86_64.rpm |
| sync | success | Synced to /var/ftp/intewell/rpms/ |

## Programmatic Pipeline Triggering

### Creating GitLab API Token via Rails Console
When you need to trigger pipelines via API (for verification or automation):

```bash
# Create token for user (requires expiration date)
docker exec gitlab gitlab-rails runner "
user = User.find(2)  # or User.find_by(username: 'renwd')
token = PersonalAccessToken.new(user: user, name: 'api-test-token', scopes: ['api'])
token.expires_at = 1.year.from_now
token.set_token('glpat-api-test-12345')
token.save!
puts \"Token: #{token.token}\"
"
```

**Note**: PersonalAccessToken validation requires `expires_at` - without it, you'll get "Expiration date can't be blank" error.

### Triggering Pipeline via API
```bash
# Trigger new pipeline
curl -X POST \
  --header "PRIVATE-TOKEN: glpat-api-test-12345" \
  "http://localhost:8080/api/v4/projects/1/pipeline?ref=main"

# Check pipeline status
curl --header "PRIVATE-TOKEN: glpat-api-test-12345" \
  "http://localhost:8080/api/v4/projects/1/pipelines/21"

# Check job status
curl --header "PRIVATE-TOKEN: glpat-api-test-12345" \
  "http://localhost:8080/api/v4/projects/1/pipelines/21/jobs"
```

### Querying Pipeline Status via Rails Console
```bash
docker exec gitlab gitlab-rails runner "
p = Project.find(1)
ci = p.ci_pipelines.last
puts \"Pipeline ##{ci.id}: #{ci.status}\"
ci.builds.each { |b| puts \"  #{b.name}: #{b.status}\" }
"
```

## Lessons Learned

1. **Always use `network_mode = "host"` for GitLab Runner** when job containers need to access host services
2. **Never use `when: manual`** in CI/CD pipelines unless explicitly required for approval gates
3. **Use `localhost` URLs** when containers share host network
4. **Test complete pipeline end-to-end** after any network configuration change
5. **PersonalAccessToken requires expiration date** - always set `expires_at` when creating tokens via Rails console
