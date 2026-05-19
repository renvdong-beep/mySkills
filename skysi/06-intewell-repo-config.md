# Intewell软件源配置

配置Intewell系统的软件源，解决包安装问题。

## 触发条件
- 用户要求安装软件包
- 用户提到"软件源"、"repo"、"dnf install失败"
- 包安装提示找不到包

## 配置步骤

### 1. 检查现有repo配置
```bash
ls -la /etc/yum.repos.d/
cat /etc/yum.repos.d/Intewell_extend.repo
```

### 2. 配置Intewell_extend.repo
```bash
cat > /etc/yum.repos.d/Intewell_extend.repo << 'EOF'
[Intewell_extend]
name=Intewell_extend
baseurl=ftp://121.43.98.247/Intewell_V1.2/Intewell_extend/$basearch/
metadata_expire=1h
enabled=1
gpgcheck=0
EOF
```

### 3. 修改内网地址为外网地址
```bash
sed -i 's|192.168.11.33|121.43.98.247|g' /etc/yum.repos.d/Intewell_unmodify.repo
```

### 4. 更新软件缓存
```bash
dnf clean all
dnf makecache
```

### 5. 验证配置
```bash
dnf repolist
```

## 常用软件包安装

### 桌面环境
```bash
dnf install -y lxqt desktop lightdm lightdm-gtk
```

### 网络工具
```bash
dnf install -y NetworkManager nm-connection-editor
```

### 开发工具
```bash
dnf install -y gcc make cmake git
```

### 系统工具
```bash
dnf install -y vim htop iotop
```

## 一键配置脚本

```bash
#!/bin/bash
echo "=== 配置Intewell软件源 ==="

# 备份原有配置
cp /etc/yum.repos.d/Intewell_extend.repo /etc/yum.repos.d/Intewell_extend.repo.bak 2>/dev/null

# 配置Intewell_extend.repo
cat > /etc/yum.repos.d/Intewell_extend.repo << 'EOF'
[Intewell_extend]
name=Intewell_extend
baseurl=ftp://121.43.98.247/Intewell_V1.2/Intewell_extend/$basearch/
metadata_expire=1h
enabled=1
gpgcheck=0
EOF

# 修改内网地址
sed -i 's|192.168.11.33|121.43.98.247|g' /etc/yum.repos.d/Intewell_unmodify.repo

# 更新缓存
dnf clean all
dnf makecache

echo "=== 配置完成 ==="
dnf repolist
```

## 常见问题

### 问题1: 无法连接软件源
```bash
# 检查网络
ping 121.43.98.247

# 检查DNS
nslookup 121.43.98.247
```

### 问题2: 找不到包
```bash
# 搜索包
dnf search 包名

# 查看包信息
dnf info 包名
```

### 问题3: 依赖冲突
```bash
# 清理缓存重试
dnf clean all
dnf makecache
dnf install -y 包名 --allowerasing
```

## 软件源地址说明

| 软件源 | 地址 | 说明 |
|-------|------|------|
| Intewell_extend | ftp://121.43.98.247/Intewell_V1.2/Intewell_extend/$basearch/ | 扩展软件包 |
| Intewell_unmodify | ftp://121.43.98.247/... | 基础软件包 |

## 注意事项
- 需要外网访问权限
- 内网地址(192.168.11.33)需要替换为外网地址
- 配置后需要更新缓存
