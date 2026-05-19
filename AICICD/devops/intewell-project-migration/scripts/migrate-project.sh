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
        echo "========================================"
        echo "准备迁移包"
        echo "========================================"
        
        # 停止服务
        echo ""
        echo "[1/6] 停止服务..."
        docker stop gitlab gitlab-runner obs-server-test webhook-server sync-service quality-gate 2>/dev/null || true
        echo "服务已停止"
        
        # 创建迁移目录
        mkdir -p $MIGRATION_DIR/images $MIGRATION_DIR/configs
        
        # 导出镜像
        echo ""
        echo "[2/6] 导出Docker镜像..."
        IMAGES="gitlab/gitlab-ce:latest gitlab/gitlab-runner:latest"
        for img in $IMAGES; do
            name=$(echo $img | tr '/' '_' | tr ':' '_')
            echo "  导出: $img"
            docker save $img > $MIGRATION_DIR/images/${name}.tar 2>/dev/null || echo "  跳过: $img (不存在)"
        done
        
        # 导出本地镜像
        LOCAL_IMAGES="intewell-obs-server:latest intewell-webhook-server:v3.8 intewell-sync-service:latest intewell-quality-gate:latest"
        for img in $LOCAL_IMAGES; do
            name=$(echo $img | tr ':' '_')
            if docker images | grep -q "$img"; then
                echo "  导出: $img"
                docker save $img > $MIGRATION_DIR/images/${name}.tar
            else
                echo "  跳过: $img (不存在)"
            fi
        done
        
        # 打包项目
        echo ""
        echo "[3/6] 打包项目文件..."
        tar --exclude='*.log' \
            --exclude='__pycache__' \
            --exclude='.git' \
            --exclude='tmp/*' \
            --exclude='*.pyc' \
            -czvf $MIGRATION_DIR/AICICD-project.tar.gz \
            $PROJECT_DIR/ 2>/dev/null
        
        # 打包数据
        echo ""
        echo "[4/6] 打包数据文件..."
        if [ -d "$PROJECT_DIR/data" ]; then
            tar -czvf $MIGRATION_DIR/AICICD-data.tar.gz $PROJECT_DIR/data/ 2>/dev/null
        else
            echo "  数据目录不存在，跳过"
        fi
        
        # 打包Skills
        echo ""
        echo "[5/6] 打包Skills..."
        if [ -d ~/.hermes/skills ]; then
            tar -czvf $MIGRATION_DIR/hermes-skills.tar.gz ~/.hermes/skills/ 2>/dev/null
        else
            echo "  Skills目录不存在，跳过"
        fi
        
        # 导出配置
        echo ""
        echo "[6/6] 导出容器配置..."
        for container in gitlab gitlab-runner obs-server-test webhook-server; do
            if docker ps -a | grep -q "$container"; then
                docker inspect $container > $MIGRATION_DIR/configs/${container}-config.json 2>/dev/null || true
            fi
        done
        
        # GitLab Runner配置
        if [ -f /srv/gitlab-runner/config/config.toml ]; then
            cp /srv/gitlab-runner/config/config.toml $MIGRATION_DIR/configs/gitlab-runner-config.toml
        fi
        
        # GitLab配置
        if [ -d /srv/gitlab/config ]; then
            cp /srv/gitlab/config/gitlab.rb $MIGRATION_DIR/configs/gitlab.rb 2>/dev/null || true
            cp /srv/gitlab/config/gitlab-secrets.json $MIGRATION_DIR/configs/gitlab-secrets.json 2>/dev/null || true
        fi
        
        # 创建清单
        echo ""
        echo "创建迁移清单..."
        cat > $MIGRATION_DIR/MANIFEST.txt << EOF
Intewell CI/CD 迁移清单
日期: $(date)
源服务器: $(hostname -I | awk '{print $1}')

