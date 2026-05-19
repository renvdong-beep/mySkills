---
name: intewell-project-migration
description: Intewell CI/CD项目整体迁移skill。用于将整个项目（脚本、文档、代码、容器、数据、镜像）迁移到另一台服务器。包含完整的迁移步骤、检查清单和验证方法。
tags:
  - intewell
  - migration
  - backup
  - restore
  - deployment
---

# Intewell CI/CD 项目迁移指南

## 概述

本skill用于将Intewell CI/CD项目从一台服务器完整迁移到另一台服务器。

## 迁移内容清单

| 类别 | 内容 | 大小估算 |
|------|------|---------|
| 项目代码 | `/home/nando/AICICD/` | ~500MB |
| Docker镜像 | GitLab, OBS, Runner等 | ~5GB |
| Docker容器数据 | 挂载卷数据 | ~10GB |
| OBS数据 | `/home/nando/AICICD/data/obs/` | ~2GB |
| RPM仓库 | `/home/nando/AICICD/data/repos/` | ~1GB |
| Skills | `~/.hermes/skills/` | ~50MB |
| 配置文件 | 各种服务配置 | ~10MB |

## 迁移步骤

### Phase 1: 准备工作（源服务器）

#### 1.1 检查服务状态

```bash
# 运行健康检查
/home/nando/AICICD/scripts/health-check.sh

# 确认所有服务正常
```

#### 1.2 停止服务

```bash
# 停止所有容器
docker stop gitlab gitlab-runner obs-server-test webhook-server sync-service quality-gate

# 停止Docker服务（可选）
systemctl stop docker
```

#### 1.3 导出Docker镜像

```bash
# 创建镜像导出目录
mkdir -p /home/nando/AICICD-migration/images

# 导出镜像
docker save gitlab/gitlab-ce:latest > /home/nando/AICICD-migration/images/gitlab-ce.tar
docker save gitlab/gitlab-runner:latest > /home/nando/AICICD-migration/images/gitlab-runner.tar
docker save intewell-obs-server:latest > /home/nando/AICICD-migration/images/obs-server.tar
docker save intewell-webhook-server:v3.8 > /home/nando/AICICD-migration/images/webhook-server.tar
docker save intewell-sync-service:latest > /home/nando/AICICD-migration/images/sync-service.tar
docker save intewell-quality-gate:latest > /home/nando/AICICD-migration/images/quality-gate.tar

# 查看镜像大小
ls -lh /home/nando/AICICD-migration/images/
```

#### 1.4 导出容器配置

```bash
# 创建配置导出目录
mkdir -p /home/nando/AICICD-migration/configs

# 导出容器配置
for container in gitlab gitlab-runner obs-server-test webhook-server; do
    docker inspect $container > /home/nando/AICICD-migration/configs/${container}-config.json
done

# 导出GitLab Runner配置
cp /srv/gitlab-runner/config/config.toml /home/nando/AICICD-migration/configs/gitlab-runner-config.toml

# 导出OBS配置
docker exec obs-server-test cat /etc/obs/obs-server.conf > /home/nando/AICICD-migration/configs/obs-server.conf
```

#### 1.5 打包项目文件

```bash
# 打包项目目录（排除临时文件）
tar --exclude='*.log' \
    --exclude='__pycache__' \
    --exclude='.git' \
    --exclude='tmp/*' \
    -czvf /home/nando/AICICD-migration/AICICD-project.tar.gz \
    /home/nando/AICICD/

# 打包数据目录
tar -czvf /home/nando/AICICD-migration/AICICD-data.tar.gz \
    /home/nando/AICICD/data/

# 打包Skills
tar -czvf /home/nando/AICICD-migration/hermes-skills.tar.gz \
    ~/.hermes/skills/
```

#### 1.6 导出GitLab数据

```bash
# GitLab备份（如果使用内置备份功能）
docker exec gitlab gitlab-backup create

# 复制备份文件
cp /srv/gitlab/data/backups/*.tar /home/nando/AICICD-migration/gitlab-backup.tar

# 导出GitLab配置
cp /srv/gitlab/config/gitlab.rb /home/nando/AICICD-migration/configs/gitlab.rb
cp /srv/gitlab/config/gitlab-secrets.json /home/nando/AICICD-migration/configs/gitlab-secrets.json
```

