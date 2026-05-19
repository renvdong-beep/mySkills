---
name: intewell-packer
description: Build Intewell OS images using Intewell-unified-packer. Covers Docker build, prebuild_cache structure, app/appset mechanism, OBS repo integration, and multi-arch ISO generation.
tags: [intewell, packer, iso, image-build, aarch64, x86_64, loongarch64, docker, rpm]
---

# Intewell-unified-packer ISO 构建

使用 Intewell-unified-packer 构建 Intewell 机器人操作系统 ISO 镜像，集成 OBS 构建的 RPM 包。

## Triggers

- 构建 Intewell OS ISO 镜像
- 将 OBS 构建的 RPM 集成到 ISO
- 配置 Packer 的 OBS 仓库源
- 调试 Packer 构建失败
- 添加新应用到 ISO

## Architecture

```
OBS 构建 RPM → sync-service 同步 → HTTP 仓库 (createrepo_c)
                                            ↓
Intewell-unified-packer (_internal/)
  ├── build_in_docker.sh ← 入口脚本
  ├── build.sh           ← 核心构建逻辑
  ├── system_cfg/        ← 构建配置 JSON
  ├── prebuild_cache/    ← 缓存 (内核/rootfs/appset)
  │   └── all_appsets/aarch64/xxx.app/  ← 应用包列表
  ├── appset.d/obs.repo  ← OBS 仓库配置
  └── out/package/       ← ISO 输出
```

## Quick Build

```bash
cd /home/nando/Intewell-unified-packer/_internal

# 构建 aarch64 S5000C
bash build_in_docker.sh main_base_aarch64-S5000C.json

# 构建 x86_64
bash build_in_docker.sh main_base_x86_64.json

# 构建自定义配置
bash build_in_docker.sh my_custom_build.json
```

## 配置文件格式

位置: `_internal/system_cfg/`

```json
{
    "applist": [],
    "runlist": ["main.project"],
    "arch": "aarch64",
    "board": ["S5000C"],
    "kernel_version": ["6.12.y"],
    "kernel_config": "intewell-S5000C-rt_defconfig",
    "prebuild_dir": "root@192.168.11.33:/home/openeuler_repo/terra_ci"
}
```

| 字段 | 说明 |
|------|------|
| applist | 应用列表 (空则使用默认) |
| runlist | 构建项目列表 |
| arch | 目标架构: x86_64, aarch64, loongarch64 |
| board | 目标板卡型号 |
| kernel_version | 内核版本分支 |
| kernel_config | 内核配置文件名 |
| prebuild_dir | 预构建缓存目录 (远程或本地) |

## OBS 仓库集成

### 1. 配置 obs.repo

位置: `_internal/appset.d/obs.repo`

```ini
[obs-aarch64]
name=OBS aarch64 Repository
baseurl=http://localhost:8082/
enabled=1
gpgcheck=0
```

**注意**: baseurl 必须指向 createrepo_c 生成过 repodata 的目录对应的 HTTP 服务。

### 2. 添加应用到 ISO

在 `_internal/prebuild_cache/all_appsets/aarch64/` 下创建应用目录:

```bash
# 创建 hello-world.app 目录
mkdir -p _internal/prebuild_cache/all_appsets/aarch64/hello-world.app

# 创建 RPM 列表文件 (每行一个包名，不含版本和架构)
echo "hello-world" > _internal/prebuild_cache/all_appsets/aarch64/hello-world.app/hello-world.rpm.list
```

**关键**: `.app` 目录必须放在 `prebuild_cache/all_appsets/ARCH/` 下，不是项目根的 `prebuild_cache/`。

### 3. 同步 RPM 并更新仓库

```bash
# 1. 从 OBS 同步 RPM 到本地仓库
curl -X POST http://localhost:8090/sync \
  -H "Content-Type: application/json" \
  -d '{"project":"home:Admin","package":"hello-world","repository":"standard","arch":"aarch64"}'

# 2. 更新仓库元数据 (必须！)
createrepo_c /home/nando/AICICD/data/repos/obs-aarch64/

# 3. 确保 HTTP 仓库服务在正确目录运行
cd /home/nando/AICICD/data/repos/obs-aarch64/
python3 -m http.server 8082 &
```

## Common Pitfalls

### 1. prebuild_cache 位置错误

**Symptom**: 构建时提示 `[MISS] Kernel not found locally`，或 app 不被安装到 rootfs

**Root cause**: Docker 挂载 `_internal/` 目录，`build.sh` 的 `TOPDIR=_internal`。外层 `prebuild_cache/` 是独立目录，容器内不可见。

