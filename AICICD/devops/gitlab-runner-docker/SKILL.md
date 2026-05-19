---
name: gitlab-runner-docker
description: Deploy and troubleshoot GitLab Runner with Docker executor on Linux. Covers registration, CI job token signing key fix, network_mode=host for job containers, tag matching, and Pipeline debugging.
tags: [gitlab, runner, docker, ci, pipeline, executor, debug]
---

# GitLab Runner Docker Executor 部署与调试

部署 GitLab Runner 使用 Docker executor，解决常见问题使 Pipeline 正常运行。

## Triggers

- 部署 GitLab Runner 连接 GitLab 实例
- Pipeline jobs 一直 pending，Runner 不拉取
- Runner 执行 job 时 GitLab 返回 500 错误
- Job 容器无法访问宿主机服务
- 需要通过 API 管理 Runner 配置

## Quick Setup

### 1. 启动 Runner 容器

```bash
docker run -d \
  --name gitlab-runner \
  --restart unless-stopped \
  -v /path/to/configs/gitlab:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
```

### 2. 注册 Runner

```bash
docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://GITLAB_HOST:8080" \
  --token "glrt-xxx" \
  --executor "docker" \
  --docker-image "python:3.11-slim" \
  --docker-privileged
```

### 3. 配置 network_mode=host

**关键**: Linux 上 job 容器默认使用 bridge 网络，无法访问宿主机服务。

```bash
# 编辑 Runner 配置
docker exec gitlab-runner sh -c "cat >> /etc/gitlab-runner/config.toml << EOF

[runners.docker]
  network_mode = \"host\"
EOF"
docker restart gitlab-runner
```

配置后 CI 变量使用 `localhost` URL：
```yaml
variables:
  OBS_API_URL: "http://localhost:4455"
  SYNC_URL: "http://localhost:8090"
```

## Common Pitfalls

### 1. CI Job Token Signing Key 未设置 (GitLab 18.x)

**Symptom**: Runner 执行 job 时 GitLab 返回 `500 Internal Server Error`，错误在 `PATCH /api/v4/jobs/X/trace`

**Root cause**: GitLab 18.x 初始化时 `ci_job_token_signing_key` 未自动生成

**Fix** (自动化脚本):
```bash
# 创建修复脚本
docker exec gitlab gitlab-rails runner "
require 'openssl'
rsa_key = OpenSSL::PKey::RSA.new(2048).to_pem
key_provider = Gitlab::Encryption::KeyProvider[:db_key_base_32]
encryption_key = key_provider.encryption_key.secret
iv = OpenSSL::Random.random_bytes(12)
encrypted = Encryptor.encrypt(value: rsa_key, key: encryption_key, iv: iv, algorithm: 'aes-256-gcm')
encrypted_hex = encrypted.unpack1('H*')
iv_hex = iv.unpack1('H*')
conn = ActiveRecord::Base.connection
conn.execute(\"UPDATE application_settings SET encrypted_ci_job_token_signing_key = decode('#{encrypted_hex}', 'hex'), encrypted_ci_job_token_signing_key_iv = decode('#{iv_hex}', 'hex')\")
"
docker restart gitlab
```

**验证**:
```bash
docker exec gitlab gitlab-rails runner "
setting = ApplicationSetting.current
puts setting.ci_job_token_signing_key.present? ? 'SUCCESS' : 'FAILED'
"
```

### 2. Runner Tags 不匹配

**Symptom**: Pipeline jobs 一直 pending，Runner online 但不拉取 job

**Root cause**: CI YAML 中 `tags: [test]` 但 Runner 没有对应 tag，或 Runner 有 tag 但 job 没有 tag 且 `run_untagged=false`

**Fix**:
```bash
# 方案A: 让 Runner 接受无 tag 的 job (推荐)
GITLAB_TOKEN=xxx
curl -s -X PUT "http://localhost:8080/api/v4/runners/2" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -d "run_untagged=true"

# 方案B: 给 Runner 添加 tag
curl -s -X PUT "http://localhost:8080/api/v4/runners/2" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -d "tag_list[]=test"

# 方案C: CI YAML 不指定 tags (让 untagged runner 拾取)
# 删除 tags: [test] 行
```

### 3. Job 容器无法访问宿主机服务

**Symptom**: CI job 中 curl 连接宿主机服务失败 "Connection refused"

**Root cause**: Docker bridge 网络隔离，`host.docker.internal` 仅在 Docker Desktop (Mac/Windows) 可用，Linux 上不可用

**Fix**: 配置 Runner 使用 host 网络:
```toml
[[runners]]
  [runners.docker]
    network_mode = "host"
```

或添加 extra_hosts:
```toml
[runners.docker]
  extra_hosts = ["host.docker.internal:host-gateway"]
```