#### 1.7 创建迁移清单

```bash
# 创建清单文件
cat > /home/nando/AICICD-migration/MANIFEST.md << 'EOF'
# Intewell CI/CD 迁移清单

## 日期: $(date)

## 源服务器信息
- IP: $(hostname -I | awk '{print $1}')
- 主机名: $(hostname)
- 系统: $(cat /etc/os-release | grep PRETTY_NAME)

## 文件清单
| 文件 | 大小 | 说明 |
|------|------|------|
| AICICD-project.tar.gz | X MB | 项目代码和脚本 |
| AICICD-data.tar.gz | X MB | 数据目录 |
| hermes-skills.tar.gz | X MB | Hermes Skills |
| images/*.tar | X GB | Docker镜像 |
| configs/*.json | X KB | 容器配置 |
| gitlab-backup.tar | X MB | GitLab备份 |

## 服务端口
| 服务 | 端口 |
|------|------|
| GitLab | 8080 |
| OBS API | 5352 |
| OBS HTTP | 5252 |
| webhook-server | 8091 |
| sync-service | 8090 |
| quality-gate | 8081 |

## 验证命令
./scripts/health-check.sh
EOF

# 计算文件大小并更新清单
for f in /home/nando/AICICD-migration/*.tar.gz /home/nando/AICICD-migration/images/*.tar; do
    echo "$(basename $f): $(du -h $f | cut -f1)"
done
```

### Phase 2: 传输文件

#### 2.1 使用SCP传输

```bash
# 传输到目标服务器
scp -r /home/nando/AICICD-migration/ user@target-server:/home/user/

# 或使用rsync（更快）
rsync -avz --progress /home/nando/AICICD-migration/ user@target-server:/home/user/AICICD-migration/
```

#### 2.2 使用压缩传输（网络慢时）

```bash
# 先压缩整个迁移目录
tar -czvf /home/nando/AICICD-migration-full.tar.gz /home/nando/AICICD-migration/

# 分割大文件（如果需要）
split -b 1G /home/nando/AICICD-migration-full.tar.gz AICICD-migration-part-

# 传输分割文件
scp AICICD-migration-part-* user@target-server:/home/user/

# 在目标服务器合并
cat AICICD-migration-part-* > AICICD-migration-full.tar.gz
tar -xzvf AICICD-migration-full.tar.gz
```

### Phase 3: 目标服务器部署

#### 3.1 系统要求检查

```bash
# 检查系统版本（需要openEuler 24.03 LTS SP1）
cat /etc/os-release

# 检查磁盘空间（需要至少50GB）
df -h / /home

# 检查Docker
docker --version
systemctl status docker
```

#### 3.2 解压文件

```bash
# 创建项目目录
mkdir -p /home/nando/AICICD

# 解压项目文件
tar -xzvf AICICD-migration/AICICD-project.tar.gz -C /

# 解压数据文件
tar -xzvf AICICD-migration/AICICD-data.tar.gz -C /

# 解压Skills
mkdir -p ~/.hermes/skills
tar -xzvf AICICD-migration/hermes-skills.tar.gz -C ~/.hermes/
```

#### 3.3 导入Docker镜像

```bash
# 导入所有镜像
for img in /home/user/AICICD-migration/images/*.tar; do
    docker load -i $img
done

# 验证镜像
docker images
```

#### 3.4 恢复GitLab

```bash
# 创建GitLab目录
mkdir -p /srv/gitlab/config /srv/gitlab/data /srv/gitlab/logs

# 复制配置
cp AICICD-migration/configs/gitlab.rb /srv/gitlab/config/
cp AICICD-migration/configs/gitlab-secrets.json /srv/gitlab/config/

# 启动GitLab容器
docker run -d \
  --name gitlab \
  --hostname $(hostname) \
  -p 8080:8080 \
  -p 22:22 \
  -v /srv/gitlab/config:/etc/gitlab \
  -v /srv/gitlab/data:/var/opt/gitlab \
  -v /srv/gitlab/logs:/var/log/gitlab \
  gitlab/gitlab-ce:latest

# 等待GitLab启动（约5分钟）
sleep 300

# 恢复GitLab备份
docker exec -t gitlab gitlab-backup restore BACKUP=timestamp
```

