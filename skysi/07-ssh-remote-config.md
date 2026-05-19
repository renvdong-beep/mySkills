# SSH远程连接配置

配置SSH免密登录，方便远程管理开发板。

## 触发条件
- 用户要求配置SSH
- 用户提到"免密登录"、"SSH配置"
- 需要远程管理开发板

## 配置步骤

### 1. 在本地机器生成密钥
```bash
ssh-keygen -t rsa -b 4096
# 或使用ed25519
ssh-keygen -t ed25519
```

### 2. 复制公钥到开发板
```bash
# 使用sshpass
sshpass -p '密码' ssh-copy-id -o StrictHostKeyChecking=no root@192.168.137.49

# 或手动复制
cat ~/.ssh/id_rsa.pub | ssh root@192.168.137.49 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
```

### 3. 测试免密登录
```bash
ssh root@192.168.137.49 "hostname"
```

### 4. 配置SSH别名
```bash
cat >> ~/.ssh/config << 'EOF'
Host skysi
    HostName 192.168.137.49
    User root
    IdentityFile ~/.ssh/id_rsa
EOF

chmod 600 ~/.ssh/config
```

### 5. 使用别名连接
```bash
ssh skysi
```

## 一键配置脚本

```bash
#!/bin/bash
# 在本地机器执行

# 开发板信息
BOARD_IP="192.168.137.49"
BOARD_USER="root"
BOARD_PASS="Mydt8.com"
ALIAS_NAME="skysi"

echo "=== 1. 检查SSH密钥 ==="
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "生成SSH密钥..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

echo "=== 2. 复制公钥到开发板 ==="
sshpass -p "$BOARD_PASS" ssh-copy-id -o StrictHostKeyChecking=no ${BOARD_USER}@${BOARD_IP}

echo "=== 3. 配置SSH别名 ==="
cat >> ~/.ssh/config << EOF
Host ${ALIAS_NAME}
    HostName ${BOARD_IP}
    User ${BOARD_USER}
    IdentityFile ~/.ssh/id_rsa
EOF
chmod 600 ~/.ssh/config

echo "=== 4. 测试连接 ==="
ssh ${ALIAS_NAME} "echo 'SSH配置成功!' && hostname"
```

## 常用SSH命令

### 远程执行命令
```bash
ssh skysi "命令"
ssh root@192.168.137.49 "systemctl status HLAWOllama"
```

### 远程复制文件
```bash
# 复制到远程
scp file.txt skysi:/tmp/

# 从远程复制
scp skysi:/tmp/file.txt ./

# 复制目录
scp -r dir/ skysi:/tmp/
```

### 端口转发
```bash
# 本地端口转发
ssh -L 8080:localhost:11434 skysi
# 访问 localhost:8080 等同于访问开发板的 11434 端口
```

### 保持连接
```bash
# 添加到 ~/.ssh/config
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## 开发板信息

| 项目 | 值 |
|-----|-----|
| IP地址 | 192.168.137.49 |
| 用户名 | root |
| 密码 | Mydt8.com |
| SSH端口 | 22 |

## 常见问题

### 问题1: Permission denied
```bash
# 检查公钥是否正确复制
ssh root@192.168.137.49 "cat ~/.ssh/authorized_keys"

# 检查权限
ssh root@192.168.137.49 "chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

### 问题2: Host key verification failed
```bash
# 删除旧的host key
ssh-keygen -R 192.168.137.49
```

### 问题3: Connection refused
```bash
# 检查SSH服务
ssh root@192.168.137.49 "systemctl status sshd"
```

## 注意事项
- 首次连接需要接受host key
- 公钥权限必须是600
- .ssh目录权限必须是700
- 密码包含特殊字符时需要转义
