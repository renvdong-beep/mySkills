#!/bin/bash
# add-test-package.sh - One-click add test package and trigger full-chain build
# Usage: ./add-test-package.sh <package_name> [target]
#   package_name: Package name (e.g., test5, test6)
#   target: iso or rpm-only (default: iso)

set -e

PACKAGE_NAME=${1:-test$(date +%s | tail -c 3)}
BUILD_TARGET=${2:-iso}
PROJECT_DIR="/home/nando/AICICD"
INTREWELL_TEST_DIR="/tmp/intewell-test-$$"

GITLAB_URL="http://localhost:8080"
GITLAB_TOKEN="glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8"
WEBHOOK_URL="http://localhost:8091/gitlab/push"

echo "=========================================="
echo "Intewell CI/CD Full-Chain Automated Test"
echo "=========================================="
echo "Package: $PACKAGE_NAME"
echo "Target: $BUILD_TARGET"
echo "Time: $(date)"
echo ""

# 步骤1: 确保GitLab webhook配置正确（避免重复）
echo "=== [1/5] 检查GitLab Webhook配置 ==="
# 不再调用setup-gitlab-webhook.sh，因为它可能创建重复webhook
# 直接检查webhook是否存在
TOKEN="glpat-SiYCQt0LhczpcF7hlXgvW286MQp1OjIH.01.0w1rpj3m8"
WEBHOOK_URL="http://localhost:8091/gitlab/push"
EXISTING=$(curl -s "http://localhost:8080/api/v4/projects/1/hooks" --header "PRIVATE-TOKEN: $TOKEN" | python3 -c "
import sys,json
hooks = json.load(sys.stdin)
for h in hooks:
    if '$WEBHOOK_URL' in h.get('url', ''):
        print(h['id'])
        break
" 2>/dev/null || echo "")

if [ -z "$EXISTING" ]; then
    echo "配置GitLab webhook..."
    $PROJECT_DIR/scripts/setup-gitlab-webhook.sh 1 2>/dev/null || true
else
    echo "GitLab webhook已存在 (id=$EXISTING)"
fi

# Step 2: Clone intewell-test repo
echo "=== [2/5] Cloning intewell-test repo ==="
rm -rf "$INTREWELL_TEST_DIR"
git clone -q http://oauth2:$GITLAB_TOKEN@localhost:8080/renwd/intewell-test.git "$INTREWELL_TEST_DIR"
cd "$INTREWELL_TEST_DIR"

# Step 3: Create source files
echo "=== [3/5] Creating source files ==="
mkdir -p $PACKAGE_NAME

cat > $PACKAGE_NAME/$PACKAGE_NAME.c << EOF
#include <stdio.h>
int main() {
    printf("$PACKAGE_NAME - Intewell CI/CD automated test\n");
    printf("Build target: $BUILD_TARGET\n");
    return 0;
}
EOF

cat > $PACKAGE_NAME/$PACKAGE_NAME.spec << EOF
Name:           $PACKAGE_NAME
Version:        1.0.0
Release:        1
Summary:        $PACKAGE_NAME for Intewell CI/CD test
License:        MIT
Source0:        %{name}-%{version}.tar.gz
%description
$PACKAGE_NAME for CI/CD verification.
%prep
%setup -q
%build
gcc -o $PACKAGE_NAME $PACKAGE_NAME.c
%install
mkdir -p %{buildroot}/usr/bin
install -m 755 $PACKAGE_NAME %{buildroot}/usr/bin/$PACKAGE_NAME
%files
/usr/bin/$PACKAGE_NAME
EOF

# Step 4: Update intewell.yaml
echo "=== [4/5] Updating intewell.yaml ==="
cat > intewell.yaml << EOF
package:
  name: $PACKAGE_NAME
  version: 1.0.0
build:
  target: $BUILD_TARGET
  arch:
    - x86_64
    - aarch64
iso:
  configs:
    - main_base_aarch64-S5000C.json
EOF

# Step 5: Commit and push
echo "=== [5/5] Committing and triggering build ==="
git add .
git commit -q -m "Add $PACKAGE_NAME for automated CI/CD test"
git push -q origin main

echo ""
echo "=========================================="
echo "Code pushed, triggering full-chain build"
echo "=========================================="

# Trigger webhook
sleep 2
curl -s -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d "{
    \"object_kind\": \"push\",
    \"project\": {\"id\": 1, \"path_with_namespace\": \"renwd/intewell-test\"},
    \"ref\": \"refs/heads/main\",
    \"before\": \"abc\",
    \"after\": \"def\",
    \"commits\": [{\"message\": \"Add $PACKAGE_NAME\"}],
    \"user_name\": \"script\",
    \"repository\": {\"name\": \"intewell-test\"}
  }" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Status: {d.get(\"status\")}')
for p in d.get('packages', []):
    print(f'  Package: {p.get(\"package\")} Target: {p.get(\"target\")} Status: {p.get(\"status\")}')
"

# Wait for Pipeline
echo ""
echo "Waiting for Pipeline creation..."
sleep 5

PIPELINE_ID=$(curl -s "$GITLAB_URL/api/v4/projects/1/pipelines?per_page=1" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" | python3 -c "
import sys,json; p=json.load(sys.stdin); print(p[0]['id'] if p else 0)
")

if [ -n "$PIPELINE_ID" ] && [ "$PIPELINE_ID" != "0" ]; then
    echo ""
    echo "=========================================="
    echo "Pipeline #$PIPELINE_ID created"
    echo "=========================================="
    echo ""
    echo "Monitor: http://192.168.137.103:8080/renwd/intewell-test/-/pipelines/$PIPELINE_ID"
    echo ""
    echo "Full-chain flow:"
    echo "  1. push → build (build source)"
    echo "  2. obs-trigger → obs-wait (OBS build RPM)"
    echo "  3. sync → quality-gate (sync and quality check)"
    echo "  4. update-repo (update repository)"
    if [ "$BUILD_TARGET" = "iso" ]; then
        echo "  5. ISO build (Packer auto-trigger)"
    fi
    echo ""
    echo "View logs: docker logs -f webhook-server"
else
    echo "Pipeline creation failed, check webhook-server logs"
fi

# Cleanup
rm -rf "$INTREWELL_TEST_DIR"
