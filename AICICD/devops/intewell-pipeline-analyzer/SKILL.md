---
name: intewell-pipeline-analyzer
description: 自动分析Intewell CI/CD Pipeline的6个步骤执行状态，诊断问题并提供修复建议。支持分析build、obs-trigger、obs-wait、sync、quality-gate、update-repo各阶段。
tags:
  - intewell
  - cicd
  - pipeline
  - analysis
  - debugging
---

# Intewell Pipeline Analyzer

## 功能

自动分析Intewell CI/CD Pipeline的6个步骤执行状态：
1. build - 打包源码，触发webhook
2. obs-trigger - 上传到OBS
3. obs-wait - 等待OBS构建
4. sync - 同步RPM
5. quality-gate - 质量检查
6. update-repo - 更新仓库

## 使用方法

### 分析指定Pipeline

```bash
# 设置变量
PIPELINE_ID=231
PROJECT_ID=1
TOKEN="glpat-xxx"

# 运行分析脚本
./analyze-pipeline.sh $PIPELINE_ID $PROJECT_ID $TOKEN
```

### 分析最新Pipeline

```bash
./analyze-pipeline.sh latest $PROJECT_ID $TOKEN
```

## 分析脚本

```bash
#!/bin/bash
# analyze-pipeline.sh - Intewell Pipeline分析脚本

PIPELINE_ID=${1:-latest}
PROJECT_ID=${2:-1}
TOKEN=${3:-"glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8"}
GITLAB_URL="http://localhost:8080"
OBS_API="http://localhost:5352"
OBS_USER="Admin"
OBS_PASSWORD="admin123"

# 获取Pipeline ID
if [ "$PIPELINE_ID" = "latest" ]; then
    PIPELINE_ID=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=1" \
        --header "PRIVATE-TOKEN: $TOKEN" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
fi

echo "========================================"
echo "Pipeline #$PIPELINE_ID 分析报告"
echo "========================================"

# 获取Pipeline状态
PIPELINE_STATUS=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID" \
    --header "PRIVATE-TOKEN: $TOKEN" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")

echo ""
echo "【Pipeline状态】: $PIPELINE_STATUS"

# 获取Jobs状态
echo ""
echo "【Jobs状态】:"
curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/jobs" \
    --header "PRIVATE-TOKEN: $TOKEN" | \
    python3 -c "
import sys,json
jobs = json.load(sys.stdin)
for j in jobs:
    print(f'  {j[\"name\"]}: {j[\"status\"]}')" | sort

# 分析每个Job
echo ""
echo "【详细分析】:"
JOBS=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/jobs" \
    --header "PRIVATE-TOKEN: $TOKEN")

# 1. build job分析
BUILD_ID=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['id'] for j in jobs if j['name']=='build'][0] if any(j['name']=='build' for j in jobs) else '')")
if [ -n "$BUILD_ID" ]; then
    BUILD_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['name']=='build'][0])")
    echo ""
    echo "1. build: $BUILD_STATUS"
    
    if [ "$BUILD_STATUS" = "failed" ]; then
        echo "   [错误] build job失败"
        curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$BUILD_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep -E "ERROR|error|失败" | tail -5
    else
        # 检查是否正确读取包名
        PACKAGE_NAME=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$BUILD_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep "PACKAGE_NAME=" | head -1 | sed 's/.*PACKAGE_NAME=//')
        echo "   [包名]: $PACKAGE_NAME"
        
        # 检查webhook触发
        WEBHOOK_RESULT=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$BUILD_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep -E "webhook|触发" | tail -3)
        echo "   [webhook]: $WEBHOOK_RESULT"
    fi
fi

# 2. obs-trigger分析
OBS_TRIGGER_ID=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['id'] for j in jobs if j['name']=='obs-trigger'][0] if any(j['name']=='obs-trigger' for j in jobs) else '')")
if [ -n "$OBS_TRIGGER_ID" ]; then
    OBS_TRIGGER_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['name']=='obs-trigger'][0])")
    echo ""
    echo "2. obs-trigger: $OBS_TRIGGER_STATUS"
    
    if [ "$OBS_TRIGGER_STATUS" = "failed" ]; then
        echo "   [错误] OBS上传失败"
        curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$OBS_TRIGGER_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep -E "ERROR|error|404|does not exist" | tail -5
    fi
fi

# 3. obs-wait分析
OBS_WAIT_ID=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['id'] for j in jobs if j['name']=='obs-wait'][0] if any(j['name']=='obs-wait' for j in jobs) else '')")
if [ -n "$OBS_WAIT_ID" ]; then
    OBS_WAIT_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['name']=='obs-wait'][0])")
    echo ""
    echo "3. obs-wait: $OBS_WAIT_STATUS"
    
    if [ "$OBS_WAIT_STATUS" = "failed" ]; then
        echo "   [错误] OBS构建超时或失败"
        # 检查OBS构建状态
        if [ -n "$PACKAGE_NAME" ]; then
            OBS_RESULT=$(curl -s "$OBS_API/build/home:Admin:$PACKAGE_NAME/_result" \
                --user "$OBS_USER:$OBS_PASSWORD")
            echo "   [OBS状态]: $OBS_RESULT"
        fi
    fi
fi

# 4. sync分析
SYNC_IDS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print(' '.join([str(j['id']) for j in jobs if j['name'].startswith('sync')]))")
for SYNC_ID in $SYNC_IDS; do
    SYNC_NAME=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['name'] for j in jobs if j['id']==$SYNC_ID][0])")
    SYNC_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['id']==$SYNC_ID][0])")
    echo ""
    echo "4. $SYNC_NAME: $SYNC_STATUS"
    
    if [ "$SYNC_STATUS" = "failed" ]; then
        echo "   [错误] 同步失败"
        curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$SYNC_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep -E "ERROR|error|500" | tail -5
    fi
done

# 5. quality-gate分析
QG_IDS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print(' '.join([str(j['id']) for j in jobs if j['name'].startswith('quality-gate')]))")
for QG_ID in $QG_IDS; do
    QG_NAME=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['name'] for j in jobs if j['id']==$QG_ID][0])")
    QG_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['id']==$QG_ID][0])")
    echo ""
    echo "5. $QG_NAME: $QG_STATUS"
    
    if [ "$QG_STATUS" = "failed" ]; then
        echo "   [错误] 质量检查失败"
        curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$QG_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep -E "ERROR|error|CVE|依赖" | tail -5
    fi
done

# 6. update-repo分析
UPDATE_REPO_ID=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['id'] for j in jobs if j['name']=='update-repo'][0] if any(j['name']=='update-repo' for j in jobs) else '')")
if [ -n "$UPDATE_REPO_ID" ]; then
    UPDATE_REPO_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['name']=='update-repo'][0])")
    echo ""
    echo "6. update-repo: $UPDATE_REPO_STATUS"
fi

# 总结
echo ""
echo "========================================"
echo "【诊断建议】"
echo "========================================"

if [ "$PIPELINE_STATUS" = "success" ]; then
    echo "Pipeline成功完成！"
    if [ -n "$PACKAGE_NAME" ]; then
        echo "OBS构建状态:"
        curl -s "$OBS_API/build/home:Admin:$PACKAGE_NAME/_result" \
            --user "$OBS_USER:$OBS_PASSWORD"
    fi
elif [ "$PIPELINE_STATUS" = "failed" ]; then
    FAILED_JOBS=$(echo "$JOBS" | python3 -c "
import sys,json
jobs = json.load(sys.stdin)
failed = [j['name'] for j in jobs if j['status']=='failed']
print(' '.join(failed))")
    echo "失败的Jobs: $FAILED_JOBS"
    
    # 根据失败Job提供建议
    if echo "$FAILED_JOBS" | grep -q "build"; then
        echo ""
        echo "[build失败建议]:"
        echo "  1. 检查intewell.yaml是否存在且格式正确"
        echo "  2. 检查源码目录结构"
        echo "  3. 检查webhook-server是否运行"
    fi
    
    if echo "$FAILED_JOBS" | grep -q "obs-trigger"; then
        echo ""
        echo "[obs-trigger失败建议]:"
        echo "  1. 检查OBS项目是否已创建"
        echo "  2. 检查OBS服务是否运行"
        echo "  3. 检查spec文件格式"
    fi
    
    if echo "$FAILED_JOBS" | grep -q "obs-wait"; then
        echo ""
        echo "[obs-wait失败建议]:"
        echo "  1. 检查OBS scheduler是否运行"
        echo "  2. 检查OBS构建日志"
        echo "  3. 增加obs-wait超时时间"
    fi
    
    if echo "$FAILED_JOBS" | grep -q "sync"; then
        echo ""
        echo "[sync失败建议]:"
        echo "  1. 检查sync-service是否运行"
        echo "  2. 检查RPM是否已构建完成"
    fi
    
    if echo "$FAILED_JOBS" | grep -q "quality-gate"; then
        echo ""
        echo "[quality-gate失败建议]:"
        echo "  1. 检查quality-gate服务是否运行"
        echo "  2. 检查CVE扫描结果"
        echo "  3. 检查依赖关系"
    fi
elif [ "$PIPELINE_STATUS" = "running" ]; then
    echo "Pipeline正在运行中，请等待..."
else
    echo "Pipeline状态: $PIPELINE_STATUS"
fi
```

