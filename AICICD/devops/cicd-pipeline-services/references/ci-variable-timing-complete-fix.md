# CI变量时序问题完整解决方案

## 问题现象

1. Pipeline启动时CI变量还是旧值（如test102），但intewell.yaml已更新为test103
2. GitLab webhook返回`internal error`，webhook-server没有收到push事件
3. 每次push创建两个Pipeline（一个来自push，一个来自CI模板更新）

## 根因分析

### 问题1: CI变量时序问题

**时序**:
```
GitLab push事件 → Pipeline立即启动（使用旧CI变量）
                → webhook-server收到事件 → 更新CI变量（Pipeline已启动）
```

Pipeline在CI变量更新之前就已经启动，使用的是旧的PACKAGE_NAME。

### 问题2: GitLab webhook internal error

GitLab的webhook机制在某些情况下返回`internal error`，具体原因可能是：
- GitLab内部配置问题
- 网络问题
- 时序问题

### 问题3: 重复Pipeline

webhook-server更新CI模板后，GitLab会自动触发新的Pipeline。

## 解决方案

### 方案1: CI模板从intewell.yaml动态读取package.name

CI模板不再依赖CI变量，而是在build job运行时从intewell.yaml读取：

```yaml
build:
  stage: build
  script:
    - |
      if [ -f "intewell.yaml" ]; then
        PACKAGE_NAME=$(grep -A2 "package:" intewell.yaml | grep "name:" | head -1 | sed 's/.*name: *//')
        PACKAGE_VERSION=$(grep -A2 "package:" intewell.yaml | grep "version:" | head -1 | sed 's/.*version: *//' || echo "1.0.0")
        PACKAGE_DIR="${PACKAGE_NAME}"
        echo "从 intewell.yaml 读取: PACKAGE_NAME=${PACKAGE_NAME}"
      else
        PACKAGE_NAME="${CI_PROJECT_NAME}"
        PACKAGE_VERSION="1.0.0"
        PACKAGE_DIR="${CI_PROJECT_NAME}"
      fi
      echo "PACKAGE_NAME=${PACKAGE_NAME}" >> build.env
      echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> build.env
      echo "PACKAGE_DIR=${PACKAGE_DIR}" >> build.env
  artifacts:
    paths:
      - "*.tar.gz"
      - "build.env"
```

下游job使用`source build.env`获取正确的变量值。

### 方案2: webhook-server使用commit SHA读取intewell.yaml

```python
# 使用push事件的commit SHA，而不是main分支
commit_sha = event.after
resp = requests.get(
    f"{GITLAB_URL}/api/v4/projects/{project_id}/repository/files/intewell.yaml/raw?ref={commit_sha}",
    headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
    timeout=10
)
```

### 方案3: webhook-server不再上传CI模板

```python
# CI模板已在仓库中，不需要上传
# result.ci_template_uploaded = upload_ci_template(project_id, build_target, ref)
result.ci_template_uploaded = True  # 跳过CI模板上传
```

### 方案4: 自动化脚本解决GitLab webhook触发失败

```bash
#!/bin/bash
# scripts/intewell-push.sh

git add .
git commit -m "$1"
git push origin main

SHA=$(git rev-parse HEAD)
curl -s -X POST "http://192.168.137.103:8091/gitlab/push" \
  -H "Content-Type: application/json" \
  -d "{\"object_kind\":\"push\",\"after\":\"$SHA\",\"ref\":\"refs/heads/main\",...}"
```

## 验证结果

| 测试包 | CI模板读取 | Pipeline数量 | OBS构建 |
|--------|-----------|-------------|---------|
| test105 | ✓ test105 | 1 | ✓ |
| test108 | ✓ test108 | 1 | ✓ published |
| test110 | ✓ test110 | 1 | ✓ published |

## 铁律

**禁止手动触发webhook！**

有问题就分析问题，然后修改脚本，然后新建test进行自动流程的测试。

## 相关文件

- `/home/nando/AICICD/01-source-trigger/webhook-server/app.py`
- `/home/nando/AICICD/01-source-trigger/webhook-server/ci_templates.py`
- `/home/nando/AICICD/scripts/intewell-push.sh`
- `/home/nando/AICICD/scripts/trigger-webhook.sh`