**Fix**: 所有缓存和 app 必须放在 `_internal/prebuild_cache/` 下:
```bash
# 正确位置
_internal/prebuild_cache/all_appsets/aarch64/hello-world.app/

# 错误位置 (容器内不可见)
prebuild_cache/all_appsets/aarch64/hello-world.app/
```

### 2. createrepo_c 未在 sync 后运行

**Symptom**: Packer 构建安装了旧版本包，不是刚 sync 的最新 RPM

**Root cause**: sync-service 只复制 RPM 文件，不更新 repodata。dnf 读取 repodata 发现包，新 RPM 不可见。

**Fix**: 每次 sync 后必须运行:
```bash
createrepo_c /path/to/repo/
```

### 3. HTTP 仓库工作目录不对

**Symptom**: dnf 报错 "Cannot download repodata" 或返回 HTML 错误页面

**Root cause**: `python3 -m http.server` 必须在 RPM 仓库目录启动，否则路径不匹配

**Fix**:
```bash
# 必须先 cd 到仓库目录
cd /home/nando/AICICD/data/repos/obs-aarch64/
python3 -m http.server 8082 &
```

### 4. runlist 安装失败导致 applist 为空

**Symptom**: ISO 中没有安装任何应用包

**Root cause**: runlist 中的项目安装失败时，会级联导致 applist 为空，所有 app 都不安装

**Fix**: 检查 runlist 中每个项目的安装日志，确保基础项目可正常安装

### 5. Docker --platform 参数不支持

**Symptom**: `"--platform" is only supported on a Docker daemon with experimental features enabled`

**Fix**: 修改 `/etc/docker/daemon.json`:
```json
{
  "experimental": true
}
```
```bash
sudo systemctl restart docker
```

### 6. glibc ABI 不兼容

**Symptom**: RPM 安装到 ISO 后运行失败，报 "version `GLIBC_2.35' not found"

**Root cause**: OBS DoD 仓库版本与 Packer rootfs 基线版本不一致。OBS 用 SP3 编译的 RPM 可能链接到 SP3 独有的 ABI 符号。

**铁律**: OBS DoD 仓库版本必须和 Packer rootfs 基线版本一致。

**Fix**: 将 OBS DoD 指向与 rootfs 相同的 SP 版本:
```
SP1 DoD: glibc-2.38-47.oe2403sp1 = Packer rootfs glibc ✅
SP3 DoD: glibc-2.38-29.oe2403 ≠ Packer rootfs glibc ❌
```

## 目录结构

```
_internal/
├── build.sh              ← 核心构建脚本 (TOPDIR)
├── build_in_docker.sh    ← Docker 构建入口
├── system_cfg/           ← 构建配置 JSON
│   ├── main_base_aarch64-S5000C.json
│   ├── main_base_x86_64.json
│   └── main_base_loongarch64.json
├── prebuild_cache/       ← 缓存目录
│   ├── all_appsets/      ← 应用集
│   │   └── aarch64/
│   │       └── hello-world.app/
│   │           └── hello-world.rpm.list
│   ├── all_kernels/      ← 内核缓存
│   └── all_rootfs/       ← 根文件系统
├── appset.d/             ← 仓库配置
│   └── obs.repo
└── out/package/          ← ISO 输出
    └── aarch64/S5000C/
        └── *.iso
```

## ISO 输出验证

```bash
# 查看 ISO 文件
ls -la _internal/out/package/aarch64/S5000C/

# 验证 ISO 中的包
# 挂载 ISO 或解压 ROOTFS.TGZ 检查
mkdir /tmp/rootfs && cd /tmp/rootfs
tar xzf _internal/out/package/aarch64/S5000C/ROOTFS.TGZ
ls usr/bin/hello-world  # 验证二进制存在
```

### 7. build_in_docker.sh 必须在宿主机执行 (铁律)

**Symptom**: ISO 构建失败，提示 `python3: command not found` 或其他依赖缺失

**Root cause**: `build_in_docker.sh` 设计为在宿主机上执行，它会自动启动专门的 Docker 容器进行 ISO 构建。如果在容器内执行，会添加不必要的层级和依赖问题。

**铁律**: `build_in_docker.sh` 必须在宿主机上执行，不能在容器内执行！

**webhook-server 触发 ISO 构建的正确方式**:
```python
def trigger_iso_build(package_name: str, iso_configs: list) -> dict:
    PACKER_DIR = os.getenv("PACKER_DIR", "/home/nando/Intewell-unified-packer")
    for config in iso_configs:
        # 直接在宿主机上执行 build_in_docker.sh
        subprocess.Popen(f"bash {PACKER_DIR}/_internal/build_in_docker.sh {config}",
                        shell=True, cwd=PACKER_DIR)
```

