---
name: cicd-project-template
description: CI/CD项目通用模板。包含AGENTS.md结构、文档目录组织、调试记录规范、自动化脚本规范等。用于快速搭建新的CI/CD项目。
tags:
  - cicd
  - template
  - project-structure
  - documentation
  - automation
---

# CI/CD 项目通用模板

## 项目结构模板

```
project/
├── AGENTS.md                    # Agent上下文记录（必需）
├── README.md                    # 项目说明
├── docs/
│   ├── architecture/            # 架构设计文档
│   ├── debug/                   # 调试记录（按日期命名）
│   ├── procedures/              # 操作规程
│   ├── specs/                   # 规格说明
│   ├── reports/                 # 报告
│   ├── handover/                # 交接文档
│   └── cicd-flow-snapshot.md    # 流程固化文档
├── scripts/                     # 自动化脚本（必需）
│   ├── health-check.sh          # 健康检查
│   ├── restore-env.sh           # 环境恢复
│   └── analyze-*.sh             # 分析脚本
├── configs/                     # 配置文件
├── deployments/                 # 部署相关
└── data/                        # 数据目录（大文件）
```

## AGENTS.md 模板

```markdown
# 项目名称 - Agent 上下文记录

## 项目信息
- **项目名称**: xxx
- **基于**: xxx
- **系统底座**: xxx
- **版本**: v1.0
- **更新日期**: YYYY-MM-DD

## 项目状态

| 阶段 | 名称 | 状态 |
|------|------|------|
| 阶段1 | xxx | ✅ 已完成 |
| 阶段2 | xxx | ⏳ 进行中 |
| 阶段3 | xxx | ⏳ 待实施 |

## ⚠️ 项目铁律 (必须遵守)

### 自动化铁律 (最高优先级)
**有需要手动的问题，就应该设置为自动化脚本，保证全链路自动化流程。不允许手动介入！**

- 发现任何需要手动操作的步骤 → 立即创建自动化脚本
- 调试过程必须实时记录到 `docs/debug/` 目录
- 新增配置/修复问题后 → 更新对应的自动化脚本
- 自动化脚本目录: `scripts/`

### 调试铁律
**有问题就分析问题，然后修改脚本，然后新建test验证。不要手动触发！**

1. 分析问题根因
2. 修改脚本/代码
3. 新建test验证
4. 确认问题解决

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| xxx | 8080 | xxx |

## 关键架构决策

| 决策 | 选择 | 理由 |
|------|------|------|
| xxx | xxx | xxx |

## 固化 Skills

| Skill | 说明 |
|-------|------|
| xxx | xxx |

## 自动化脚本 (scripts/)

| 脚本 | 功能 | 用法 |
|------|------|------|
| xxx.sh | xxx | `./xxx.sh` |
```

## 调试文档模板

```markdown
# 调试记录标题

## 日期
YYYY-MM-DD

## 目标
本次调试的目标是什么

## 环境
- 系统版本
- 相关服务版本
- 配置信息

## 问题现象
描述遇到的问题

## 分析过程

### 问题1: 标题

**现象**:
```
错误日志
```

**原因**:
分析原因

**解决方案**:
```bash
修复命令
```

**验证**:
```bash
验证命令
```

## 总结
- 问题根因
- 解决方案
- 后续改进
```

## 自动化脚本规范

### 脚本头部模板

```bash
#!/bin/bash
# script-name.sh - 脚本功能说明
# 
# 用法: ./script-name.sh [参数]
#
# 参数:
#   参数1 - 说明
#   参数2 - 说明
#
# 示例:
#   ./script-name.sh arg1 arg2
#
# 作者: xxx
# 日期: YYYY-MM-DD

set -e  # 遇错退出

# 配置变量
PROJECT_DIR="/path/to/project"
LOG_DIR="$PROJECT_DIR/logs"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "开始执行..."

# 主逻辑
# ...

log "执行完成"
```

### 脚本命名规范

| 前缀 | 说明 | 示例 |
|------|------|------|
| setup- | 安装配置 | setup-gitlab.sh |
| check- | 检查验证 | check-and-fix-obs.sh |
| fix- | 修复问题 | fix-gitlab-runner.sh |
| restore- | 恢复环境 | restore-cicd.sh |
| analyze- | 分析诊断 | analyze-pipeline.sh |
| add- | 添加创建 | add-test-package.sh |
| init- | 初始化 | init-obs-projects.sh |
| migrate- | 迁移 | migrate-data-dir.sh |

## 流程固化文档模板

```markdown
# 项目流程固化文档

## 日期: YYYY-MM-DD

## 当前工作状态

### 验证成功的版本
- testXXX: Pipeline #XXX success

### 关键配置

#### 1. 服务配置
```bash
启动命令
```

#### 2. 配置文件
```
配置内容
```

## 恢复方法

### 1. 恢复服务A
```bash
恢复命令
```

### 2. 恢复服务B
```bash
恢复命令
```

## 故障排查

### 问题A
**原因**: xxx
**解决**: xxx

## 相关文件
- 文件1: 路径
- 文件2: 路径
```

## 文档组织规范

### docs/ 目录结构

| 子目录 | 内容 | 命名规范 |
|--------|------|---------|
| architecture/ | 架构设计 | `xxx-architecture.md` |
| debug/ | 调试记录 | `xxx-debug.md` 或 `xxx-process.md` |
| procedures/ | 操作规程 | `xxx-procedure.md` |
| specs/ | 规格说明 | `xxx-spec.md` |
| reports/ | 报告 | `xxx-report-YYYYMMDD.md` |
| handover/ | 交接文档 | `handover-YYYYMMDD.md` |

### 文档版本控制

在文档头部添加版本信息：

```markdown
# 文档标题

**版本**: v1.0
**日期**: YYYY-MM-DD
**作者**: xxx
**状态**: draft | review | final

## 更新历史

| 版本 | 日期 | 作者 | 变更说明 |
|------|------|------|---------|
| v1.0 | YYYY-MM-DD | xxx | 初始版本 |
```

## Pitfalls

### 1. AGENTS.md 未及时更新

**问题**: Agent使用过时的上下文信息

**解决**: 每次重要变更后更新AGENTS.md

### 2. 调试文档未记录

**问题**: 同样的问题重复调试

**解决**: 调试过程实时记录到docs/debug/

### 3. 自动化脚本缺少错误处理

**问题**: 脚本出错但继续执行导致更大问题

**解决**: 使用 `set -e` 和错误检查

### 4. 文档分散难以查找

**问题**: 文档放在多个位置

**解决**: 统一放在docs/目录下，按类型分类

## 相关Skills

- intewell-project-context: Intewell项目上下文示例
- intewell-health-check: 自动化巡检示例