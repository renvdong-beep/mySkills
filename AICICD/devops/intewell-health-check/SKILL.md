---
name: intewell-health-check
description: Intewell CI/CD项目自动化巡检和运维。检查所有服务状态、磁盘空间、OBS构建队列、GitLab Runner状态等，并提供修复建议。
tags:
  - intewell
  - health-check
  - monitoring
  - maintenance
  - automation
---

# Intewell CI/CD 自动化巡检

## 功能

自动化检查Intewell CI/CD项目的所有服务状态：
1. GitLab服务状态
2. GitLab Runner状态
3. OBS服务状态（API、scheduler、worker）
4. webhook-server状态
5. sync-service状态
6. quality-gate状态
7. 磁盘空间检查
8. Docker容器状态

## 使用方法

```bash
# 运行巡检脚本
/home/nando/AICICD/scripts/health-check.sh

# 或使用详细模式
/home/nando/AICICD/scripts/health-check.sh --verbose
```

## 巡检脚本

```bash
#!/bin/bash
# health-check.sh - Intewell CI/CD 健康检查脚本

set -e

PROJECT_DIR="/home/nando/AICICD"
LOG_FILE="$PROJECT_DIR/logs/health-check-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$PROJECT_DIR/logs"

echo "========================================"
echo "Intewell CI/CD 健康检查"
echo "时间: $(date)"
echo "========================================"

# 1. 检查Docker服务
echo ""
echo "【1. Docker服务】"
if systemctl is-active docker > /dev/null 2>&1; then
    echo "  ✓ Docker服务运行中"
else
    echo "  ✗ Docker服务未运行"
fi

# 2. 检查容器状态
echo ""
echo "【2. 容器状态】"
CONTAINERS="gitlab gitlab-runner obs-server-test webhook-server sync-service quality-gate"
for c in $CONTAINERS; do
    STATUS=$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null || echo "not_found")
    if [ "$STATUS" = "running" ]; then
        echo "  ✓ $c: running"
    else
        echo "  ✗ $c: $STATUS"
    fi
done

# 3. 检查GitLab
echo ""
echo "【3. GitLab服务】"
GITLAB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "000")
if [ "$GITLAB_STATUS" = "200" ] || [ "$GITLAB_STATUS" = "302" ]; then
    echo "  ✓ GitLab Web: $GITLAB_STATUS"
else
    echo "  ✗ GitLab Web: $GITLAB_STATUS"
fi

# 4. 检查GitLab Runner
echo ""
echo "【4. GitLab Runner】"
TOKEN="glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8"
RUNNER_STATUS=$(curl -s "http://localhost:8080/api/v4/runners" --header "PRIVATE-TOKEN: $TOKEN" 2>/dev/null | \
    python3 -c "import sys,json; runners=json.load(sys.stdin); print('online' if any(r['status']=='online' for r in runners) else 'offline')" 2>/dev/null || echo "error")
if [ "$RUNNER_STATUS" = "online" ]; then
    echo "  ✓ Runner: online"
else
    echo "  ✗ Runner: $RUNNER_STATUS"
fi

# 5. 检查OBS服务
echo ""
echo "【5. OBS服务】"

# OBS API
OBS_API=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5352/ 2>/dev/null || echo "000")
if [ "$OBS_API" = "200" ]; then
    echo "  ✓ OBS API: $OBS_API"
else
    echo "  ✗ OBS API: $OBS_API"
fi

# OBS Scheduler
SCHEDULER_COUNT=$(docker exec obs-server-test ps aux 2>/dev/null | grep -c "bs_sched" || echo "0")
if [ "$SCHEDULER_COUNT" -ge 2 ]; then
    echo "  ✓ OBS Scheduler: $SCHEDULER_COUNT 个进程"
else
    echo "  ✗ OBS Scheduler: 仅 $SCHEDULER_COUNT 个进程 (需要2个)"
fi

# OBS Worker
WORKER_COUNT=$(docker exec obs-server-test ps aux 2>/dev/null | grep -c "bs_worker" || echo "0")
if [ "$WORKER_COUNT" -ge 2 ]; then
    echo "  ✓ OBS Worker: $WORKER_COUNT 个进程"
else
    echo "  ⚠ OBS Worker: 仅 $WORKER_COUNT 个进程"
fi

# 6. 检查webhook-server
echo ""
echo "【6. webhook-server】"
WEBHOOK_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8091/ 2>/dev/null || echo "000")
if [ "$WEBHOOK_STATUS" = "404" ] || [ "$WEBHOOK_STATUS" = "200" ]; then
    echo "  ✓ webhook-server: $WEBHOOK_STATUS"
else
    echo "  ✗ webhook-server: $WEBHOOK_STATUS"
fi

# 7. 检查sync-service
echo ""
echo "【7. sync-service】"
SYNC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/ 2>/dev/null || echo "000")
if [ "$SYNC_STATUS" = "200" ] || [ "$SYNC_STATUS" = "404" ]; then
    echo "  ✓ sync-service: $SYNC_STATUS"
else
    echo "  ✗ sync-service: $SYNC_STATUS"
fi

# 8. 检查quality-gate
echo ""
echo "【8. quality-gate】"
QG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ 2>/dev/null || echo "000")
if [ "$QG_STATUS" = "200" ] || [ "$QG_STATUS" = "404" ]; then
    echo "  ✓ quality-gate: $QG_STATUS"
else
    echo "  ✗ quality-gate: $QG_STATUS"
fi

# 9. 检查磁盘空间
echo ""
echo "【9. 磁盘空间】"
ROOT_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
HOME_USAGE=$(df -h /home | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$ROOT_USAGE" -lt 80 ]; then
    echo "  ✓ 根分区 /: ${ROOT_USAGE}%"
else
    echo "  ⚠ 根分区 /: ${ROOT_USAGE}% (接近满)"
fi

if [ "$HOME_USAGE" -lt 80 ]; then
    echo "  ✓ Home分区 /home: ${HOME_USAGE}%"
else
    echo "  ⚠ Home分区 /home: ${HOME_USAGE}%"
fi

# 10. 检查最近的Pipeline
echo ""
echo "【10. 最近Pipeline】"
LATEST_PIPELINE=$(curl -s "http://localhost:8080/api/v4/projects/1/pipelines?per_page=1" \
    --header "PRIVATE-TOKEN: $TOKEN" 2>/dev/null | \
    python3 -c "import sys,json; p=json.load(sys.stdin); print(f'#{p[0][\"id\"]} {p[0][\"status\"]}' if p else 'none')" 2>/dev/null || echo "error")
echo "  最新Pipeline: $LATEST_PIPELINE"

# 总结
echo ""
echo "========================================"
echo "【巡检完成】"
echo "========================================"

# 返回状态码
if docker ps | grep -q "gitlab.*Up" && \
   docker ps | grep -q "gitlab-runner.*Up" && \
   docker ps | grep -q "obs-server-test.*Up"; then
    echo "状态: ✓ 核心服务正常"
    exit 0
else
    echo "状态: ✗ 存在异常服务"
    exit 1
fi
```