**重要 (2026-05-19)**: Runner 配置 `network_mode = "host"` 后，可以访问宿主机上的所有服务。这对于解决 GitLab webhook internal error 问题至关重要 —— Runner 可以在 build job 中调用 webhook-server。

**Runner 容器本身也建议使用 host 网络**:
```bash
docker run -d --name gitlab-runner --network host \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
```

**完整配置文件示例 (host网络模式)**:
```toml
concurrent = 4
check_interval = 0

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

**配置文件备份路径**: `/home/nando/AICICD/deployments/docker-compose/configs/gitlab/config.toml`

### 3a. GitLab Runner 配置文件丢失恢复

**Symptom**: Runner 日志显示 `Failed to load config stat /etc/gitlab-runner/config.toml: no such file or directory`

**Root cause**: 修改 Runner 网络模式或重建容器时配置文件丢失

**Fix**: 从备份恢复配置文件:
```bash
# 备份路径: /home/nando/AICICD/deployments/docker-compose/configs/gitlab/config.toml
docker run --rm \
  -v /home/nando/AICICD/deployments/docker-compose/configs/gitlab:/config \
  -v /srv/gitlab-runner/config:/output \
  alpine:latest sh -c 'cp /config/config.toml /output/config.toml'

# 重启 Runner
docker restart gitlab-runner
```

**验证**: `docker logs gitlab-runner 2>&1 | tail -5` 应显示 `Configuration loaded`

### 4. Runner max_builds=0 / contacted_at=None

**Symptom**: Runner API 显示 online 但 `max_builds=0`, `contacted_at=None`，Pipeline 直接 failed 无 jobs

**Root cause**: Runner 与 GitLab 通信异常，可能 token 过期或配置损坏

**Fix**: 重新注册 Runner:
```bash
# 1. 注销旧 Runner
docker exec gitlab-runner gitlab-runner unregister --all-runners

# 2. 从 GitLab 获取新 token (Settings > CI/CD > Runners > New runner)

# 3. 重新注册
docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://GITLAB_HOST:8080" \
  --token "NEW_TOKEN" \
  --executor "docker" \
  --docker-image "python:3.11-slim" \
  --docker-privileged

# 4. 添加 network_mode=host
# 编辑 config.toml
```

### 5. Pipeline 直接 failed 无 jobs 创建

**Symptom**: `POST /api/v4/projects/:id/pipeline` 返回 pipeline created 但 status=failed，jobs 列表为空

**Root cause**: `.gitlab-ci.yml` YAML 语法错误

**Debug**:
```bash
# 检查 YAML 错误
curl -s -X POST "http://localhost:8080/api/v4/projects/1/pipeline?ref=main" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | python3 -c "
import sys, json
p = json.loads(sys.stdin.read())
if p.get('message'):
    print('YAML Error:', p['message'])
else:
    print(f'Pipeline #{p.get(\"id\")} status={p.get(\"status\")}')"
```

常见 YAML 错误:
- `${VAR}` 在 Python 字符串中被替换为空 → 用 base64 编码上传
- `*` 在 YAML 中是别名符号 → 用引号包裹或块标量 `|`
- 长命令行含 `$()` 嵌套 → 用 `|` 块标量

### 6. git clone 返回 503

**Symptom**: `git clone` 失败但 GitLab API 正常

**Root cause**: GitLab nginx 未完全就绪，git 协议需要更多服务

**Fix**: 使用 GitLab REST API 直接操作文件:
```bash
# base64 编码上传（避免变量替换和特殊字符问题）
CI_B64=$(base64 -w 0 /tmp/ci.yml)
curl -s -X PUT "http://localhost:8080/api/v4/projects/1/repository/files/.gitlab-ci.yml" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  -d "{\"branch\":\"main\",\"content\":\"$CI_B64\",\"encoding\":\"base64\",\"commit_message\":\"Update CI\"}"
```

## Runner 管理 API

```bash
TOKEN=xxx

# 列出所有 Runners
curl -s "http://localhost:8080/api/v4/runners" --header "PRIVATE-TOKEN: $TOKEN" | python3 -c "
import sys, json
for r in json.loads(sys.stdin.read()):
    print(f'Runner #{r[\"id\"]}: {r[\"status\"]} tags={r[\"tag_list\"]} online={r[\"online\"]} untagged={r[\"run_untagged\"]}')"

# 更新 Runner 配置
curl -s -X PUT "http://localhost:8080/api/v4/runners/2" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  -d "run_untagged=true&tag_list[]=test&tag_list[]=rpm"

# 删除 Runner
curl -s -X DELETE "http://localhost:8080/api/v4/runners/2" \
  --header "PRIVATE-TOKEN: $TOKEN"
