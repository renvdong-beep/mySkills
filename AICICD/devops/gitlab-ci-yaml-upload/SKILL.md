---
name: gitlab-ci-yaml-upload
description: Upload .gitlab-ci.yml to GitLab via REST API. Covers base64 encoding to avoid variable substitution, YAML special character escaping, block scalar for complex scripts, and Pipeline validation.
tags: [gitlab, ci, yaml, api, pipeline, upload, base64]
---

# GitLab CI YAML 上传与验证

通过 GitLab REST API 上传 `.gitlab-ci.yml`，解决变量替换、YAML 特殊字符、编码等常见问题。

## Triggers

- 通过 API 更新 GitLab CI 配置文件
- git clone 失败 (503) 需要直接操作文件
- Pipeline 创建后直接 failed 无 jobs
- YAML 语法验证

## 核心方法：Base64 编码上传

**为什么必须用 base64**: 直接用 JSON content 字段上传时，Python/shell 变量替换会破坏 YAML 中的 `${VAR}` 语法，导致 GitLab 解析失败。

```bash
# 正确方式：base64 编码上传
CI_B64=$(base64 -w 0 /tmp/ci.yml)
curl -s -X PUT "http://localhost:8080/api/v4/projects/1/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  -d "{\"branch\":\"main\",\"content\":\"$CI_B64\",\"encoding\":\"base64\",\"commit_message\":\"Update CI\"}"
```

**错误方式** (变量被替换):
```bash
# Python 中 ${PACKAGE_NAME} 会被替换为空字符串
python3 -c "
content = open('/tmp/ci.yml').read()
# content 中的 ${PACKAGE_NAME} 在 f-string 中被替换！
json.dumps(content)  # 变量丢失
"
```

## Common Pitfalls

### 1. Python 变量替换破坏 YAML

**Symptom**: Pipeline 创建后 YAML 解析错误，`${VAR}` 变成空字符串

**Root cause**: Python 的 f-string 或 shell 的 `$()` 会解释 `${}` 语法

**Fix**: 使用 base64 编码，绕过所有变量替换:
```bash
CI_B64=$(base64 -w 0 /tmp/ci.yml)
# base64 字符串不含 $ 或特殊字符，安全嵌入 JSON
```

### 2. YAML 中的 * 被解析为别名

**Symptom**: "did not find expected alphabetic or numeric character while scanning an alias"

**Root cause**: YAML 中 `*` 是别名指示符，如 `tar -czvf ../pkg.tar.gz *` 中的 `*` 会被误解析

**Fix**: 使用块标量 `|` 包裹 script:
```yaml
build:
  script:
    - |
      cd ${PACKAGE_DIR}
      tar -czvf ../${PACKAGE_NAME}-1.0.0.tar.gz *
```

### 3. 长命令行含 $() 嵌套

**Symptom**: YAML 解析错误在包含 `$(command)` 的行

**Fix**: 用 `|` 块标量重写:
```yaml
# 错误：一行太长，$() 嵌套
script:
  - while [ "$(curl -s -u $OBS_USER:$OBS_PASSWORD $OBS_API_URL/build/$OBS_PROJECT/_result | grep -o 'state=\"[^\"]*\"' | head -1)" != "state=\"succeeded\"" ]; do sleep 30; done

# 正确：块标量
script:
  - |
    while true; do
      STATUS=$(curl -s -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/build/$OBS_PROJECT/_result")
      if echo "$STATUS" | grep -q 'state="succeeded"'; then
        break
      fi
      sleep 30
    done
```

### 4. artifacts 路径变量未展开

**Symptom**: `artifacts:paths` 中 `${PACKAGE_NAME}-1.0.0.tar.gz` 匹配不到文件

**Root cause**: GitLab CI 的 artifacts paths 不支持变量展开（某些版本）

**Fix**: 使用通配符:
```yaml
artifacts:
  paths:
    - "*.tar.gz"
  expire_in: 1 hour
```

### 5. Pipeline 直接 failed 无 jobs

**Symptom**: `POST /api/v4/projects/:id/pipeline` 返回 pipeline 但 status=failed，jobs 列表为空

**Root cause**: `.gitlab-ci.yml` YAML 语法错误

**Debug 方法**:
```bash
# 方法1: API 创建 pipeline 查看错误
curl -s -X POST "http://localhost:8080/api/v4/projects/1/pipeline?ref=main" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | python3 -c "
import sys, json
p = json.loads(sys.stdin.read())
if p.get('message'):
    print('Error:', p['message'])
else:
    print(f'Pipeline #{p[\"id\"]} status={p[\"status\"]}')"

# 方法2: CI Lint API (如果可用)
curl -s -X POST "http://localhost:8080/api/v4/ci/lint" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -d "content=$(base64 -w 0 /tmp/ci.yml)"
```

### 6. 逐步定位 YAML 错误

当 YAML 错误信息不够明确时，用二分法逐步定位:

```bash
# 1. 上传最简 CI (只有 stages + 1个 job + 1行 script)
# 2. 如果成功，逐步添加内容
# 3. 每次添加后触发 Pipeline 验证
# 4. 定位到具体哪行/哪个字段导致错误

# 常见出错点:
# - script 中的 * $ { } ( ) 特殊字符
# - artifacts 配置格式
# - variables 中的特殊值
# - while/for 循环命令
```

