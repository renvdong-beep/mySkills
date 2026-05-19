---
name: gitlab-webhook-bypass
description: 解决GitLab webhook返回internal error的问题。GitLab容器有防火墙限制无法访问宿主机IP，解决方案是在CI Pipeline的build job中主动调用webhook-server。
tags:
  - gitlab
  - webhook
  - network
  - docker
  - cicd
---

# GitLab Webhook Bypass

## 问题现象

GitLab配置的webhook URL返回`internal error`，webhook-server没有收到任何请求。

**错误日志**:
```
Failed to open TCP connection to 192.168.137.103:8091 
(No route to host - connect(2) for "192.168.137.103" port 8091)
```

## 根本原因

GitLab容器内部有防火墙限制，无法访问宿主机IP地址上的服务。

## 解决方案

**不依赖GitLab webhook机制**，而是在CI Pipeline的build job中主动调用webhook-server。

### 原理

1. GitLab Runner使用`host`网络模式
2. Runner可以访问宿主机上的所有服务
3. 在build job中用curl调用webhook-server API

### 关键配置

#### 1. GitLab Runner - host网络模式

```bash
docker run -d \
  --name gitlab-runner \
  --network host \
  --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
```

#### 2. webhook-server - host网络模式

```bash
docker run -d \
  --name webhook-server \
  --network host \
  -e GITLAB_URL="http://localhost:8080" \
  -e GITLAB_TOKEN="<your-token>" \
  -e OBS_URL="http://localhost:4455" \
  intewell-webhook-server:v3.8
```

#### 3. CI模板 - build job中触发webhook

```yaml
build:
  stage: build
  image: alpine:latest
  script:
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
```

## Pitfalls

### 1. webhook payload缺少必需字段

**错误**: webhook-server返回`400 Bad Request`

**原因**: payload缺少`before`、`user_name`、`commits`字段

**解决**: 确保payload包含所有必需字段

### 2. Runner使用bridge网络

**错误**: Runner无法访问webhook-server

**原因**: Runner使用默认bridge网络，无法访问宿主机服务

**解决**: Runner必须使用`host`网络模式

### 3. webhook-server使用bridge网络

**错误**: webhook-server端口不在宿主机监听

**原因**: webhook-server使用bridge网络，端口未映射

**解决**: webhook-server必须使用`host`网络模式

## 优点

- 绕过GitLab容器的网络限制
- 不需要修改GitLab配置
- 完全自动化，用户只需git push

## 相关文件

- CI模板: `.gitlab-ci.yml`
- webhook-server代码: `webhook-server/app.py`
- Runner配置: `/srv/gitlab-runner/config/config.toml`