#### 3.5 恢复OBS服务

```bash
# 使用项目脚本启动OBS
/home/nando/AICICD/scripts/setup-obs-server.sh

# 或手动启动
docker run -d \
  --name obs-server-test \
  --privileged \
  --network host \
  -v /home/nando/AICICD/data/obs:/var/obs \
  -v /home/nando/AICICD/data/obs-srv:/srv/obs \
  intewell-obs-server:latest

# 启动scheduler
docker exec obs-server-test perl /usr/lib/obs/server/bs_sched x86_64 --daemonize
docker exec obs-server-test perl /usr/lib/obs/server/bs_sched aarch64 --daemonize
```

#### 3.6 恢复GitLab Runner

```bash
# 创建Runner目录
mkdir -p /srv/gitlab-runner/config

# 复制配置
cp AICICD-migration/configs/gitlab-runner-config.toml /srv/gitlab-runner/config/config.toml

# 启动Runner
docker run -d \
  --name gitlab-runner \
  --network host \
  --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest
```

#### 3.7 恢复webhook-server

```bash
# 启动webhook-server
docker run -d \
  --name webhook-server \
  --network host \
  -e GITLAB_URL="http://localhost:8080" \
  -e GITLAB_TOKEN="glpat-xxx" \
  -e OBS_URL="http://localhost:4455" \
  intewell-webhook-server:v3.8
```

#### 3.8 恢复其他服务

```bash
# sync-service
docker run -d \
  --name sync-service \
  --network host \
  -v /home/nando/AICICD/data/repos:/data/repos \
  intewell-sync-service:latest

# quality-gate
docker run -d \
  --name quality-gate \
  --network host \
  intewell-quality-gate:latest
```

### Phase 4: 验证迁移

#### 4.1 运行健康检查

```bash
/home/nando/AICICD/scripts/health-check.sh
```

#### 4.2 验证GitLab

```bash
# 检查GitLab Web
curl http://localhost:8080/

# 检查项目是否存在
curl -H "PRIVATE-TOKEN: glpat-xxx" \
  http://localhost:8080/api/v4/projects
```

#### 4.3 验证OBS

```bash
# 检查OBS API
curl http://localhost:5352/

# 检查项目
curl -u Admin:admin123 http://localhost:5352/source/home:Admin
```

#### 4.4 验证Pipeline

```bash
# 创建测试包验证全链路
/home/nando/AICICD/scripts/add-test-package.sh test-migration-verify
```

#### 4.5 验证ISO构建

```bash
# 如果有ISO构建配置，验证Packer
cd /home/nando/Intewell-unified-packer
./_internal/build_in_docker.sh standard_x86_64.json
```

## 迁移脚本

### 一键迁移脚本

