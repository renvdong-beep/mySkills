# Docker 跨架构构建调试

调试 Docker 多架构构建（aarch64/x86_64/loongarch64）相关问题。

## 触发条件
- Docker 构建失败
- 跨架构构建报错
- 用户提到"docker"、"容器"、"架构"、"qemu"

## 执行步骤

1. **确认当前环境**
   ```bash
   docker version
   docker info --format '{{.Architecture}}'
   # 检查 binfmt 支持
   ls /proc/sys/fs/binfmt_misc/ | grep qemu
   ```

2. **常见问题排查**

   **问题A：binfmt 未配置**
   - 症状：非本机架构容器无法启动或立即退出
   - 解决：`docker run --privileged --rm tonistiigi/binfmt --install all`

   **问题B：Docker 镜像不存在**
   - 症状：`Unable to find image 'xxx:latest' locally`
   - 解决：检查镜像 tar 文件路径，`docker load -i <tar文件>`

   **问题C：挂载目录为空**
   - 症状：容器内挂载点目录为空
   - 原因：SELinux 限制
   - 解决：加 `:z` 或 `:Z` 选项，`-v /path:/container_path:z`

   **问题D：平台不匹配**
   - 症状：`exec user process caused: exec format error`
   - 原因：容器镜像架构与 `--platform` 参数不匹配
   - 解决：确认 `--platform linux/arm64` 等参数与镜像一致

   **问题E：容器内命令未在容器内执行**
   - 症状：`cd` 和后续命令在宿主机执行
   - 原因：docker run 后的命令未用 `bash -c` 包裹
   - 解决：`docker run ... image bash -c "cd /path; cmd"`

3. **验证**
   - `docker run --rm --platform <arch> <image> uname -m` 确认架构
   - 检查容器内文件是否完整
   - 检查构建输出是否正常

## 注意事项
- loongarch64 架构可能需要特定的 QEMU 版本支持
- Docker 镜像加载是架构相关的，aarch64 的 tar 不能在 x86_64 上直接 load（需要 binfmt）
- `--privileged` 是 binfmt 注册所需，生产环境慎用
