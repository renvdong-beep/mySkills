# 系统备份与恢复

备份和恢复M1000开发板系统。

## 触发条件
- 用户要求备份系统
- 用户提到"系统备份"、"恢复系统"
- 需要迁移或恢复系统

## 备份方法

### 方法1: 备份到远程服务器

#### 备份boot分区
```bash
# 在开发板执行
sudo dd if=/dev/nvme0n1p1 bs=4M | ssh user@server 'cat > /backup/boot.img'
```

#### 备份系统分区(压缩)
```bash
# 在开发板执行
sudo tar -czpf - --exclude=/proc --exclude=/sys --exclude=/dev \
    --exclude=/tmp --exclude=/run --exclude=/mnt --exclude=/media / | \
    ssh user@server 'cat > /backup/rootfs.tar.gz'
```

### 方法2: 备份到本地文件

#### 备份boot分区
```bash
dd if=/dev/nvme0n1p1 of=/mnt/usb/boot.img bs=4M status=progress
```

#### 备份系统分区
```bash
tar -czpf /mnt/usb/rootfs.tar.gz \
    --exclude=/proc --exclude=/sys --exclude=/dev \
    --exclude=/tmp --exclude=/run --exclude=/mnt --exclude=/media /
```

## 恢复方法

### 恢复boot分区
```bash
# 从远程服务器恢复
ssh user@server 'cat /backup/boot.img' | dd of=/dev/nvme0n1p1 bs=4M status=progress

# 从本地文件恢复
dd if=/mnt/usb/boot.img of=/dev/nvme0n1p1 bs=4M status=progress
```

### 恢复系统分区
```bash
# 挂载目标分区
mount /dev/nvme0n1p2 /mnt

# 从远程服务器恢复
ssh user@server 'cat /backup/rootfs.tar.gz' | tar -xzf - -C /mnt

# 从本地文件恢复
tar -xzf /mnt/usb/rootfs.tar.gz -C /mnt

# 同步并卸载
sync && umount /mnt
```

## 完整备份脚本

```bash
#!/bin/bash
# 系统完整备份脚本

SERVER="user@192.168.137.103"
BACKUP_DIR="/home/user/skysi/backup"

echo "=== 1. 备份boot分区 ==="
dd if=/dev/nvme0n1p1 bs=4M | ssh ${SERVER} "cat > ${BACKUP_DIR}/boot.img"

echo "=== 2. 备份系统分区 ==="
tar -czpf - --exclude=/proc --exclude=/sys --exclude=/dev \
    --exclude=/tmp --exclude=/run --exclude=/mnt --exclude=/media / | \
    ssh ${SERVER} "cat > ${BACKUP_DIR}/rootfs.tar.gz"

echo "=== 3. 备份内核和设备树 ==="
ssh ${SERVER} "mkdir -p ${BACKUP_DIR}"
scp /boot/Image ${SERVER}:${BACKUP_DIR}/
scp /boot/m1000-aimodule.dtb ${SERVER}:${BACKUP_DIR}/

echo "=== 备份完成 ==="
ssh ${SERVER} "ls -lh ${BACKUP_DIR}/"
```

## 完整恢复脚本

```bash
#!/bin/bash
# 系统完整恢复脚本
# 注意: 必须从NFS启动后执行

SERVER="user@192.168.137.103"
BACKUP_DIR="/home/user/skysi/backup"

echo "=== 1. 检查NVMe设备 ==="
lsblk /dev/nvme0n1

echo "=== 2. 恢复boot分区 ==="
ssh ${SERVER} "cat ${BACKUP_DIR}/boot.img" | dd of=/dev/nvme0n1p1 bs=4M status=progress

echo "=== 3. 恢复系统分区 ==="
mount /dev/nvme0n1p2 /mnt
ssh ${SERVER} "cat ${BACKUP_DIR}/rootfs.tar.gz" | tar -xzf - -C /mnt

echo "=== 4. 更新fstab ==="
sed -i 's|/dev/sda1|/dev/nvme0n1p1|g' /mnt/etc/fstab
sed -i 's|/dev/sda2|/dev/nvme0n1p2|g' /mnt/etc/fstab

echo "=== 5. 同步并卸载 ==="
sync && umount /mnt

echo "=== 恢复完成 ==="
```

## 新NVMe分区创建

```bash
# 创建GPT分区表
echo -e 'g\nw\n' | fdisk /dev/nvme0n1

# 创建boot分区 (3GB)
echo -e 'n\n1\n2048\n+3G\nt\n1\nw\n' | fdisk /dev/nvme0n1

# 创建root分区 (剩余空间)
echo -e 'n\n2\n\n\nw\n' | fdisk /dev/nvme0n1

# 格式化
mkfs.vfat -F 32 /dev/nvme0n1p1
mkfs.ext4 -F /dev/nvme0n1p2
```

## 备份文件大小参考

| 内容 | 大小 |
|-----|------|
| boot分区镜像 | ~2GB |
| 系统分区压缩 | ~300MB-20GB |
| 内核镜像 | ~27MB |
| 设备树 | ~87KB |

## 注意事项
- 系统恢复必须从NFS启动执行
- 不能在运行中的系统上恢复自身
- 备份前确保有足够存储空间
- 恢复后检查fstab配置