## 输出示例

```
========================================
Pipeline #231 分析报告
========================================

【Pipeline状态】: success

【Jobs状态】:
  build: success
  obs-trigger: success
  obs-wait: success
  quality-gate-aarch64: success
  quality-gate-x86_64: success
  sync-aarch64: success
  sync-x86_64: success
  update-repo: success

【详细分析】:
1. build: success
   [包名]: test130
   [webhook]: 触发 webhook-server 创建 OBS 项目: test130

2. obs-trigger: success

3. obs-wait: success

========================================
【诊断建议】
========================================
Pipeline成功完成！
OBS构建状态: published
```

## 调试文档匹配

当分析发现问题时，自动读取项目调试文档进行匹配：

### 调试文档路径

```
/home/nando/AICICD/docs/debug/
├── add-test-folder-process.md      # 新增测试包流程
├── multi-package-parallel-cicd-debug.md  # 多包并行CI/CD
├── obs-server-debug.md             # OBS服务调试
├── gitlab-runner-debug.md          # GitLab Runner调试
├── intewell-packer-debug.md        # Packer ISO构建
├── feishu-terminal-bot-debug.md    # 飞书终端机器人
```

### 问题匹配规则

| 错误关键词 | 匹配文档 | 章节 |
|-----------|---------|------|
| `webhook`, `internal error`, `Host is unreachable` | gitlab-webhook-bypass skill | - |
| `OBS`, `does not exist`, `404`, `scheduler` | obs-server-debug.md | 问题1-10 |
| `Runner`, `pending`, `config.toml`, `Failed to load` | gitlab-runner-debug.md | - |
| `sync`, `500`, `Connection refused` | multi-package-parallel-cicd-debug.md | sync问题 |
| `Pipeline`, `YAML`, `syntax` | add-test-folder-process.md | CI模板问题 |
| `Packer`, `ISO`, `appset` | intewell-packer-debug.md | - |

