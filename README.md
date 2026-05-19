# mySkills

Hermes/Claude Skills 集合，包含多个项目的技能文档。

## 目录结构

```
mySkills/
├── skysi/                       # M1000/Intewell skills (11个)
├── intewell-terra-userdefos/    # 开发运维通用 skills (10个)
├── AICICD/                      # AICICD CI/CD 项目 skills (12个)
│   ├── devops/
│   └── software-development/
└── README.md
```

## Skills 列表

### skysi/ - M1000/Intewell Skills (11个)

| Skill | 描述 |
|-------|------|
| 01-hardware-info-collection | 硬件信息收集 |
| 02-npu-driver-installation | NPU驱动安装 |
| 03-hlaw-ollama-service | Ollama服务配置 |
| 04-inference-performance-test | 推理性能测试 |
| 05-display-troubleshooting | 显示问题排查 |
| 06-intewell-repo-config | Intewell仓库配置 |
| 07-ssh-remote-config | SSH远程配置 |
| 08-system-backup-restore | 系统备份恢复 |
| 09-network-configuration | 网络配置 |
| 10-log-analysis | 日志分析 |
| 11-github-repo-create | GitHub仓库创建 |

### intewell-terra-userdefos/ - 开发运维通用 Skills (10个)

| Skill | 描述 |
|-------|------|
| build-script-diff-analysis | 构建脚本差异分析 |
| config-diff-management | 配置差异管理 |
| directory-migration | 目录迁移 |
| docker-cross-arch-build | Docker跨架构构建 |
| git-commit-workflow | Git提交工作流 |
| git-push-strategy | Git推送策略 |
| internal-external-merge | 内外部合并 |
| pyinstaller-debug | PyInstaller调试 |
| pyinstaller-path-check | PyInstaller路径检查 |
| shell-script-debug | Shell脚本调试 |

### AICICD/ - CI/CD Skills (12个)

| Skill | 描述 |
|-------|------|
| obs-build-service | OBS部署调试 |
| cicd-pipeline-services | CI/CD微服务 |
| gitlab-runner-docker | GitLab Runner配置 |
| gitlab-ci-yaml-upload | CI YAML上传 |
| intewell-packer | Packer ISO构建 |
| gitlab-webhook-bypass | Webhook问题解决 |
| intewell-cicd-full-automation | 全自动化流程 |
| intewell-pipeline-analyzer | Pipeline分析 |
| intewell-project-context | 项目上下文 |
| intewell-health-check | 自动化巡检 |
| intewell-project-migration | 项目迁移 |
| cicd-project-template | CI/CD项目模板 |

## 使用方法

将 skills 目录复制到 Hermes 的 skills 目录：

```bash
cp -r mySkills/* ~/.hermes/skills/
```

## 更新日期

- 2026-04-24: 初始创建 (skysi + intewell-terra-userdefos)
- 2026-05-19: 添加 AICICD skills