文件列表:
EOF
        for f in $MIGRATION_DIR/*.tar.gz $MIGRATION_DIR/images/*.tar; do
            if [ -f "$f" ]; then
                echo "$(basename $f): $(du -h $f | cut -f1)" >> $MIGRATION_DIR/MANIFEST.txt
            fi
        done
        
        echo ""
        echo "========================================"
        echo "迁移包准备完成"
        echo "========================================"
        echo "位置: $MIGRATION_DIR"
        echo ""
        echo "文件大小:"
        du -sh $MIGRATION_DIR
        echo ""
        cat $MIGRATION_DIR/MANIFEST.txt
        ;;
        
    transfer)
        TARGET_IP=$2
        TARGET_USER=${3:-nando}
        
        if [ -z "$TARGET_IP" ]; then
            echo "错误: 请指定目标服务器IP"
            echo "用法: ./migrate-project.sh transfer <ip> [user]"
            exit 1
        fi
        
        echo "========================================"
        echo "传输到目标服务器"
        echo "========================================"
        echo "目标: $TARGET_USER@$TARGET_IP"
        echo ""
        
        # 使用rsync传输
        rsync -avz --progress $MIGRATION_DIR/ $TARGET_USER@$TARGET_IP:/home/$TARGET_USER/AICICD-migration/
        
        echo ""
        echo "========================================"
        echo "传输完成"
        echo "========================================"
        ;;
        
    restore)
        echo "========================================"
        echo "恢复项目"
        echo "========================================"
        
        # 检查迁移目录
        if [ ! -d "$MIGRATION_DIR" ]; then
            echo "错误: 迁移目录不存在"
            echo "请先将迁移包传输到此服务器"
            exit 1
        fi
        
        # 解压项目
        echo ""
        echo "[1/5] 解压项目文件..."
        if [ -f "$MIGRATION_DIR/AICICD-project.tar.gz" ]; then
            tar -xzvf $MIGRATION_DIR/AICICD-project.tar.gz -C /
        else
            echo "  项目包不存在，跳过"
        fi
        
        # 解压数据
        echo ""
        echo "[2/5] 解压数据文件..."
        if [ -f "$MIGRATION_DIR/AICICD-data.tar.gz" ]; then
            tar -xzvf $MIGRATION_DIR/AICICD-data.tar.gz -C /
        else
            echo "  数据包不存在，跳过"
        fi
        
        # 解压Skills
        echo ""
        echo "[3/5] 解压Skills..."
        if [ -f "$MIGRATION_DIR/hermes-skills.tar.gz" ]; then
            mkdir -p ~/.hermes/skills
            tar -xzvf $MIGRATION_DIR/hermes-skills.tar.gz -C ~/.hermes/
        else
            echo "  Skills包不存在，跳过"
        fi
        
        # 导入镜像
        echo ""
        echo "[4/5] 导入Docker镜像..."
        for img in $MIGRATION_DIR/images/*.tar; do
            if [ -f "$img" ]; then
                echo "  导入: $(basename $img)"
                docker load -i $img
            fi
        done
        
        # 恢复配置
        echo ""
        echo "[5/5] 恢复配置..."
        
        # GitLab Runner配置
        mkdir -p /srv/gitlab-runner/config
        if [ -f "$MIGRATION_DIR/configs/gitlab-runner-config.toml" ]; then
            cp $MIGRATION_DIR/configs/gitlab-runner-config.toml /srv/gitlab-runner/config/config.toml
        fi
        
        # GitLab配置
        mkdir -p /srv/gitlab/config /srv/gitlab/data /srv/gitlab/logs
        if [ -f "$MIGRATION_DIR/configs/gitlab.rb" ]; then
            cp $MIGRATION_DIR/configs/gitlab.rb /srv/gitlab/config/
        fi
        if [ -f "$MIGRATION_DIR/configs/gitlab-secrets.json" ]; then
            cp $MIGRATION_DIR/configs/gitlab-secrets.json /srv/gitlab/config/
        fi
        
        # 启动服务
        echo ""
        echo "========================================"
        echo "启动服务"
        echo "========================================"
        
        # 使用恢复脚本
        if [ -f "/home/nando/AICICD/scripts/restore-cicd.sh" ]; then
            /home/nando/AICICD/scripts/restore-cicd.sh
        else
            echo "恢复脚本不存在，请手动启动服务"
        fi
        
        # 健康检查
        echo ""
        echo "========================================"
        echo "健康检查"
        echo "========================================"
        
        if [ -f "/home/nando/AICICD/scripts/health-check.sh" ]; then
            /home/nando/AICICD/scripts/health-check.sh
        else
            echo "健康检查脚本不存在"
        fi
        
        echo ""
        echo "========================================"
        echo "恢复完成"
        echo "========================================"
        ;;
        
    verify)
        echo "========================================"
        echo "验证迁移"
        echo "========================================"
        
        # 健康检查
        if [ -f "/home/nando/AICICD/scripts/health-check.sh" ]; then
            /home/nando/AICICD/scripts/health-check.sh
        fi
        
        # 测试Pipeline
        echo ""
        echo "创建测试包验证全链路..."
        if [ -f "/home/nando/AICICD/scripts/add-test-package.sh" ]; then
            /home/nando/AICICD/scripts/add-test-package.sh test-migration-verify rpm-only
        fi
        ;;
        
    *)
        echo "Intewell项目迁移脚本"
        echo ""
        echo "用法:"
        echo "  ./migrate-project.sh prepare          # 准备迁移包"
        echo "  ./migrate-project.sh transfer <ip>    # 传输到目标服务器"
        echo "  ./migrate-project.sh restore          # 在目标服务器恢复"
        echo "  ./migrate-project.sh verify           # 验证迁移结果"
        echo ""
        echo "示例:"
        echo "  # 源服务器"
        echo "  ./migrate-project.sh prepare"
        echo "  ./migrate-project.sh transfer 192.168.1.100"
        echo ""
        echo "  # 目标服务器"
        echo "  ./migrate-project.sh restore"
        echo "  ./migrate-project.sh verify"
        exit 1
        ;;
esac