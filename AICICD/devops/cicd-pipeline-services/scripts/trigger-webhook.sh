#!/bin/bash
# 自动触发webhook处理
# 解决GitLab webhook返回internal error的问题
#
# Usage: ./trigger-webhook.sh [project_id]

set -e

# Configuration
WEBHOOK_URL="http://192.168.137.103:8091/gitlab/push"
GITLAB_URL="http://localhost:8080"
GITLAB_TOKEN="glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8"

# Get project ID (default: 1 = intewell-test)
PROJECT_ID=${1:-1}
PROJECT_NAME="intewell-test"

# Get latest commit SHA
echo "获取项目 $PROJECT_ID 最新 commit..."
SHA=$(curl -s "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/commits?per_page=1" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

if [ -z "$SHA" ]; then
  echo "ERROR: 无法获取 commit SHA"
  exit 1
fi

echo "触发webhook处理: SHA=$SHA"

# Trigger webhook
RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"object_kind\": \"push\",
    \"before\": \"abc\",
    \"after\": \"$SHA\",
    \"ref\": \"refs/heads/main\",
    \"user_name\": \"auto-trigger\",
    \"project\": {\"id\": $PROJECT_ID, \"name\": \"$PROJECT_NAME\", \"path_with_namespace\": \"renwd/$PROJECT_NAME\"},
    \"repository\": {\"name\": \"$PROJECT_NAME\", \"url\": \"$GITLAB_URL/renwd/$PROJECT_NAME.git\"},
    \"commits\": [{\"id\": \"$SHA\", \"message\": \"auto trigger\"}]
  }")

echo ""
echo "Webhook响应:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# Check result
if echo "$RESPONSE" | grep -q '"status":"accepted"'; then
  echo ""
  echo "✓ Webhook处理成功"
else
  echo ""
  echo "✗ Webhook处理失败"
  exit 1
fi