```bash
#!/bin/bash
# migrate-project.sh - Intewell项目一键迁移脚本
#
# 用法:
#   ./migrate-project.sh prepare          # 准备迁移包
#   ./migrate-project.sh transfer <ip>    # 传输到目标服务器
#   ./migrate-project.sh restore          # 在目标服务器恢复
#
# 作者: nando
# 日期: 2026-05-19

set -e

PROJECT_DIR="/home/nando/AICICD"
MIGRATION_DIR="/home/nando/AICICD-migration"

case "$1" in
    prepare)
        echo "=== 准备迁移包 ==="
        
        # 停止服务
        echo "停止服务..."
        docker stop gitlab gitlab-runner obs-server-test webhook-server 2>/dev/null || true
        
        # 创建迁移目录
        mkdir -p $MIGRATION_DIR/images $MIGRATION_DIR/configs
        
        # 导出镜像
        echo "导出Docker镜像..."
        docker save gitlab/gitlab-ce:latest > $MIGRATION_DIR/images/gitlab-ce.tar
        docker save gitlab/gitlab-runner:latest > $MIGRATION_DIR/images/gitlab-runner.tar
        docker save intewell-obs-server:latest > $MIGRATION_DIR/images/obs-server.tar
        docker save intewell-webhook-server:v3.8 > $MIGRATION_DIR/images/webhook-server.tar
        
        # 打包项目
        echo "打包项目文件..."
        tar --exclude='*.log' --exclude='__pycache__' --exclude='.git' \
            -czvf $MIGRATION_DIR/AICICD-project.tar.gz $PROJECT_DIR/
        
        # 打包数据
        echo "打包数据文件..."
        tar -czvf $MIGRATION_DIR/AICICD-data.tar.gz $PROJECT_DIR/data/
        
        # 打包Skills
        echo "打包Skills..."
        tar -czvf $MIGRATION_DIR/hermes-skills.tar.gz ~/.hermes/skills/
        
        # 导出配置
        echo "导出容器配置..."
        docker inspect gitlab > $MIGRATION_DIR/configs/gitlab-config.json 2>/dev/null || true
        cp /srv/gitlab-runner/config/config.toml $MIGRATION_DIR/configs/ 2>/dev/null || true
        
        echo "=== 迁移包准备完成 ==="
        echo "位置: $MIGRATION_DIR"
        du -sh $MIGRATION_DIR/*
        ;;
        
    transfer)
        TARGET_IP=$2
        if [ -z "$TARGET_IP" ]; then
            echo "错误: 请指定目标服务器IP"
            echo "用法: ./migrate-project.sh transfer <ip>"
            exit 1
        fi
        
        echo "=== 传输到目标服务器 $TARGET_IP ==="
        rsync -avz --progress $MIGRATION_DIR/ nando@$TARGET_IP:/home/nando/AICICD-migration/
        echo "=== 传输完成 ==="
        ;;
        
    restore)
        echo "=== 恢复项目 ==="
        
        # 解压项目
        echo "解压项目文件..."
        tar -xzvf $MIGRATION_DIR/AICICD-project.tar.gz -C /
        
        # 解压数据
        echo "解压数据文件..."
        tar -xzvf $MIGRATION_DIR/AICICD-data.tar.gz -C /
        
        # 解压Skills
        echo "解压Skills..."
        mkdir -p ~/.hermes/skills
        tar -xzvf $MIGRATION_DIR/hermes-skills.tar.gz -C ~/.hermes/
        
        # 导入镜像
        echo "导入Docker镜像..."
        for img in $MIGRATION_DIR/images/*.tar; do
            docker load -i $img
        done
        
        # 启动服务
        echo "启动服务..."
        /home/nando/AICICD/scripts/restore-cicd.sh
        
        # 健康检查
        echo "运行健康检查..."
        /home/nando/AICICD/scripts/health-check.sh
        
        echo "=== 恢复完成 ==="
        ;;
        
    *)
        echo "用法:"
        echo "  ./migrate-project.sh prepare          # 准备迁移包"
        echo "  ./migrate-project.sh transfer <ip>    # 传输到目标服务器"
        echo "  ./migrate-project.sh restore          # 在目标服务器恢复"
        exit 1
        ;;
esac
```

## Pitfalls

### 1. GitLab secrets丢失

**问题**: GitLab无法启动或数据无法恢复

**解决**: 必须备份 `gitlab-secrets.json` 文件

### 2. OBS scheduler未启动

**问题**: OBS构建一直scheduled

**解决**: 手动启动scheduler
```bash
docker exec obs-server-test perl /usr/lib/obs/server/bs_sched x86_64 --daemonize
docker exec obs-server-test perl /usr/lib/obs/server/bs_sched aarch64 --daemonize
```

### 3. GitLab Runner配置丢失

**问题**: Runner无法连接GitLab

**解决**: 确保 `config.toml` 文件正确复制

### 4. 磁盘空间不足

**问题**: 解压失败或服务启动失败

**解决**: 目标服务器至少需要50GB可用空间

### 5. 网络问题导致传输中断

**问题**: 大文件传输失败

**解决**: 使用rsync或分割文件传输

## 相关文件

- 迁移脚本: `/home/nando/AICICD/scripts/migrate-project.sh`
- 健康检查: `/home/nando/AICICD/scripts/health-check.sh`
- 环境恢复: `/home/nando/AICICD/scripts/restore-cicd.sh`
- OBS修复: `/home/nando/AICICD/scripts/check-and-fix-obs.sh`

## 相关Skills

- intewell-project-context: 项目上下文
- intewell-health-check: 健康检查
- obs-build-service: OBS服务
- gitlab-runner-docker: Runner配置