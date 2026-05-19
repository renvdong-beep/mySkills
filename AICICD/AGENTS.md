# Intewell CI/CD 项目 - Agent 上下文记录

## 项目信息
- **项目名称**: Intewell 机器人操作系统 CI/CD 系统
- **基于**: openEuler OBS 架构
- **系统底座**: openEuler 24.03 LTS SP1
| **版本**: v2.1
|- **更新日期**: 2026-05-18

## 项目状态

| 阶段 | 名称 | 状态 |
|------|------|------|
| 阶段1 | 源码管理与触发 | ✅ 已完成 |
| 阶段2 | OBS 多架构 RPM 构建 | ✅ 已完成 |
| 阶段3 | 制品同步与质量门禁 | ✅ 已完成 |
| 阶段4 | 系统镜像集成构建 | ✅ 已完成 |
| 阶段5 | 物理化装机与边缘烧写 | ⏳ 待实施 |
| 阶段6 | AI 智能运维 | ⏳ 待实施 |

**已验证**: push → OBS构建 → sync → 质检 → createrepo → ISO 全链路通过 (x86_64 + aarch64)

**最新验证 (2026-05-18)**: Pipeline #152 全链路自动化测试通过
- test19包: build → obs-trigger → obs-wait → sync → quality-gate → update-repo 全部成功
- OBS构建: x86_64 + aarch64 双架构 published
- 自动化脚本: `scripts/add-test-package.sh` 一键触发全链路

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
  - 阶段1: 源码管理与触发 (push → build)
  - 阶段2: OBS 多架构 RPM 构建 (obs-trigger → obs-wait)
  - 阶段3: 制品同步与质量门禁 (sync → quality-gate → update-repo)
- **ISO构建 (独立流程)**: CI完成后由 webhook-server 自动触发 Packer 构建
  - 阶段4: 系统镜像集成构建 (Packer独立脚本，不在CI Pipeline内)
- **开发人员 push 代码后必须能自动走完全链路到 ISO，不允许手动触发！**
- **CI 模板只包含6步，ISO 构建由 webhook-server 根据 intewell.yaml target 决定是否触发**

### 构建目标选择铁律
**开发人员在仓库根目录放 `intewell.yaml` 配置文件选择构建目标：**
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
- `target: iso` → CI 6步完成 → 自动触发 Packer ISO 构建（共8步）
- `target: rpm-only` → CI 6步完成 → 结束（到 update-repo）
- 无 intewell.yaml → 默认 rpm-only，包名从仓库目录自动检测
- **webhook-server 读取 intewell.yaml 后根据 target 决定是否触发 ISO 构建**
- **ISO 构建由 Packer 独立脚本执行，不在 CI Pipeline 内**

### 磁盘占用铁律
**所有占用磁盘的目录必须在 `/home/nando/AICICD` 下创建！**

- 根分区 `/` 仅 69G，剩余 ~24G
- Home 分区 `/home` 有 1.8T，剩余 ~1.6T

已迁移目录：
- `/var/ftp/intewell/rpms` → `/home/nando/AICICD/data/repos`
- OBS容器 `/var/obs` → `/home/nando/AICICD/data/obs` (挂载)
- OBS容器 `/srv/obs` → `/home/nando/AICICD/data/obs-srv/obs` (挂载)

### glibc ABI 铁律
**OBS DoD 仓库版本必须和 Packer rootfs 基线版本一致！**
- OBS DoD 指向 SP1 (glibc-2.38-47, GLIBC_2.35)
- Packer rootfs 也是 SP1
- glibc 向前兼容但不向后兼容

### Packer 路径铁律
- appset 必须放 `_internal/prebuild_cache/` 下（不是项目根）
- HTTP 仓库必须 cd 到仓库目录再启动 python http.server
- createrepo_c 必须在 RPM 同步后重新运行

### ISO 构建铁律
- **`build_in_docker.sh` 必须在宿主机上执行，不能在容器内执行！**
- `build_in_docker.sh` 会自动启动专门的 Docker 容器进行 ISO 构建
- webhook-server 触发 ISO 构建时，应通过 `docker.sock` 在宿主机上执行 `bash build_in_docker.sh <config>`
- 不要创建中间容器来运行 `build_in_docker.sh`

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| GitLab Server | 8080 | 源码仓库 + CI/CD |
| OBS Server | 4455 | RPM 构建服务 (Admin:admin123) — 容器重启自动恢复 |
| OBS HTTP 仓库 | 5252 | x86_64 RPM 仓库 |
| OBS aarch64 仓库 | 8082 | aarch64 RPM 仓库 |
| sync-service | 8090 | 制品同步服务 |
| quality-gate | 8081 | 质量门禁服务 |
| cve-scanner | 8083 | CVE 扫描服务 |
| webhook-server | 8091 | Webhook 接收服务 (自动接入新包) |
| Redis | 6380 | OBS 缓存 |