### 匹配函数示例

```python
def match_debug_doc(error_keywords):
    """根据错误关键词匹配调试文档"""
    docs_path = "/home/nando/AICICD/docs/debug/"
    
    matches = {
        'webhook': ('gitlab-webhook-bypass', None),
        'internal error': ('gitlab-webhook-bypass', None),
        'OBS': ('obs-server-debug.md', None),
        'does not exist': ('obs-server-debug.md', 'OBS项目不存在'),
        'scheduler': ('obs-server-debug.md', 'scheduler未运行'),
        'Runner': ('gitlab-runner-debug.md', None),
        'pending': ('gitlab-runner-debug.md', 'Runner不拉取job'),
        'Failed to load config': ('gitlab-runner-debug.md', '配置文件丢失'),
        'sync': ('multi-package-parallel-cicd-debug.md', 'sync问题'),
    }
    
    for keyword in error_keywords:
        if keyword in matches:
            doc, section = matches[keyword]
            return doc, section
    
    return None, None
```

## Pitfalls

### 1. Pipeline ID获取失败

**原因**: TOKEN无效或网络问题

**解决**: 检查TOKEN和网络连接

### 2. Job trace解析失败

**原因**: Job还在运行，trace不完整

**解决**: 等待Job完成后再分析

### 3. OBS状态查询失败

**原因**: OBS服务未运行或认证失败

**解决**: 检查OBS服务状态和认证信息

## 相关Skills

- intewell-cicd-full-automation: 全自动化流程
- gitlab-webhook-bypass: webhook网络问题
- obs-build-service: OBS部署调试