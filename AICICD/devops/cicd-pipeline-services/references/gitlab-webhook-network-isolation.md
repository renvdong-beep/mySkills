# GitLab Webhook Network Isolation — Complete Solution

**Date**: 2026-05-19
**Issue**: GitLab webhook returns `internal error`, webhook-server never receives events

## Root Cause

GitLab container cannot reach webhook-server on host IP due to internal network isolation:

```
"exception.class":"Errno::EHOSTUNREACH"
"exception.message":"Failed to open TCP connection to 192.168.137.103:8091 (No route to host)"
```

Even when both containers are on the same Docker network (`cicd_network`), GitLab's internal network stack blocks connections to other containers.

## Attempted Fixes (All Failed)

1. **Using `host.docker.internal`** — Only works on Docker Desktop (Mac/Windows), not Linux
2. **Using Docker network gateway IP** (e.g., `172.28.0.1`) — Still blocked
3. **Adding webhook-server to same network as GitLab** — GitLab still can't reach it
4. **Using container name** (`http://webhook-server:8091`) — DNS resolution fails inside GitLab

## Solution: Self-Contained CI Template

The CI template auto-creates OBS project and package, eliminating dependency on webhook-server for OBS setup:

```yaml
obs-trigger:
  stage: obs-trigger
  script:
    - source build.env
    - apk add --no-cache curl
    - OBS_PROJECT="home:Admin:${PACKAGE_NAME}"
    
    # 1. Create OBS project if not exists
    - |
      obs_check=$(curl -s -u "${OBS_USER}:${OBS_PASSWORD}" "${OBS_API}/source/${OBS_PROJECT}/_meta" 2>&1)
      if echo "$obs_check" | grep -q "does not exist\|unknown_project\|404"; then
        echo "OBS项目不存在，正在创建..."
        curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -X PUT "${OBS_API}/source/${OBS_PROJECT}/_meta" \
          -H "Content-Type: text/xml" \
          -d "<project name='${OBS_PROJECT}'><title>${PACKAGE_NAME} package build</title><description>${PACKAGE_NAME} package build for Intewell CI/CD</description><person userid='${OBS_USER}' role='maintainer'/><repository name='standard'><path project='home:Admin:openEuler24.03-SP1' repository='standard'/><arch>x86_64</arch><arch>aarch64</arch></repository></project>"
        echo "OBS项目创建成功: ${OBS_PROJECT}"
      else
        echo "OBS项目已存在: ${OBS_PROJECT}"
      fi
    
    # 2. Create OBS package if not exists
    - |
      pkg_check=$(curl -s -u "${OBS_USER}:${OBS_PASSWORD}" "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/_meta" 2>&1)
      if echo "$pkg_check" | grep -q "does not exist\|unknown_package\|404"; then
        echo "OBS包不存在，正在创建..."
        curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -X PUT "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/_meta" \
          -H "Content-Type: text/xml" \
          -d "<package name='${PACKAGE_NAME}' project='${OBS_PROJECT}'><title>${PACKAGE_NAME}</title><description>${PACKAGE_NAME} package</description></package>"
        echo "OBS包创建成功: ${PACKAGE_NAME}"
      else
        echo "OBS包已存在: ${PACKAGE_NAME}"
      fi
    
    # 3. Upload files
    - curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -T "${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz" "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
    - curl -s -u "${OBS_USER}:${OBS_PASSWORD}" -T "${PACKAGE_DIR}/${PACKAGE_NAME}.spec" "${OBS_API}/source/${OBS_PROJECT}/${PACKAGE_NAME}/${PACKAGE_NAME}.spec"
```

## Key Points

1. **OBS project _meta must include `<repository>`** with `<path>` to DoD and `<arch>` for each architecture
2. **OBS package _meta must be created before uploading files**
3. **Project `kind` attribute must be empty** — `kind='package'` is illegal
4. **First build takes 10-20 minutes** — increase obs-wait timeout to 1200s

## Fallback Script

For cases where GitLab webhook fails, use `scripts/intewell-push.sh`:

```bash
#!/bin/bash
# git push + auto webhook trigger
git add .
git commit -m "$1"
git push origin main

SHA=$(git rev-parse HEAD)
curl -s -X POST "http://192.168.137.103:8091/gitlab/push" \
  -H "Content-Type: application/json" \
  -d "{\"object_kind\":\"push\",\"after\":\"$SHA\",\"ref\":\"refs/heads/main\",\"project\":{\"id\":1},\"commits\":[{\"id\":\"$SHA\"}]}"
```

## Verification

```bash
# Check OBS project
curl -s -u "Admin:admin123" "http://localhost:5352/source/home:Admin:test119/_meta"

# Check OBS package
curl -s -u "Admin:admin123" "http://localhost:5352/source/home:Admin:test119/test119/_meta"

# Check OBS build status
curl -s "http://localhost:5352/build/home:Admin:test119/_result" --user "Admin:admin123"
```

## Related Pitfalls

- Pitfall #61: GitLab webhook "internal error" — container network isolation
- Pitfall #62: OBS project must include repository config for builds
- Pitfall #63: OBS package must be created before uploading files
- Pitfall #64: OBS project `kind` attribute must be empty
- Pitfall #65: OBS build wait timeout — first build takes longer