**关键点**:
- webhook-server 通过挂载的 Packer 目录访问脚本
- 使用 `subprocess.Popen` 在宿主机上执行
- `build_in_docker.sh` 会自动创建专门的构建容器
- 不要创建中间容器来运行 `build_in_docker.sh`

### 8. ISO Build Integration with CI Pipeline

**Current state**: ISO build is triggered by webhook-server after Pipeline success (when `intewell.yaml` has `target: iso`).

**Flow**:
```
Developer push → GitLab CI Pipeline (6 stages) → webhook-server monitors → 
  Pipeline success + target=iso → trigger_iso_build() → build_in_docker.sh on host
```

**See**: `cicd-pipeline-services` skill pitfall #48 for implementation details.

### 9. ISO Build Container Missing genisoimage

**Symptom**: ISO build fails with `genisoimage: command not found` during pack.sh

**Root cause**: 
1. `rootfs_openeuler` container's default repo points to unreachable internal FTP
2. Container doesn't have genisoimage pre-installed

**Fix**: Delete default repos, use accessible mirror, install genisoimage before build:
```bash
# In build container startup
rm -f /etc/yum.repos.d/*.repo
echo -e "[OS]\nname=OS\nbaseurl=https://mirrors.aliyun.com/openeuler/openEuler-24.03-LTS-SP1/OS/aarch64/\nenabled=1\ngpgcheck=0" > /etc/yum.repos.d/openeuler.repo
dnf -y install genisoimage
bash build.sh main_base_aarch64-S5000C.json
```

**See**: `cicd-pipeline-services` skill pitfall #52 for complete webhook-server implementation.

### 10. Docker-in-Docker Volume Mount Path Mismatch

**Symptom**: ISO build container can't find `build.sh` even though it exists in the mounted volume

**Root cause**: When webhook-server container has `/packer` mounted from host's `/home/nando/Intewell-unified-packer`, and it starts a new container with `-v /packer/_internal:/userdefos`, the new container receives an EMPTY directory because `/packer` only exists inside webhook-server's namespace, not on the host.

**Fix**: Always use the HOST's actual path for volume mounts when starting containers from within another container:
```python
# WRONG - /packer only exists in webhook-server container's namespace
cmd = f"docker run ... -v /packer/_internal:/userdefos ..."

# CORRECT - use host's actual path
packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"  # Host path
cmd = f"docker run ... -v {packer_internal_path}:/userdefos ..."
```

**Key**: Docker socket (`/var/run/docker.sock`) allows creating sibling containers on the host. Volume mount paths are resolved on the HOST, not in the calling container.

### 11. ISO Build Container Working Directory

**Symptom**: ISO build fails with `build.sh: No such file or directory` even when volume mount is correct

**Root cause**: Container starts in default working directory (usually `/`), not in the mounted volume directory

**Fix**: Use `-w /userdefos` to set working directory to the mounted volume:
```bash
docker run -d --name iso-build-pkgname \
  -v /home/nando/Intewell-unified-packer/_internal:/userdefos \
  -w /userdefos \
  rootfs_openeuler_24.03-lts-sp1_aarch64 \
  bash build.sh main_base_aarch64-S5000C.json
```

**Complete webhook-server trigger_iso_build() implementation**:
```python
def trigger_iso_build(package_name: str, iso_configs: list) -> dict:
    PACKER_DIR = os.getenv("PACKER_DIR", "/home/nando/Intewell-unified-packer")
    packer_internal_path = "/home/nando/Intewell-unified-packer/_internal"  # Host path!
    
    for config in iso_configs:
        container_name = f"iso-build-{package_name}-{config.replace('.json','')}"
        repo_content = "[OS]\\nname=OS\\nbaseurl=https://mirrors.aliyun.com/openeuler/openEuler-24.03-LTS-SP1/OS/aarch64/\\nenabled=1\\ngpgcheck=0"
        
        cmd = f"docker run -d --name {container_name} --privileged --network host --platform linux/arm64 " \
              f"-v {packer_internal_path}:/userdefos -w /userdefos " \
              f"rootfs_openeuler_24.03-lts-sp1_aarch64 /bin/bash -c " \
              f"'rm -f /etc/yum.repos.d/*.repo && echo -e \"{repo_content}\" > /etc/yum.repos.d/openeuler.repo " \
              f"&& dnf -y install genisoimage && bash build.sh {config} 2>&1 | tee /tmp/iso-build.log'"
        
        subprocess.Popen(cmd, shell=True)
```

**Verified**: test100 full-chain automation succeeded with webhook-server v3.4 (2026-05-18)

## Related Skills

- `obs-build-service` - OBS 构建服务部署与调试
- `cicd-pipeline-services` - CI/CD 微服务 (sync, quality-gate, cve-scanner)
