#!/bin/bash
# Intewell git push wrapper - 自动触发webhook处理
# 解决GitLab webhook返回internal error的问题
#
# 使用方法：
# ./intewell-push.sh "commit message"

set -e

WEBHOOK_URL="http://192.168.137.103:8091/gitlab/push"
PROJECT_ID=1
PROJECT_NAME="intewell-test"

# 提交并push
git add .
git commit -m "$1"
git push origin main

# 获取最新的commit SHA
SHA=$(git rev-parse HEAD)

echo ""
echo "触发webhook处理: SHA=$SHA"

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"object_kind\": \"push\",
    \"before\": \"abc\",
    \"after\": \"$SHA\",
    \"ref\": \"refs/heads/main\",
    \"user_name\": \"auto\",
    \"project\": {\"id\": $PROJECT_ID, \"name\": \"$PROJECT_NAME\", \"path_with_namespace\": \"renwd/$PROJECT_NAME\"},
    \"repository\": {\"name\": \"$PROJECT_NAME\", \"url\": \"http://localhost:8080/renwd/$PROJECT_NAME.git\"},
    \"commits\": [{\"id\": \"$SHA\", \"message\": \"$1\"}]
  }"

echo ""
echo "=========================================="
echo "推送完成，webhook已触发"
echo "=========================================="