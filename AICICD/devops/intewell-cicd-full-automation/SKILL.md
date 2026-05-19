---
name: intewell-cicd-full-automation
description: Intewell CI/CD全自动化流程。用户只需git push，后续全部自动化：GitLab Pipeline触发 → webhook-server创建OBS项目 → OBS构建 → sync → quality-gate → update-repo。
tags:
  - intewell
  - cicd
  - automation
  - obs
  - gitlab
---

# Intewell CI/CD 全自动化流程

## 流程概述

用户只需执行 `git push`，后续全部自动化完成：

```
git push → Pipeline触发 → build → obs-trigger → obs-wait → sync → quality-gate → update-repo
```

## CI Pipeline 6个步骤

| 步骤 | 名称 | 功能 |
|------|------|------|
| 1 | build | 打包源码，触发webhook-server创建OBS项目 |
| 2 | obs-trigger | 上传源码和spec文件到OBS |
| 3 | obs-wait | 等待OBS构建完成（超时600秒） |
| 4 | sync | 同步RPM到仓库（x86_64 + aarch64） |
| 5 | quality-gate | 质量检查（依赖检查、CVE扫描） |
| 6 | update-repo | 更新仓库元数据（createrepo_c） |

## 关键配置

### 1. intewell.yaml

项目根目录必须包含`intewell.yaml`配置文件：

```yaml
package:
  name: test-package
  version: 1.0.0
build:
  target: rpm-only  # rpm-only 或 iso
  arch:
    - x86_64
    - aarch64
```

### 2. CI模板 (.gitlab-ci.yml)

关键部分：

```yaml
stages:
  - build
  - obs-trigger
  - obs-wait
  - sync
  - quality-gate
  - update-repo

variables:
  OBS_USER: "Admin"
  OBS_PASSWORD: "admin123"
  OBS_API: "http://localhost:5352"
  SYNC_SERVICE: "http://localhost:8090"
  QUALITY_GATE: "http://localhost:8081"

build:
  stage: build
  script:
    - |
      # 从intewell.yaml读取package.name
      PACKAGE_NAME=$(grep -A2 "package:" intewell.yaml | grep "name:" | sed 's/.*name: *//')
    - |
      # 触发webhook-server创建OBS项目
      curl -X POST "http://192.168.137.103:8091/gitlab/push" ...
```

### 3. 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| GitLab | 8080 | 源码仓库 |
| OBS API | 5352 | RPM构建服务 |
| OBS HTTP | 5252 | RPM仓库 |
| webhook-server | 8091 | Webhook接收 |
| sync-service | 8090 | 制品同步 |
| quality-gate | 8081 | 质量门禁 |

## 使用方法

### 创建新包

1. 创建源码目录和文件
2. 创建spec文件
3. 创建intewell.yaml
4. git push

```bash
mkdir -p my-package
cat > my-package/my-package.c << 'EOF'
#include <stdio.h>
int main() { printf("Hello\n"); return 0; }
EOF

cat > my-package/my-package.spec << 'EOF'
Name: my-package
Version: 1.0.0
...
EOF

cat > intewell.yaml << 'EOF'
package:
  name: my-package
  version: 1.0.0
build:
  target: rpm-only
  arch:
    - x86_64
    - aarch64
EOF

git add .
git commit -m "Add my-package"
git push origin main
```

### 验证构建状态

```bash
# 检查Pipeline状态
curl -s "http://localhost:8080/api/v4/projects/1/pipelines?per_page=3" \
  --header "PRIVATE-TOKEN: $TOKEN"

# 检查OBS构建状态
curl -s "http://localhost:5352/build/home:Admin:my-package/_result" \
  --user "Admin:admin123"
```

## 故障排查

### Pipeline卡在pending

**原因**: GitLab Runner配置丢失

**解决**: 检查Runner配置文件，必要时从备份恢复

### OBS项目不存在

**原因**: webhook-server未收到请求或返回错误

**解决**: 
1. 检查webhook-server日志
2. 检查CI模板中的webhook payload格式
3. 确认Runner和webhook-server都使用host网络模式

### OBS构建一直scheduled

**原因**: OBS scheduler未运行

**解决**:
```bash
docker exec obs-server-test perl /usr/lib/obs/server/bs_sched x86_64 --daemonize
docker exec obs-server-test perl /usr/lib/obs/server/bs_sched aarch64 --daemonize
```

### obs-wait超时

**原因**: OBS构建时间过长（首次构建需下载基础镜像）

**解决**: 增加obs-wait超时时间，或检查OBS构建日志

## Pitfalls

### 1. CI模板从intewell.yaml读取包名

**问题**: CI变量PACKAGE_NAME可能滞后

**解决**: 在build job运行时从intewell.yaml动态读取package.name

### 2. webhook payload必需字段

**问题**: 缺少before/user_name/commits导致400错误

**解决**: 确保payload包含所有必需字段

### 3. OBS项目repository配置

**问题**: OBS项目缺少repository配置导致无法构建

**解决**: webhook-server创建项目时必须包含repository和path配置

## 相关Skills

- gitlab-webhook-bypass: 解决webhook网络问题
- obs-build-service: OBS部署和调试
- gitlab-runner-docker: Runner配置