## 检查项目

| 检查项 | 正常状态 | 异常处理 |
|-------|---------|---------|
| Docker服务 | active | `systemctl start docker` |
| GitLab容器 | running | `docker start gitlab` |
| GitLab Runner容器 | running | `docker start gitlab-runner` |
| OBS容器 | running | `docker start obs-server-test` |
| webhook-server容器 | running | `docker start webhook-server` |
| OBS Scheduler | 2个进程 | `docker exec obs-server-test perl /usr/lib/obs/server/bs_sched x86_64 --daemonize` |
| GitLab Web | 200/302 | 检查GitLab日志 |
| OBS API | 200 | 检查OBS日志 |
| 根分区磁盘 | <80% | 清理旧文件 |
| Home分区磁盘 | <80% | 清理旧文件 |

## 自动修复

当发现异常时，可以运行修复脚本：

```bash
# 修复OBS服务
/home/nando/AICICD/scripts/check-and-fix-obs.sh

# 恢复CI/CD环境
/home/nando/AICICD/scripts/restore-cicd.sh

# 修复GitLab Runner
/home/nando/AICICD/scripts/fix-gitlab-runner.sh
```

## 定时巡检

可以配置cron定时任务：

```bash
# 每小时巡检一次
0 * * * * /home/nando/AICICD/scripts/health-check.sh >> /home/nando/AICICD/logs/health-check.log 2>&1

# 每天凌晨2点清理日志
0 2 * * * find /home/nando/AICICD/logs -name "*.log" -mtime +7 -delete
```

## Pitfalls

### 1. OBS Scheduler进程丢失

**现象**: OBS构建一直scheduled

**解决**: 运行 `check-and-fix-obs.sh` 或手动启动scheduler

### 2. GitLab Runner配置丢失

**现象**: Runner日志显示 `Failed to load config`

**解决**: 从备份恢复配置文件

### 3. 磁盘空间不足

**现象**: 根分区使用率>90%

**解决**: 
```bash
# 清理Docker
docker system prune -f

# 清理旧日志
find /var/log -name "*.log" -mtime +30 -delete
```

## 相关Skills

- intewell-project-context: 项目上下文
- obs-build-service: OBS服务调试
- gitlab-runner-docker: Runner调试