## 关键架构决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 系统底座 | openEuler 24.03 LTS SP1 | LTS 5年支持，OBS 官方支持，多架构成熟 |
| OBS 部署方式 | Docker (开发) / 裸机 (生产) | Docker 快速验证，裸机性能最优 |
| OBS 子项目隔离 | 每个包独立子项目 | 支持多人并行，互不干扰 |
| OBS DoD 版本 | SP1 (非SP3) | glibc ABI 与 Packer rootfs 对齐 |
| _link 包合并 | 集成项目层叠+link包 | path层叠只提供依赖，link包合并RPM |
| Runner 网络 | network_mode=host | 解决 Docker 网络隔离 |
| CI 变量 URL | localhost | Runner 使用 host 网络 |
| CI YAML 上传 | base64 编码 | 避免 Python 变量替换破坏 ${VAR} |
| 通知渠道 | 飞书 | 用户偏好 |
| 数据目录 | /home/nando/AICICD/data/ | 磁盘空间充足 |
| 多包并行 | OBS子项目隔离 + 集成项目层叠 + _link包 | 支持多人并行互不干扰 |
| CI 包名映射 | CI/CD变量 PACKAGE_NAME 覆盖 | CI_PROJECT_NAME 可能≠包名 |
| Runner 并发 | concurrent=4 | 支持多Pipeline并行 |
| 新包接入方式 | Webhook 自动接入 (push→检测→创建OBS→设CI变量→上传模板→触发Pipeline) |
| 构建目标选择 | intewell.yaml (target: iso/rpm-only) |
| OBS 容器重启 | 自动恢复所有服务 (start-obs.sh + hostname修复) |
| sync-all 策略 | 从子项目同步 (home:Admin:pkgname) | 绕过集成项目OBS API hostname问题 |
| OBS Rails视图路径 | /app符号链接 | Rails在/app/views搜索，实际在/srv/www/obs/api/app/views |
| GitLab Runner镜像策略 | pull_policy=if-not-present | 避免每次拉取镜像，加速构建 |
| GitLab webhook URL | 使用IP地址而非localhost | localhost URL不会触发webhook，必须使用实际IP（如192.168.137.103） |

## 固化 Skills

| Skill | 说明 | 关键 Pitfall |
|-------|------|-------------|
| obs-build-service | OBS 部署调试 (19 refs) | DoD占位符杀bs_dodup、binfmt_misc挂载、--nocodeupdate、/app符号链接 |
| cicd-pipeline-services | CI/CD 微服务 (8 refs) | base64上传YAML、-T上传二进制、PACKAGE_NAME变量 |
| hermes-gateway-feishu | 飞书集成 (4 refs) | lark-oapi装venv、WebSocket长连接 |
| gitlab-runner-docker | Runner Docker executor | token signing key修复、tag匹配、max_builds=0、pull_policy |
| intewell-packer | Packer ISO 构建 | appset放_internal/、createrepo_c必须跑 |
| gitlab-ci-yaml-upload | CI YAML API 上传 | base64编码、YAML特殊字符、块标量写法 |

## 自动化脚本 (scripts/)

| 脚本 | 功能 | 用法 |
|------|------|------|
| add-test-package.sh | 一键添加测试包并触发全链路构建 | `./add-test-package.sh <包名> [iso|rpm-only]` |
| full-chain-test.sh | 全链路自动化测试（含环境检查） | `./full-chain-test.sh <包名>` |
| check-and-fix-obs.sh | OBS服务健康检查与自动修复 | `./check-and-fix-obs.sh` |
| setup-gitlab-webhook.sh | GitLab Webhook自动配置 | `./setup-gitlab-webhook.sh <项目ID>` |
| fix-gitlab-runner.sh | GitLab Runner配置修复 | `./fix-gitlab-runner.sh` |
| init-obs-projects.sh | OBS项目初始化（DoD+集成项目） | `./init-obs-projects.sh` |

## 下一步行动

