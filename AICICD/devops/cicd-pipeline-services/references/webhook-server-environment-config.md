# webhook-server Environment Configuration Debugging

**Date**: 2026-05-18
**Context**: Intewell CI/CD project, webhook-server container

## Error Chain

### Error 1: GitLab API Returns 404 "Project Not Found"

**Symptom**:
```
2026-05-18 07:16:42,529 - app - ERROR - GitLab API get /projects/1/repository/tree?ref=main&recursive=true failed: 404 {"message":"404 Project Not Found"}
```

**Cause**: webhook-server container missing `GITLAB_TOKEN` environment variable

**Diagnosis**:
```bash
docker exec webhook-server python3 -c "import os; print('GITLAB_TOKEN:', os.getenv('GITLAB_TOKEN', 'EMPTY'))"
# Output: GITLAB_TOKEN: EMPTY
```

**Fix**: Add GITLAB_TOKEN to container startup:
```bash
docker stop webhook-server && docker rm webhook-server

docker run -d --name webhook-server \
  --network host \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /home/nando/Intewell-unified-packer:/packer \
  -e DOCKER_API_VERSION=1.39 \
  -e GITLAB_URL=http://localhost:8080 \
  -e GITLAB_TOKEN=glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8 \
  -e OBS_API_URL=http://localhost:4455 \
  -e OBS_USER=Admin \
  -e OBS_PASSWORD=admin123 \
  intewell-webhook-server:v2.3
```

### Error 2: Package Name Detected as "main" Instead of Actual Package

**Symptom**:
```
2026-05-18 07:16:42,529 - app - INFO - 检测到包: ['main']
```

**Cause**: Without GITLAB_TOKEN, webhook-server cannot read intewell.yaml or scan repo tree, falls back to using branch name as package name

**Fix**: Same as Error 1 — set GITLAB_TOKEN

**Verification**:
```bash
docker logs webhook-server --tail 20 | grep "检测到包"
# Expected: 检测到包: ['test17'] (actual package name)
```

### Error 3: Duplicate Pipelines (source=push and source=api)

**Symptom**:
```
Pipeline #149 source=push sha=25d3e4c3
Pipeline #150 source=push sha=f5272e47
```

Two Pipelines created within 3 seconds for the same commit.

**Cause**: webhook-server's `onboard_and_build()` calls `trigger_pipeline()` which creates a new Pipeline via API, while GitLab's push webhook also automatically triggers a Pipeline.

**Fix**: Modify webhook-server to NOT trigger Pipeline, only monitor:
```python
# In app.py, onboard_and_build() function, replace:
pipeline_id = trigger_pipeline(project_id, ref)

# With:
pipeline_id = get_latest_pipeline_id(project_id, ref)
```

Add `get_latest_pipeline_id()` function that waits for GitLab to create the Pipeline:
```python
def get_latest_pipeline_id(project_id: int, ref: str = None) -> Optional[int]:
    """获取最新的Pipeline ID（不触发新Pipeline）"""
    if ref is None:
        ref = get_default_branch(project_id)
    import time
    for _ in range(10):
        result = gitlab_api("get", f"/projects/{project_id}/pipelines?ref={ref}&per_page=1")
        if result and len(result) > 0:
            pipeline_id = result[0]["id"]
            logger.info(f"找到最新Pipeline #{pipeline_id} for project {project_id}")
            return pipeline_id
        time.sleep(1)
    logger.warning(f"No pipeline found for project {project_id} ref={ref}")
    return None
```

**Result**: Only 1 Pipeline per push (source=push)

### Error 4: Build Job Takes 400+ Seconds

**Symptom**:
```
[1] running - build (17s)
[2] running - build (27s)
...
[40] running - build (475s)
```

Job stuck on "Pulling docker image registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper..."

**Cause**: GitLab Runner `pull_policy = "always"` tries to pull image from registry even when cached locally

**Fix**: Configure Runner to use local images:
```bash
docker exec gitlab-runner bash -c 'cat >> /etc/gitlab-runner/config.toml << EOF
    pull_policy = ["if-not-present"]
EOF'
docker restart gitlab-runner
```

**Result**: Build job completes in ~5 seconds when image is cached.

### Error 5: Multiple Duplicate Webhooks

**Symptom**:
```
Webhooks:
  id=2 url=http://localhost:8091/gitlab/push push_events=True
  id=3 url=http://localhost:8091/gitlab/push push_events=True
  id=4 url=http://localhost:8091/gitlab/push push_events=True
  id=5 url=http://localhost:8091/gitlab/push push_events=True
```

**Cause**: `setup-gitlab-webhook.sh` creates new webhook without checking if one already exists

**Fix**: Update script to check first:
```bash
EXISTING=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/hooks" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | \
  python3 -c "
import sys,json
hooks = json.load(sys.stdin)
for h in hooks:
    if h['url'] == '$WEBHOOK_URL':
        print('exists')
        break
")

if [ "$EXISTING" != "exists" ]; then
    curl -X POST "$GITLAB_URL/api/v4/projects/$PROJECT_ID/hooks" ...
fi
```

## Required Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| GITLAB_URL | Yes | http://localhost:8080 | GitLab API endpoint |
| GITLAB_TOKEN | **Yes** | "" (empty) | GitLab private token — MUST be set |
| OBS_API_URL | Yes | http://localhost:4455 | OBS API endpoint |
| OBS_USER | Yes | Admin | OBS username |
| OBS_PASSWORD | Yes | admin123 | OBS password |
| DOCKER_API_VERSION | Yes | 1.39 | Docker API version for compatibility |
| GITLAB_SECRET_TOKEN | No | "" | Webhook secret for verification |

## Key Lessons

1. **GITLAB_TOKEN is mandatory** — without it, all GitLab API calls fail
2. **webhook-server should only monitor Pipelines** — GitLab push event already triggers Pipeline automatically
3. **Runner pull_policy affects build speed** — "if-not-present" is essential for fast builds
4. **Check for existing webhooks before creating** — avoid duplicate triggers

## Related Files

- `/home/nando/AICICD/01-source-trigger/webhook-server/app.py` — Main webhook server code
- `/home/nando/AICICD/scripts/setup-gitlab-webhook.sh` — Webhook setup script (updated)
- `/home/nando/AICICD/scripts/fix-gitlab-runner.sh` — Runner configuration fix
- `/home/nando/AICICD/docs/debug/add-test-folder-process.md` — Full debugging log