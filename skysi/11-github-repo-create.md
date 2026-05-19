# GitHub仓库创建与推送

创建GitHub仓库并推送本地代码。

## 触发条件
- 用户要求创建GitHub仓库
- 用户提到"推送到GitHub"、"创建仓库"
- 需要上传代码到GitHub

## 前置条件检查

### 1. 检查gh CLI是否安装
```bash
which gh || echo "需要安装gh"
```

### 2. 安装gh CLI (如果未安装)
```bash
# Ubuntu/Debian
sudo apt-get install -y gh

# CentOS/RHEL
sudo dnf install -y gh

# macOS
brew install gh
```

### 3. 检查登录状态
```bash
gh auth status
```

### 4. 登录GitHub (如果未登录)
```bash
gh auth login
```

登录流程：
1. 选择 `GitHub.com`
2. 选择 `HTTPS` 或 `SSH`
3. 选择 `Login with a web browser`
4. 复制显示的code，在浏览器中完成授权

## 创建仓库并推送

### 方法1: 使用gh创建仓库

```bash
# 在项目目录执行
cd /path/to/your/project

# 初始化git (如果还没有)
git init
git add .
git commit -m "Initial commit"

# 创建GitHub仓库并推送
gh repo create mySkills --public --source=. --push

# 或创建私有仓库
gh repo create mySkills --private --source=. --push
```

### 方法2: 手动创建并推送

```bash
# 1. 在GitHub网页创建仓库: https://github.com/new
#    - 仓库名: mySkills
#    - 不要勾选 "Add a README file"
#    - 不要选择 .gitignore 和 license

# 2. 本地初始化并推送
cd /path/to/your/project
git init
git add .
git commit -m "Initial commit"
git branch -m main
git remote add origin https://github.com/USERNAME/mySkills.git
git push -u origin main
```

## 一键推送脚本

```bash
#!/bin/bash
# GitHub仓库创建与推送脚本

REPO_NAME="${1:-mySkills}"
VISIBILITY="${2:-public}"  # public 或 private

echo "=== 1. 检查gh CLI ==="
if ! command -v gh &> /dev/null; then
    echo "安装gh CLI..."
    sudo apt-get install -y gh
fi

echo "=== 2. 检查登录状态 ==="
if ! gh auth status &> /dev/null; then
    echo "请先登录GitHub:"
    echo "执行: gh auth login"
    exit 1
fi

echo "=== 3. 初始化Git ==="
if [ ! -d .git ]; then
    git init
    git add .
    git commit -m "Initial commit"
    git branch -m main
fi

echo "=== 4. 创建仓库并推送 ==="
if [ "$VISIBILITY" = "private" ]; then
    gh repo create "$REPO_NAME" --private --source=. --push
else
    gh repo create "$REPO_NAME" --public --source=. --push
fi

echo "=== 完成 ==="
gh repo view --web
```

## 常用gh命令

### 仓库操作
```bash
# 查看仓库信息
gh repo view

# 在浏览器打开仓库
gh repo view --web

# 列出所有仓库
gh repo list

# 删除仓库
gh repo delete USERNAME/REPO_NAME
```

### 认证管理
```bash
# 登录
gh auth login

# 查看登录状态
gh auth status

# 登出
gh auth logout

# 刷新token
gh auth refresh
```

### Git配置
```bash
# 配置用户信息
git config --global user.name "Your Name"
git config --global user.email "your@email.com"

# 查看配置
git config --global --list
```

## 常见问题

### 问题1: Authentication failed
```bash
# 重新登录
gh auth logout
gh auth login
```

### 问题2: Repository already exists
```bash
# 使用已存在的仓库
git remote add origin https://github.com/USERNAME/REPO_NAME.git
git push -u origin main
```

### 问题3: Permission denied
```bash
# 检查是否有权限
gh repo view USERNAME/REPO_NAME

# 或使用SSH
git remote set-url origin git@github.com:USERNAME/REPO_NAME.git
```

### 问题4: gh版本过旧
```bash
# 更新gh
# Ubuntu/Debian
sudo apt-get update && sudo apt-get upgrade gh

# 或从官方安装最新版
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
```

## SSH密钥配置 (可选)

```bash
# 生成SSH密钥
ssh-keygen -t ed25519 -C "your@email.com"

# 添加到ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 添加到GitHub
gh ssh-key add ~/.ssh/id_ed25519.pub

# 测试SSH连接
ssh -T git@github.com
```

## 注意事项
- 首次使用需要 `gh auth login`
- 推送前确保本地有commit
- 仓库名不能已存在
- 私有仓库需要付费账户或有限制
