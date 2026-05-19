# Intewell Multi-Package CI/CD Template

**Last updated**: 2026-05-15
**Status**: Verified working with hello-world + demo-app parallel pipelines

## Architecture

```
Developer A push → GitLab repo: intewell-test → CI → OBS home:Admin:hello-world
Developer B push → GitLab repo: demo-app     → CI → OBS home:Admin:demo-app
                                                    ↓
                                          OBS 集成项目 home:Admin (path层叠+_link包)
                                                    ↓
                                          sync-service sync-all (从子项目同步)
                                                    ↓
                                          merge RPMs → integration repo → createrepo_c
                                                    ↓
                                          Packer ISO 构建 (按需)
```

## GitLab CI/CD Variables (per project)

| Variable | hello-world project | demo-app project | Description |
|----------|--------------------|--------------------|-------------|
| PACKAGE_NAME | hello-world | demo-app | OBS package name (overrides CI_PROJECT_NAME) |
| PACKAGE_DIR | hello-world | demo-app | Source directory in repo |

**Critical**: `CI_PROJECT_NAME` may differ from OBS package name. For example,
`intewell-test` (GitLab project name) ≠ `hello-world` (OBS package name).
Always set `PACKAGE_NAME` as a CI/CD variable.

## CI Template (.gitlab-ci.yml)

```yaml
stages:
  - build
  - obs-trigger
  - obs-wait
  - sync
  - quality-gate
  - update-repo

variables:
  # PACKAGE_NAME and PACKAGE_DIR should be set as CI/CD variables per project
  # If not set, fallback to CI_PROJECT_NAME
  PACKAGE_NAME: "${CI_PROJECT_NAME}"
  PACKAGE_DIR: "${CI_PROJECT_NAME}"

build:
  stage: build
  tags: ["docker"]
  image: openeuler/openeuler:24.03
  script:
    - mkdir -p /tmp/${PACKAGE_NAME}-1.0.0
    - cp -r ${PACKAGE_DIR}/* /tmp/${PACKAGE_NAME}-1.0.0/
    - cd /tmp && tar -czvf ${CI_PROJECT_DIR}/${PACKAGE_NAME}-1.0.0.tar.gz ${PACKAGE_NAME}-1.0.0/
  artifacts:
    paths:
      - ${PACKAGE_NAME}-1.0.0.tar.gz
      - ${PACKAGE_DIR}/*.spec

obs-trigger:
  stage: obs-trigger
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - |
      OBS_PROJECT="home:Admin:${PACKAGE_NAME}"
      curl -u Admin:admin123 -X PUT -T ${PACKAGE_NAME}-1.0.0.tar.gz \
        "http://localhost:4455/source/${OBS_PROJECT}/${PACKAGE_NAME}/${PACKAGE_NAME}-1.0.0.tar.gz"
      for spec_file in ${PACKAGE_DIR}/*.spec; do
        spec_name=$(basename $spec_file)
        curl -u Admin:admin123 -X PUT -T $spec_file \
          "http://localhost:4455/source/${OBS_PROJECT}/${PACKAGE_NAME}/$spec_name"
      done

obs-wait:
  stage: obs-wait
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - |
      OBS_PROJECT="home:Admin:${PACKAGE_NAME}"
      for i in $(seq 1 60); do
        STATUS=$(curl -s "http://localhost:8090/obs-build-status/${OBS_PROJECT}/${PACKAGE_NAME}")
        if echo "$STATUS" | grep -q '"overall":"succeeded"'; then
          echo "Build succeeded!"
          exit 0
        fi
        echo "Waiting for OBS build... ($i/60)"
        sleep 30
      done
      echo "Build timeout!"
      exit 1

sync-x86_64:
  stage: sync
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -s -X POST "http://localhost:8090/sync-all/home:Admin/standard/x86_64"

sync-aarch64:
  stage: sync
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -s -X POST "http://localhost:8090/sync-all/home:Admin/standard/aarch64"

quality-gate-x86_64:
  stage: quality-gate
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -s "http://localhost:8081/quality-check/home:Admin/standard/x86_64"

quality-gate-aarch64:
  stage: quality-gate
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -s "http://localhost:8081/quality-check/home:Admin/standard/aarch64"

update-repo:
  stage: update-repo
  tags: ["docker"]
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -s -X POST "http://localhost:8090/update-repo/x86_64"
    - curl -s -X POST "http://localhost:8090/update-repo/aarch64"
```

## New Project Setup Checklist

When adding a new package to the CI/CD system:

1. **Create OBS sub-project**: `home:Admin:new-package`
   - Set `_meta` with DoD path to `home:Admin:openEuler24.03-SP1`
   - Set `_config` (copy from existing sub-project)
   - Upload source files (spec + tarball)

2. **Update integration project** `home:Admin`:
   - Add path to new sub-project in `_meta`
   - Create `_link` package: `echo '<link project="home:Admin:new-package" package="new-package"/>' | curl -u Admin:admin123 -X PUT -T - "http://localhost:4455/source/home:Admin/new-package/_link"`
   - **Must use `-T` flag** for _link upload (not `--data-binary`)

3. **Create GitLab repository**: `renwd/new-package`
   - Upload source code (spec + source files)
   - Upload `.gitlab-ci.yml` (same template as other projects)

4. **Set GitLab CI/CD variables**:
   - `PACKAGE_NAME` = new-package
   - `PACKAGE_DIR` = new-package

5. **Enable Runner for new project**:
   ```bash
   curl -s --header "PRIVATE-TOKEN: $TOKEN" -X POST \
     "http://localhost:8080/api/v4/projects/{id}/runners" \
     -H "Content-Type: application/json" -d '{"runner_id": 2}'
   docker restart gitlab-runner  # May be needed
   ```

6. **Trigger pipeline**: Push to repo or use API

## Key Pitfalls

- **CI_PROJECT_NAME ≠ PACKAGE_NAME**: GitLab project name may differ from OBS package name
- **Tarball must have PackageName-Version/ subdirectory**: `%setup -q` expects it
- **OBS sub-project must have _config**: New sub-projects fail without it
- **Runner must be enabled for each new project**: Not automatic
- **_link upload must use -T flag**: `--data-binary @-` creates 0-byte file
- **OBS API hostname**: See obs-build-service pitfall #34