```

## Pipeline 调试 API

```bash
PROJECT_ID=1

# 触发 Pipeline
curl -s -X POST "http://localhost:8080/api/v4/projects/$PROJECT_ID/pipeline?ref=main" \
  --header "PRIVATE-TOKEN: $TOKEN"

# 查看 Pipeline jobs
curl -s "http://localhost:8080/api/v4/projects/$PROJECT_ID/pipelines/PIPELINE_ID/jobs" \
  --header "PRIVATE-TOKEN: $TOKEN" | python3 -c "
import sys, json
for j in json.loads(sys.stdin.read()):
    print(f'Job #{j[\"id\"]}: {j[\"name\"]} status={j[\"status\"]} stage={j[\"stage\"]}')"

# 查看 job 日志
curl -s "http://localhost:8080/api/v4/projects/$PROJECT_ID/jobs/JOB_ID/trace" \
  --header "PRIVATE-TOKEN: $TOKEN"

# 重试失败的 job
curl -s -X POST "http://localhost:8080/api/v4/projects/$PROJECT_ID/jobs/JOB_ID/retry" \
  --header "PRIVATE-TOKEN: $TOKEN"
```

## Runner 配置文件参考

```toml
concurrent = 4
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "runner-name"
  url = "http://GITLAB_HOST:8080"
  id = 2
  token = "glrt-xxx"
  executor = "docker"
  [runners.docker]
    tls_verify = false
    image = "python:3.11-slim"
    privileged = true
    network_mode = "host"
    volumes = ["/cache"]
```

**Note**: `concurrent = 4` supports parallel Pipelines. Default is 1 which serializes all jobs.

## Additional Pitfalls

### Pitfall 7: Runner Not Enabled for New Projects

**Symptom**: New GitLab project's Pipeline jobs stay `pending` forever. Runner shows `online=true` but never picks up the job.

**Root cause**: When a Runner is registered, it's only enabled for the project specified during registration. New projects must explicitly enable the Runner.

**Fix**: Enable the Runner for the new project via API:
```bash
curl -s --header "PRIVATE-TOKEN: $TOKEN" -X POST \
  "http://localhost:8080/api/v4/projects/{new_project_id}/runners" \
  -H "Content-Type: application/json" \
  -d '{"runner_id": 2}'
```

**Pitfall**: After enabling, you may need to restart the Runner container: `docker restart gitlab-runner`

**Prevention**: Use a **shared Runner** (registered without `--project-id`) so it's available to all projects by default.

### Pitfall 8: Runner concurrent=1 Blocks Parallel Pipelines

**Symptom**: Multiple Pipelines run serially — one Pipeline completes before the next starts.

**Root cause**: Default `config.toml` has `concurrent = 1`.

**Fix**: Increase the concurrent limit:
```bash
docker exec gitlab-runner sed -i 's/concurrent = 1/concurrent = 4/' /etc/gitlab-runner/config.toml
docker restart gitlab-runner
```

### Pitfall 9: Runner pull_policy=always Slows Down Builds

**Symptom**: CI job `build` stage takes 400+ seconds, logs show "Pulling docker image registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper..." for most of the time.

**Root cause**: GitLab Runner default `pull_policy = "always"` forces pulling images from registry every job, even if the image already exists locally. Network latency (especially from China to GitLab.com registry) causes significant delays.

**Fix**: Change pull_policy to "if-not-present":
```bash
# Add pull_policy to config.toml
docker exec gitlab-runner bash -c 'cat >> /etc/gitlab-runner/config.toml << EOF

[runners.docker]
  pull_policy = ["if-not-present"]
EOF'

# Or use sed if section exists
docker exec gitlab-runner sed -i '/\[runners.docker\]/a\  pull_policy = ["if-not-present"]' /etc/gitlab-runner/config.toml

docker restart gitlab-runner
```

**Verification**: After fix, build job should complete in ~30-70 seconds instead of 400+ seconds.

**Important**: After `docker system prune -a`, the `gitlab-runner-helper` image may be deleted. Re-pull it:
```bash
docker pull registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v18.11.2
```

### Pitfall 10: GitLab Runner Helper Image Deleted by docker system prune

**Symptom**: After running `docker system prune -a -f`, CI jobs fail with "failed to pull image registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v18.11.2"

**Root cause**: `docker system prune -a` deletes all images not currently used by running containers, including GitLab Runner helper images that are needed when jobs execute.

**Fix**:
```bash
# Re-pull the helper image
docker pull registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v18.11.2
```

**Prevention**: Use `docker image prune` (without `-a`) to only clean dangling images (`<none>` tags), not all unused images.

## Related Skills

- `cicd-pipeline-services` - CI/CD 微服务实现
- `obs-build-service` - OBS 构建服务部署