1. **阶段5: 物理化装机与边缘烧写** (调研中)
   - E300 自动部署系统 (已学习文档)
   - PXE 网络装机服务
   - IPMI/Redfish 远程控制
   - 开发板烧写工具
   - 串口转网口服务 (ser2net/ttyd)
   - 文档: `docs/stage5-physical-deploy/e300-auto-deploy.md`
2. **阶段6: AI 智能运维** (待实施)
   - Dify Agent 配置
   - 知识库建设
   - 日志收集服务
3. **通用化改进** (持续)
   - ISO 构建接入 CI Pipeline (当前由 Packer 独立脚本执行，intewell.yaml target=iso 可触发)
4. **自动化运维脚本** (2026-05-18新增)
   - `scripts/add-test-package.sh` - 一键添加测试包并触发全链路构建
   - `scripts/full-chain-test.sh` - 全链路自动化测试（含环境检查+代码创建+Pipeline监控+ISO验证）
   - `scripts/check-and-fix-obs.sh` - OBS服务健康检查与自动修复
   - `scripts/setup-gitlab-webhook.sh` - GitLab Webhook自动配置

## CI变量问题修复 (2026-05-19)

### 问题
1. CI变量时序问题：Pipeline启动时CI变量还是旧值
2. 重复Pipeline问题：git push触发一个Pipeline，webhook-server更新CI模板后又触发一个
3. GitLab webhook触发失败：返回internal error

### 解决方案
1. **CI模板修改**：`.gitlab-ci.yml`从intewell.yaml动态读取package.name
2. **webhook-server修改**：
   - 使用push的commit SHA读取intewell.yaml（不是main分支）
   - 不再上传CI模板（CI模板已在仓库中）
3. **自动化脚本**：`scripts/trigger-webhook.sh`解决GitLab webhook触发失败

### 验证结果
- test108: 只有一个Pipeline ✓
- test108: CI模板正确读取包名test108 ✓
- test108: OBS构建成功 ✓

### 相关文件
- `/home/nando/AICICD/01-source-trigger/webhook-server/app.py`
- `/home/nando/AICICD/01-source-trigger/webhook-server/ci_templates.py`
- `/home/nando/AICICD/scripts/trigger-webhook.sh`

## 铁律 (2026-05-19 新增)

### 禁止手动触发webhook
**有问题就分析问题，然后修改脚本，然后新建test进行自动流程的测试。不要手动触发CI模板更新！**

### 自动化流程
1. 分析问题根因
2. 修改脚本/代码
3. 新建test验证
4. 确认问题解决

### 自动化脚本
- `scripts/intewell-push.sh` - git push + 自动触发webhook
- `scripts/trigger-webhook.sh` - 手动触发webhook（仅用于调试）


## 流程固化 (2026-05-19)

### 当前工作版本
- test122: Pipeline #224 success, OBS x86_64 + aarch64 published

### 关键配置

#### webhook-server
- 网络模式: **host** (必须使用 host 网络，否则无法访问 GitLab)
- 环境变量:
  - GITLAB_URL="http://localhost:8080"
  - OBS_URL="http://localhost:4455"

#### 提交流程
使用脚本提交，不要直接 git push：
```bash
/home/nando/AICICD/scripts/intewell-push.sh "commit message"
```

#### CI 模板
- 从 intewell.yaml 动态读取 package.name
- 不自动创建 OBS 项目（依赖 webhook-server）
- obs-wait 超时 600 秒

### 恢复方法
详见 `docs/cicd-flow-snapshot-2026-05-19.md`


## 全自动化流程实现 (2026-05-19 最终版本)

### 验证成功
- test126: Pipeline #230 success, OBS x86_64 + aarch64 published

### GitLab webhook internal error 问题已解决

**问题**: GitLab 容器内部有防火墙限制，无法访问宿主机 IP 上的 webhook-server

**解决方案**: 不依赖 GitLab webhook，在 CI Pipeline 的 build job 中主动调用 webhook-server

**关键配置**:
1. GitLab Runner 使用 `host` 网络模式
2. webhook-server 使用 `host` 网络模式
3. CI 模板中 webhook payload 必须包含 `before`、`user_name`、`commits` 字段

### 使用方法

直接 git push 即可触发全自动化构建：
```bash
git add .
git commit -m "Add new package"
git push origin main
```

### 恢复方法

详见 `docs/cicd-flow-snapshot-2026-05-19.md`


