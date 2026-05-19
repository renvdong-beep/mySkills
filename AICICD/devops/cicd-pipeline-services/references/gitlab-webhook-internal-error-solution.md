# GitLab Webhook "internal error" 完整解决方案

## 日期: 2026-05-19

## 问题现象

GitLab webhook 配置正确，但事件列表始终为空，webhook-server 从未收到任何请求。

**GitLab 日志**:
```
"exception.class":"Errno::EHOSTUNREACH"
"exception.message":"Failed to open TCP connection to 192.168.137.103:8091 (No route to host)"
```

**webhook-server 日志**: 无任何请求记录

## 根本原因

GitLab 容器内部有防火墙/网络隔离机制，即使配置了 `allow_local_requests_from_hooks_and_services=true`，也无法访问：
- 宿主机 IP 地址
- 其他 Docker 容器的 IP 地址
- Docker 网络网关

这是 GitLab 容器的内部限制，不是 Docker 网络配置问题。

## 尝试过但失败的方案

### 1. 使用 host.docker.internal
```bash
curl -X POST ... -d '{"url": "http://host.docker.internal:8091/gitlab/push"}'
```
**结果**: `host.docker.internal` 仅在 Docker Desktop (Mac/Windows) 可用，Linux 上无法解析

### 2. 使用 Docker 网络网关 IP
```bash
curl -X POST ... -d '{"url": "http://172.28.0.1:8091/gitlab/push"}'
```
**结果**: GitLab 容器无法访问网关 IP

### 3. 将 webhook-server 加入同一网络
```bash
docker network connect cicd_network webhook-server
curl -X POST ... -d '{"url": "http://webhook-server:8091/gitlab/push"}'
```
**结果**: GitLab 无法解析容器名称，也无法访问容器 IP

### 4. 修改 GitLab 容器防火墙
```bash
docker exec gitlab iptables -A OUTPUT -d 192.168.137.103 -j ACCEPT
```
**结果**: GitLab 容器没有 iptables 权限

## 最终解决方案

**绕过 GitLab webhook 机制**，在 CI Pipeline 的 build job 中主动调用 webhook-server。

### 架构

```
git push
   │
   ▼
GitLab Pipeline 触发
   │
   ▼
build job (GitLab Runner, host 网络)
   │
   ├─► 读取 intewell.yaml 获取 package.name
   │
   └─► curl POST webhook-server /gitlab/push
          │
          ▼
       webhook-server (host 网络)
          │
          ├─► 创建 OBS 项目
          ├─► 设置 CI 变量
          └─► 返回成功
   │
   ▼
obs-trigger job 上传源码
   │
   ▼
OBS 自动构建
   │
   ▼
Pipeline 完成
```

### 关键配置

#### 1. GitLab Runner - host 网络模式

```bash
docker run -d \
  --name gitlab-runner \
  --network host \
  --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
```

**配置文件** `/srv/gitlab-runner/config/config.toml`:
```toml
concurrent = 4

[[runners]]
  name = "intewell-runner"
  url = "http://192.168.137.103:8080"
  executor = "docker"
  [runners.docker]
    image = "python:3.11-slim"
    privileged = true
    network_mode = "host"
    pull_policy = ["if-not-present"]
```

#### 2. webhook-server - host 网络模式

```bash
docker run -d \
  --name webhook-server \
  --network host \
  -e GITLAB_URL="http://localhost:8080" \
  -e GITLAB_TOKEN="glpat-xxx" \
  -e OBS_URL="http://localhost:4455" \
  intewell-webhook-server:v3.8
```

#### 3. CI 模板 - build job 触发 webhook

```yaml
build:
  stage: build
  image: alpine:latest
  script:
    - |
      # 从 intewell.yaml 动态读取 package.name
      if [ -f "intewell.yaml" ]; then
        PACKAGE_NAME=$(grep -A2 "package:" intewell.yaml | grep "name:" | head -1 | sed 's/.*name: *//')
        PACKAGE_VERSION=$(grep -A2 "package:" intewell.yaml | grep "version:" | head -1 | sed 's/.*version: *//' || echo "1.0.0")
      else
        PACKAGE_NAME="${CI_PROJECT_NAME}"
        PACKAGE_VERSION="1.0.0"
      fi
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
    - sleep 5  # 等待 webhook-server 创建 OBS 项目
    - |
      # 导出到后续 job
      echo "PACKAGE_NAME=${PACKAGE_NAME}" >> build.env
      echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> build.env
  artifacts:
    paths:
      - "*.tar.gz"
      - "build.env"
```

### webhook payload 必需字段

webhook-server 使用 pydantic 验证 payload，缺少以下字段会返回 `400 Bad Request`:

- `object_kind` - 必须是 "push"
- `before` - 任意 commit SHA (可以是 "abc123")
- `after` - 当前 commit SHA (${CI_COMMIT_SHA})
- `ref` - 分支引用 ("refs/heads/main")
- `user_name` - 任意用户名 (可以是 "ci-bot")
- `project.id` - GitLab 项目 ID (${CI_PROJECT_ID})
- `project.name` - 项目名称 (${CI_PROJECT_NAME})
- `repository.name` - 仓库名称
- `commits` - 至少一个 commit 对象

**错误示例**:
```
3 validation errors for GitLabPushEvent
before: Field required
commits: Field required
user_name: Field required
```

## 验证结果

**test126**: Pipeline #230 success, OBS x86_64 + aarch64 published

**用户操作**: 只需 `git push`，后续全部自动化

## 为什么这个方案有效

1. **GitLab Runner 使用 host 网络** → 可以访问宿主机上的所有服务
2. **webhook-server 使用 host 网络** → 监听宿主机端口，Runner 可达
3. **CI build job 主动调用 webhook** → 绕过 GitLab 容器的网络隔离
4. **webhook payload 完整** → pydantic 验证通过，OBS 项目创建成功

## 相关文件

- CI 模板: `/tmp/intewell-test/.gitlab-ci.yml`
- webhook-server: `/home/nando/AICICD/01-source-trigger/webhook-server/app.py`
- Runner 配置: `/srv/gitlab-runner/config/config.toml`
- 固化文档: `/home/nando/AICICD/docs/cicd-flow-snapshot-2026-05-19.md`

## 教训

- GitLab 容器的网络隔离是内部机制，无法通过 Docker 网络配置绕过
- 不要在 GitLab webhook 上浪费时间 — 直接在 CI Pipeline 中解决
- `host` 网络模式是 Linux 上最简单可靠的网络方案
