# GitLab Runner Docker Executor 调试记录

## CI Job Token Signing Key 修复 (GitLab 18.x)

### 问题
Runner 执行 job 时 GitLab 返回 500 Internal Server Error，错误在 PATCH /api/v4/jobs/X/trace

### 根因
GitLab 18.x 初始化时 ci_job_token_signing_key 未自动生成

### 修复脚本
```bash
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

### 验证
```bash
docker exec gitlab gitlab-rails runner "
setting = ApplicationSetting.current
puts setting.ci_job_token_signing_key.present? ? 'SUCCESS' : 'FAILED'
"
```

## Runner Tag 匹配问题

### 现象
Pipeline #24: Pipeline created 但 0 jobs。Runner online 但不拉取。

### 原因
CI YAML 中 `tags: [test]` 但 Runner 没有 test tag。

### 修复方案优先级
1. 设置 `run_untagged=true` (最简单)
2. 给 Runner 添加对应 tag
3. CI YAML 不指定 tags

## network_mode=host 配置

### 为什么需要
Linux 上 Docker bridge 网络隔离 job 容器与宿主机。`host.docker.internal` 仅在 Docker Desktop (Mac/Windows) 可用。

### 配置方法
```toml
[[runners]]
  executor = "docker"
  [runners.docker]
    network_mode = "host"
```

### CI 变量
使用 localhost URL（因为容器共享宿主机网络）:
```yaml
variables:
  OBS_API_URL: "http://localhost:4455"
  SYNC_URL: "http://localhost:8090"
```

## max_builds=0 问题

### 现象
Runner API 显示 online 但 max_builds=0, contacted_at=None

### 修复
重新注册 Runner（token 可能过期或配置损坏）

## Pipeline 调试流程

1. 检查 Runner 状态: `curl -s http://localhost:8080/api/v4/runners --header "PRIVATE-TOKEN: $TOKEN"`
2. 触发 Pipeline: `curl -s -X POST "http://localhost:8080/api/v4/projects/1/pipeline?ref=main" --header "PRIVATE-TOKEN: $TOKEN"`
3. 查看 jobs: `curl -s "http://localhost:8080/api/v4/projects/1/pipelines/ID/jobs" --header "PRIVATE-TOKEN: $TOKEN"`
4. 查看 job 日志: `curl -s "http://localhost:8080/api/v4/projects/1/jobs/ID/trace" --header "PRIVATE-TOKEN: $TOKEN"`
