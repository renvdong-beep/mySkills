# CI Variable Timing Issue — Complete Fix (2026-05-19)

## Problem

When a developer pushes a new package (e.g., test105) to GitLab:
1. GitLab immediately triggers a Pipeline
2. webhook-server receives the push event and updates CI variables (PACKAGE_NAME)
3. But the Pipeline has already started with OLD CI variables

**Result**: Pipeline uses wrong package name (e.g., test104 instead of test105)

## Root Cause Analysis

The timing sequence:
```
push event → GitLab creates Pipeline (instant) → Pipeline starts with old variables
            → webhook-server receives event (delayed) → updates CI variables
            → Pipeline already running, can't change variables
```

## Solution 1: CI Template Reads intewell.yaml Dynamically

The CI template should NOT rely on CI variables. Instead, read `package.name` from `intewell.yaml` at runtime:

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

Downstream jobs use `source build.env` to get correct values.

## Solution 2: webhook-server Reads intewell.yaml from Commit SHA

webhook-server should read `intewell.yaml` from the push event's commit SHA, not from `main` branch:

```python
# In detect_packages_from_push() and handle_push_event()
commit_sha = event.after  # push 事件中的最新 commit
resp = requests.get(
    f"{GITLAB_URL}/api/v4/projects/{project_id}/repository/files/intewell.yaml/raw?ref={commit_sha}",
    headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
    timeout=10
)
```

This ensures webhook-server reads the correct `intewell.yaml` that was just pushed.

## Solution 3: webhook-server Does NOT Upload CI Template

Uploading CI template via API creates a new commit, which triggers another Pipeline. This causes duplicate Pipelines.

**Fix**: Skip CI template upload since template is already in repository:

```python
# In onboard_and_build()
result.ci_template_uploaded = True  # 跳过CI模板上传
```

## Verification Results

| Test | Before Fix | After Fix |
|------|------------|-----------|
| test104 | Wrong package name | — |
| test105 | Wrong package name | Correct (test105) |
| test106 | Duplicate Pipelines (#200, #201) | — |
| test107 | — | Single Pipeline (#202) |
| test108 | — | Single Pipeline (#203), correct package name |

## Key Lessons

1. **CI variables are obsolete** — CI template reads intewell.yaml directly
2. **No manual triggers** — Automation must work end-to-end
3. **No duplicate Pipelines** — Don't update CI template via API
4. **Systematic debugging** — Analyze → Fix → Verify with new test package

## User Corrections

- "为什么每次都要你手动触发webhook？" — Don't manually trigger, fix the automation
- "不要CI模板的问题没解决，你的修改又造成新的问题" — Fixes must not introduce new issues
- "为什么创建了200和201两个pipline" — Duplicate Pipelines from CI template update