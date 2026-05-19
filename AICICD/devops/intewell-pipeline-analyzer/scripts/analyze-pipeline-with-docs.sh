#!/bin/bash
# analyze-pipeline-with-docs.sh - Intewell Pipeline分析脚本（带调试文档匹配）
# 用法: ./analyze-pipeline-with-docs.sh [pipeline_id|latest] [project_id] [token]

PIPELINE_ID=${1:-latest}
PROJECT_ID=${2:-1}
TOKEN=${3:-"glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8"}
GITLAB_URL="http://localhost:8080"
OBS_API="http://localhost:5352"
OBS_USER="Admin"
OBS_PASSWORD="admin123"
DEBUG_DOCS_PATH="/home/nando/AICICD/docs/debug"

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

# 收集错误关键词
ERROR_KEYWORDS=""

# 分析每个Job
echo ""
echo "【详细分析】:"
JOBS=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/jobs" \
    --header "PRIVATE-TOKEN: $TOKEN")

# 1. build job分析
BUILD_ID=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['id'] for j in jobs if j['name']=='build'][0] if any(j['name']=='build' for j in jobs) else '')")
PACKAGE_NAME=""

if [ -n "$BUILD_ID" ]; then
    BUILD_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['name']=='build'][0])")
    echo ""
    echo "1. build: $BUILD_STATUS"
    
    if [ "$BUILD_STATUS" = "failed" ]; then
        echo "   [错误] build job失败"
        BUILD_TRACE=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$BUILD_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN")
        
        # 提取错误关键词
        ERROR_LINES=$(echo "$BUILD_TRACE" | grep -E "ERROR|error|失败|webhook|internal error|Host is unreachable" | tail -10)
        echo "$ERROR_LINES"
        
        # 收集关键词
        if echo "$ERROR_LINES" | grep -q "webhook"; then ERROR_KEYWORDS="$ERROR_KEYWORDS webhook"; fi
        if echo "$ERROR_LINES" | grep -q "internal error"; then ERROR_KEYWORDS="$ERROR_KEYWORDS internal_error"; fi
        if echo "$ERROR_LINES" | grep -q "Host is unreachable"; then ERROR_KEYWORDS="$ERROR_KEYWORDS host_unreachable"; fi
    else
        # 检查是否正确读取包名
        PACKAGE_NAME=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$BUILD_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep "PACKAGE_NAME=" | head -1 | sed 's/.*PACKAGE_NAME=//' | cut -d',' -f1)
        echo "   [包名]: $PACKAGE_NAME"
        
        # 检查webhook触发
        WEBHOOK_RESULT=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$BUILD_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN" | grep -E "webhook|触发" | tail -3)
        if [ -n "$WEBHOOK_RESULT" ]; then
            echo "   [webhook]: 已触发"
        fi
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
        OBS_TRACE=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$OBS_TRIGGER_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN")
        
        ERROR_LINES=$(echo "$OBS_TRACE" | grep -E "ERROR|error|404|does not exist|Connection refused" | tail -10)
        echo "$ERROR_LINES"
        
        # 收集关键词
        if echo "$ERROR_LINES" | grep -q "does not exist"; then ERROR_KEYWORDS="$ERROR_KEYWORDS obs_not_exist"; fi
        if echo "$ERROR_LINES" | grep -q "404"; then ERROR_KEYWORDS="$ERROR_KEYWORDS obs_404"; fi
        if echo "$ERROR_LINES" | grep -q "Connection refused"; then ERROR_KEYWORDS="$ERROR_KEYWORDS connection_refused"; fi
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
        OBS_TRACE=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$OBS_WAIT_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN")
        
        ERROR_LINES=$(echo "$OBS_TRACE" | grep -E "ERROR|timeout|timed out|scheduled" | tail -10)
        echo "$ERROR_LINES"
        
        # 收集关键词
        if echo "$ERROR_LINES" | grep -q "timeout"; then ERROR_KEYWORDS="$ERROR_KEYWORDS obs_timeout"; fi
        if echo "$ERROR_LINES" | grep -q "scheduled"; then ERROR_KEYWORDS="$ERROR_KEYWORDS obs_scheduled"; fi
        
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
        SYNC_TRACE=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$SYNC_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN")
        
        ERROR_LINES=$(echo "$SYNC_TRACE" | grep -E "ERROR|error|500|Connection refused" | tail -10)
        echo "$ERROR_LINES"
        
        # 收集关键词
        if echo "$ERROR_LINES" | grep -q "500"; then ERROR_KEYWORDS="$ERROR_KEYWORDS sync_500"; fi
        if echo "$ERROR_LINES" | grep -q "Connection refused"; then ERROR_KEYWORDS="$ERROR_KEYWORDS sync_refused"; fi
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
        QG_TRACE=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$QG_ID/trace" \
            --header "PRIVATE-TOKEN: $TOKEN")
        
        ERROR_LINES=$(echo "$QG_TRACE" | grep -E "ERROR|error|CVE|依赖" | tail -10)
        echo "$ERROR_LINES"
        
        # 收集关键词
        if echo "$ERROR_LINES" | grep -q "CVE"; then ERROR_KEYWORDS="$ERROR_KEYWORDS cve_error"; fi
    fi
