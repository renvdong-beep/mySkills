---
name: intewell-project-context
description: Intewell CI/CD项目的通用上下文和铁律。包含项目状态、关键架构决策、服务端口、自动化脚本、固化Skills等。Agent在处理Intewell项目任务时必须遵守这些铁律。
tags:
  - intewell
  - cicd
  - context
  - rules
  - automation
---

# Intewell CI/CD 项目上下文

## 项目信息

- **项目名称**: Intewell 机器人操作系统 CI/CD 系统
- **基于**: openEuler OBS 架构
- **系统底座**: openEuler 24.03 LTS SP1
- **项目目录**: `/home/nando/AICICD/`

## 项目状态

| 阶段 | 名称 | 状态 |
|------|------|------|
| 阶段1 | 源码管理与触发 | ✅ 已完成 |
| 阶段2 | OBS 多架构 RPM 构建 | ✅ 已完成 |
| 阶段3 | 制品同步与质量门禁 | ✅ 已完成 |
| 阶段4 | 系统镜像集成构建 | ✅ 已完成 |
| 阶段5 | 物理化装机与边缘烧写 | ⏳ 待实施 |
| 阶段6 | AI 智能运维 | ⏳ 待实施 |

## ⚠️ 项目铁律 (必须遵守)

### 自动化铁律 (最高优先级)

**有需要手动的问题，就应该设置为自动化脚本，保证全链路自动化流程。不允许手动介入！**

- 发现任何需要手动操作的步骤 → 立即创建自动化脚本
- 调试过程必须实时记录到 `docs/debug/` 目录
- 新增配置/修复问题后 → 更新对应的自动化脚本
- 自动化脚本目录: `/home/nando/AICICD/scripts/`

### CI/CD 全链路铁律

**完整流程分两段：CI Pipeline (6步) + ISO构建 (独立流程)**

- **CI Pipeline (6步)**: push → build → obs-trigger → obs-wait → sync → quality-gate → update-repo
- **ISO构建 (独立流程)**: CI完成后由 webhook-server 自动触发 Packer 构建
- **开发人员 push 代码后必须能自动走完全链路到 ISO，不允许手动触发！**

### 构建目标选择铁律

开发人员在仓库根目录放 `intewell.yaml` 配置文件选择构建目标：

```yaml
package:
  name: test1
  version: 1.0.0

build:
  target: iso          # iso | rpm-only
  arch:                # 可选，默认双架构
    - x86_64
    - aarch64
```

- `target: iso` → CI 6步完成 → 自动触发 Packer ISO 构建
- `target: rpm-only` → CI 6步完成 → 结束
- 无 intewell.yaml → 默认 rpm-only

### 磁盘占用铁律

**所有占用磁盘的目录必须在 `/home/nando/AICICD` 下创建！**

- 根分区 `/` 仅 69G，剩余 ~24G
- Home 分区 `/home` 有 1.8T，剩余 ~1.6T

### 调试铁律

**有问题就分析问题，然后修改脚本，然后新建test进行自动流程的测试。不要手动触发CI模板更新！**

1. 分析问题根因
2. 修改脚本/代码
3. 新建test验证
4. 确认问题解决

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| GitLab Server | 8080 | 源码仓库 + CI/CD |
| OBS Server | 4455 | RPM 构建服务 (Admin:admin123) |
| OBS HTTP 仓库 | 5252 | x86_64 RPM 仓库 |
| OBS aarch64 仓库 | 8082 | aarch64 RPM 仓库 |
| sync-service | 8090 | 制品同步服务 |
| quality-gate | 8081 | 质量门禁服务 |
| cve-scanner | 8083 | CVE 扫描服务 |
| webhook-server | 8091 | Webhook 接收服务 |
| Redis | 6380 | OBS 缓存 |

## 关键架构决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 系统底座 | openEuler 24.03 LTS SP1 | LTS 5年支持，OBS 官方支持 |
| OBS 部署方式 | Docker (开发) / 裸机 (生产) | Docker 快速验证 |
| OBS 子项目隔离 | 每个包独立子项目 | 支持多人并行 |
| Runner 网络 | network_mode=host | 解决 Docker 网络隔离 |
| 通知渠道 | 飞书 | 用户偏好 |
| 数据目录 | /home/nando/AICICD/data/ | 磁盘空间充足 |

## 固化 Skills

| Skill | 说明 |
|-------|------|
| obs-build-service | OBS 部署调试 |
| cicd-pipeline-services | CI/CD 微服务 |
| gitlab-runner-docker | Runner Docker executor |
| intewell-packer | Packer ISO 构建 |
| gitlab-ci-yaml-upload | CI YAML API 上传 |
| gitlab-webhook-bypass | Webhook 网络问题 |
| intewell-cicd-full-automation | 全自动化流程 |
| intewell-pipeline-analyzer | Pipeline 分析诊断 |

## 自动化脚本 (scripts/)

| 脚本 | 功能 | 用法 |
|------|------|------|
| add-test-package.sh | 一键添加测试包并触发全链路构建 | `./add-test-package.sh <包名> [iso|rpm-only]` |
| full-chain-test.sh | 全链路自动化测试 | `./full-chain-test.sh <包名>` |
| check-and-fix-obs.sh | OBS服务健康检查与自动修复 | `./check-and-fix-obs.sh` |
| analyze-pipeline.sh | Pipeline状态分析 | `./analyze-pipeline.sh [pipeline_id]` |
| analyze-pipeline-with-docs.sh | Pipeline分析+调试文档匹配 | `./analyze-pipeline-with-docs.sh [pipeline_id]` |
| restore-cicd.sh | CI/CD环境恢复 | `./restore-cicd.sh` |
| setup-gitlab-webhook.sh | GitLab Webhook配置 | `./setup-gitlab-webhook.sh <项目ID>` |

## 调试文档目录

```
/home/nando/AICICD/docs/debug/
├── add-test-folder-process.md      # 新增测试包流程
├── multi-package-parallel-cicd-debug.md  # 多包并行CI/CD
├── obs-server-debug.md             # OBS服务调试
├── gitlab-runner-debug.md          # GitLab Runner调试
├── intewell-packer-debug.md        # Packer ISO构建
├── feishu-terminal-bot-debug.md    # 飞书终端机器人
```

## Pitfalls

### 1. 不要重复探索已有解决方案

**问题**: Agent自己重新探索解决方案，浪费时间

**解决**: 做CI/CD任务前必须:
1. 读 `docs/` 目录下的文档
2. 查 `session_search` 看之前的工作
3. 检查已有服务代码
4. 加载相关 skill

### 2. 不要手动触发CI模板更新

**问题**: 手动触发webhook导致重复Pipeline或时序问题

**解决**: 使用自动化脚本或直接git push

### 3. 修改代码时不要引入新问题

**问题**: 解决一个问题又制造另一个问题

**解决**: 修改后必须新建test验证全流程

## 相关文件

- AGENTS.md: `/home/nando/AICICD/AGENTS.md`
- 固化文档: `/home/nando/AICICD/docs/cicd-flow-snapshot-2026-05-19.md`
- CI模板: `/tmp/intewell-test/.gitlab-ci.yml`
- webhook-server: `/home/nando/AICICD/01-source-trigger/webhook-server/app.py`