## CI 模板最佳实践

### 6阶段 CI 模板 (OBS + Packer)

```yaml
stages:
  - build
  - obs-trigger
  - obs-wait
  - sync
  - quality-gate
  - update-repo

variables:
  PACKAGE_NAME: "hello-world"
  PACKAGE_DIR: "hello-world"
  OBS_API_URL: "http://localhost:4455"
  OBS_USER: "Admin"
  OBS_PASSWORD: "admin123"
  OBS_PROJECT: "home:Admin:${PACKAGE_NAME}"
  SYNC_URL: "http://localhost:8090"

build:
  stage: build
  image: alpine:latest
  script:
    - apk add --no-cache tar
    - cd ${PACKAGE_DIR}
    - tar -czvf ../${PACKAGE_NAME}-1.0.0.tar.gz *
  artifacts:
    paths:
      - "*.tar.gz"
    expire_in: 1 hour

obs-trigger:
  stage: obs-trigger
  image: alpine:latest
  dependencies: [build]
  script:
    - apk add --no-cache curl
    - |
      curl -s -u "$OBS_USER:$OBS_PASSWORD" \
        -T ${PACKAGE_NAME}-1.0.0.tar.gz \
        "$OBS_API_URL/source/$OBS_PROJECT/$PACKAGE_NAME/${PACKAGE_NAME}-1.0.0.tar.gz"
    - |
      curl -s -u "$OBS_USER:$OBS_PASSWORD" \
        -T ${PACKAGE_DIR}/${PACKAGE_NAME}.spec \
        "$OBS_API_URL/source/$OBS_PROJECT/$PACKAGE_NAME/${PACKAGE_NAME}.spec"

obs-wait:
  stage: obs-wait
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - |
      for i in $(seq 1 40); do
        STATUS=$(curl -s -u "$OBS_USER:$OBS_PASSWORD" "$OBS_API_URL/build/$OBS_PROJECT/_result")
        if echo "$STATUS" | grep -q 'state="succeeded"'; then
          echo "Build succeeded"
          exit 0
        fi
        echo "Waiting... ($i/40)"
        sleep 30
      done
      echo "Build timeout"
      exit 1

sync:
  stage: sync
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - |
      curl -X POST "$SYNC_URL/sync" \
        -H "Content-Type: application/json" \
        -d "{\"project\":\"$OBS_PROJECT\",\"package\":\"$PACKAGE_NAME\",\"repository\":\"standard\",\"arch\":\"aarch64\"}"

quality-gate:
  stage: quality-gate
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - |
      curl -X POST "http://localhost:8081/check" \
        -H "Content-Type: application/json" \
        -d "{\"project\":\"$OBS_PROJECT\",\"package\":\"$PACKAGE_NAME\",\"arch\":\"aarch64\"}"

update-repo:
  stage: update-repo
  image: alpine:latest
  script:
    - apk add --no-cache curl
    - curl -X POST "$SYNC_URL/update-repo/aarch64"
```

### 7. CI_PROJECT_NAME ≠ OBS Package Name — Use Per-Project Variables

**Symptom**: OBS trigger fails with `unknown_project` because `OBS_PROJECT` resolves to `home:Admin:repo-name` instead of `home:Admin:package-name`

**Root cause**: GitLab's `CI_PROJECT_NAME` is the repository project name (e.g., `intewell-test`), which may differ from the OBS package name (e.g., `hello-world`). Defining `OBS_PROJECT: "home:Admin:${CI_PROJECT_NAME}"` in YAML variables hardcodes the repo name.

**Fix**: Do NOT define `OBS_PROJECT` in YAML variables. Instead, use `PACKAGE_NAME` (set as per-project CI/CD variable) directly in script commands. Set `PACKAGE_NAME` and `PACKAGE_DIR` via GitLab API:
```bash
curl -X POST "http://localhost:8080/api/v4/projects/$ID/variables" \
  -H "Content-Type: application/json" \
  -d '{"key":"PACKAGE_NAME","value":"hello-world"}'
curl -X POST "http://localhost:8080/api/v4/projects/$ID/variables" \
  -H "Content-Type: application/json" \
  -d '{"key":"PACKAGE_DIR","value":"hello-world"}'
```

## 相关 API

```bash
# 读取当前 CI 配置
curl -s "http://localhost:8080/api/v4/projects/1/repository/files/.gitlab-ci.yml/raw?ref=main" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN"

# 更新 CI 配置 (base64)
CI_B64=$(base64 -w 0 /tmp/ci.yml)
curl -s -X PUT "http://localhost:8080/api/v4/projects/1/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  -d "{\"branch\":\"main\",\"content\":\"$CI_B64\",\"encoding\":\"base64\",\"commit_message\":\"Update CI\"}"

# 触发 Pipeline
curl -s -X POST "http://localhost:8080/api/v4/projects/1/pipeline?ref=main" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN"
```

## Related Skills

- `gitlab-runner-docker` - GitLab Runner 部署与调试
- `cicd-pipeline-services` - CI/CD 微服务实现
- `obs-build-service` - OBS 构建服务