done

# 6. update-repo分析
UPDATE_REPO_ID=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['id'] for j in jobs if j['name']=='update-repo'][0] if any(j['name']=='update-repo' for j in jobs) else '')")
if [ -n "$UPDATE_REPO_ID" ]; then
    UPDATE_REPO_STATUS=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print([j['status'] for j in jobs if j['name']=='update-repo'][0])")
    echo ""
    echo "6. update-repo: $UPDATE_REPO_STATUS"
fi

# 总结和调试文档匹配
echo ""
echo "========================================"
echo "【诊断建议】"
echo "========================================"

if [ "$PIPELINE_STATUS" = "success" ]; then
    echo "✓ Pipeline成功完成！"
    if [ -n "$PACKAGE_NAME" ]; then
        echo ""
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
    echo "✗ 失败的Jobs: $FAILED_JOBS"
    echo ""
    echo "【错误关键词】: $ERROR_KEYWORDS"
    
    # 匹配调试文档
    echo ""
    echo "【相关调试文档】:"
    
    for keyword in $ERROR_KEYWORDS; do
        case $keyword in
            webhook|internal_error|host_unreachable)
                echo ""
                echo ">>> 匹配: gitlab-webhook-bypass skill"
                echo "    问题: GitLab webhook返回internal error"
                echo "    解决: 在CI build job中主动调用webhook-server"
                echo "    参考: skill gitlab-webhook-bypass"
                ;;
            obs_not_exist|obs_404)
                echo ""
                echo ">>> 匹配: obs-server-debug.md"
                echo "    问题: OBS项目不存在"
                echo "    解决: 检查webhook-server是否创建OBS项目"
                if [ -f "$DEBUG_DOCS_PATH/obs-server-debug.md" ]; then
                    echo "    文档片段:"
                    grep -A5 "OBS项目不存在" "$DEBUG_DOCS_PATH/obs-server-debug.md" 2>/dev/null | head -10 || \
                    grep -A5 "does not exist" "$DEBUG_DOCS_PATH/obs-server-debug.md" 2>/dev/null | head -10
                fi
                ;;
            obs_timeout|obs_scheduled)
                echo ""
                echo ">>> 匹配: obs-server-debug.md"
                echo "    问题: OBS构建超时或一直scheduled"
                echo "    解决: 检查OBS scheduler是否运行"
                if [ -f "$DEBUG_DOCS_PATH/obs-server-debug.md" ]; then
                    echo "    文档片段:"
                    grep -A5 "scheduler" "$DEBUG_DOCS_PATH/obs-server-debug.md" 2>/dev/null | head -10
                fi
                ;;
            connection_refused|sync_refused)
                echo ""
                echo ">>> 匹配: multi-package-parallel-cicd-debug.md"
                echo "    问题: 服务连接失败"
                echo "    解决: 检查服务是否运行，网络配置"
                if [ -f "$DEBUG_DOCS_PATH/multi-package-parallel-cicd-debug.md" ]; then
                    echo "    文档片段:"
                    grep -A5 "Connection refused" "$DEBUG_DOCS_PATH/multi-package-parallel-cicd-debug.md" 2>/dev/null | head -10
                fi
                ;;
            sync_500)
                echo ""
                echo ">>> 匹配: multi-package-parallel-cicd-debug.md"
                echo "    问题: sync-service返回500错误"
                echo "    解决: 检查sync-service日志，RPM是否存在"
                if [ -f "$DEBUG_DOCS_PATH/multi-package-parallel-cicd-debug.md" ]; then
                    echo "    文档片段:"
                    grep -A5 "sync" "$DEBUG_DOCS_PATH/multi-package-parallel-cicd-debug.md" 2>/dev/null | head -10
                fi
                ;;
            cve_error)
                echo ""
                echo ">>> 匹配: cicd-pipeline-services skill"
                echo "    问题: CVE扫描失败"
                echo "    解决: 检查quality-gate服务配置"
                ;;
        esac
    done
    
    # 如果没有匹配到关键词，提供通用建议
    if [ -z "$ERROR_KEYWORDS" ]; then
        echo ""
        echo "【通用建议】:"
        
        if echo "$FAILED_JOBS" | grep -q "build"; then
            echo ""
            echo "[build失败建议]:"
            echo "  1. 检查intewell.yaml是否存在且格式正确"
            echo "  2. 检查源码目录结构"
            echo "  3. 检查webhook-server是否运行"
            echo "  4. 查看调试文档: $DEBUG_DOCS_PATH/add-test-folder-process.md"
        fi
        
        if echo "$FAILED_JOBS" | grep -q "obs-trigger"; then
            echo ""
            echo "[obs-trigger失败建议]:"
            echo "  1. 检查OBS项目是否已创建"
            echo "  2. 检查OBS服务是否运行"
            echo "  3. 检查spec文件格式"
            echo "  4. 查看调试文档: $DEBUG_DOCS_PATH/obs-server-debug.md"
        fi
        
        if echo "$FAILED_JOBS" | grep -q "obs-wait"; then
            echo ""
            echo "[obs-wait失败建议]:"
            echo "  1. 检查OBS scheduler是否运行"
            echo "  2. 检查OBS构建日志"
            echo "  3. 增加obs-wait超时时间"
            echo "  4. 查看调试文档: $DEBUG_DOCS_PATH/obs-server-debug.md"
        fi
        
        if echo "$FAILED_JOBS" | grep -q "sync"; then
            echo ""
            echo "[sync失败建议]:"
            echo "  1. 检查sync-service是否运行"
            echo "  2. 检查RPM是否已构建完成"
            echo "  3. 查看调试文档: $DEBUG_DOCS_PATH/multi-package-parallel-cicd-debug.md"
        fi
        
        if echo "$FAILED_JOBS" | grep -q "quality-gate"; then
            echo ""
            echo "[quality-gate失败建议]:"
            echo "  1. 检查quality-gate服务是否运行"
            echo "  2. 检查CVE扫描结果"
            echo "  3. 检查依赖关系"
        fi
    fi
elif [ "$PIPELINE_STATUS" = "running" ]; then
    echo "⏳ Pipeline正在运行中，请等待..."
else
    echo "Pipeline状态: $PIPELINE_STATUS"
fi

# 显示所有调试文档列表
echo ""
echo "========================================"
echo "【调试文档列表】"
echo "========================================"
ls -la "$DEBUG_DOCS_PATH"/*.md 2>/dev/null | awk '{print "  " $NF}'