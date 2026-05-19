# CI Template Dynamic Package Name Reading

## Problem

GitLab push triggers Pipeline immediately. webhook-server's CI variable update happens AFTER Pipeline has started. The Pipeline uses stale CI variables (previous package's name).

## Solution

CI template reads `package.name` directly from `intewell.yaml` at runtime:

```yaml
build:
  stage: build
  image: alpine:latest
  script:
    - |
      # 从 intewell.yaml 动态读取 package.name 和 package.version
      if [ -f "intewell.yaml" ]; then
        PACKAGE_NAME=$(grep -A2 "package:" intewell.yaml | grep "name:" | head -1 | sed 's/.*name: *//')
        PACKAGE_VERSION=$(grep -A2 "package:" intewell.yaml | grep "version:" | head -1 | sed 's/.*version: *//' || echo "1.0.0")
        PACKAGE_DIR="${PACKAGE_NAME}"
        echo "从 intewell.yaml 读取: PACKAGE_NAME=${PACKAGE_NAME}, PACKAGE_VERSION=${PACKAGE_VERSION}"
      else
        # 无 intewell.yaml 时，使用 CI_PROJECT_NAME
        PACKAGE_NAME="${CI_PROJECT_NAME}"
        PACKAGE_VERSION="1.0.0"
        PACKAGE_DIR="${CI_PROJECT_NAME}"
        echo "无 intewell.yaml，使用默认: PACKAGE_NAME=${PACKAGE_NAME}"
      fi
      # 导出到后续 job
      echo "PACKAGE_NAME=${PACKAGE_NAME}" >> build.env
      echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> build.env
      echo "PACKAGE_DIR=${PACKAGE_DIR}" >> build.env
    - echo "=== Intewell CI/CD - ${PACKAGE_NAME} ==="
    - apk add --no-cache tar
    - mkdir -p /tmp/${PACKAGE_NAME}-${PACKAGE_VERSION}
    - cp -r ${PACKAGE_DIR}/* /tmp/${PACKAGE_NAME}-${PACKAGE_VERSION}/
    - cd /tmp && tar -czvf ${CI_PROJECT_DIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz ${PACKAGE_NAME}-${PACKAGE_VERSION}/
    - ls -la ${CI_PROJECT_DIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz
  artifacts:
    paths:
      - "*.tar.gz"
      - "build.env"
    expire_in: 1 hour

obs-trigger:
  stage: obs-trigger
  image: alpine:latest
  dependencies:
    - build
  script:
    - source build.env
    - apk add --no-cache curl
    - OBS_PROJECT="home:Admin:${PACKAGE_NAME}"
    - curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -T "${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz" "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
    - curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -T "${PACKAGE_DIR}/${PACKAGE_NAME}.spec" "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/${PACKAGE_NAME}.spec"
```

## Key Points

1. **No CI variables needed** — PACKAGE_NAME, PACKAGE_DIR are read from intewell.yaml at runtime
2. **build.env artifact** — Exports variables for downstream jobs
3. **source build.env** — Downstream jobs use this to get correct values
4. **Fallback to CI_PROJECT_NAME** — Works even without intewell.yaml

## Verification

```
从 intewell.yaml 读取: PACKAGE_NAME=test105, PACKAGE_VERSION=1.0.0
=== Intewell CI/CD - test105 ===
```

## Session Reference

- Session: 2026-05-19
- Issue: CI variable timing — Pipeline uses stale PACKAGE_NAME
- Fix: CI template reads intewell.yaml dynamically
- Verified: test105 Pipeline correctly used PACKAGE_NAME=test105
