# NPU驱动安装与验证

安装Houmo XH2 NPU驱动并验证设备是否正常工作。

## 触发条件
- 用户要求安装NPU驱动
- 用户提到"NPU驱动"、"xh2a"、"npucore"
- NPU设备未检测到

## 执行步骤

1. **检查驱动包是否存在**
   ```bash
   ls -la /var/lib/dkms.tar.gz
   ls -la /usr/local/houmo-drv*
   ```

2. **解压驱动模块**
   ```bash
   tar -xf /var/lib/dkms.tar.gz -C /var/lib/
   # 处理解压路径问题
   mv /var/lib/var/lib/dkms /var/lib/dkms 2>/dev/null
   rm -rf /var/lib/var 2>/dev/null
   ```

3. **复制驱动到内核模块目录**
   ```bash
   cp /var/lib/dkms/xh2_driver/v1.2.0/6.6.10/aarch64/module/xh2a_drv.ko /lib/modules/6.6.10/extra/
   depmod -a
   ```

4. **加载内核驱动**
   ```bash
   modprobe npucore 2>/dev/null || insmod /lib/modules/6.6.10/extra/npucore.ko
   modprobe xh2a_drv 2>/dev/null || insmod /lib/modules/6.6.10/extra/xh2a_drv.ko
   ```

5. **验证驱动加载**
   ```bash
   lsmod | grep -E 'xh2a|npucore'
   ```

6. **验证设备节点**
   ```bash
   ls /dev/xh2a* /dev/npucore
   # 应该看到: xh2a_ipu0, xh2a_ipu1, xh2a_ctl0 等
   ```

7. **设置开机自动加载**
   ```bash
   cat > /etc/modules-load.d/houmo-npu.conf << EOF
   npucore
   xh2a_drv
   EOF
   ```

## 验证命令

```bash
# 检查驱动模块
lsmod | grep xh2a

# 检查设备节点数量
ls /dev/xh2a* /dev/npucore 2>/dev/null | wc -l

# 检查IPU设备
ls /dev/xh2a_ipu*

# 检查HAL库链接
ls -la /usr/local/houmo-drv/hal/lib/libhal_xh2a.so
```

## 常见问题

### 问题1: dkms.tar.gz解压路径错误
**症状:** `/var/lib/var/lib/dkms` 路径存在
**解决:** `mv /var/lib/var/lib/dkms /var/lib/dkms && rm -rf /var/lib/var`

### 问题2: HAL库找不到
**症状:** `Failed to load: libhal_xh2a.so`
**解决:** `ln -sf /usr/local/houmo-drv-xh2_v1.2.0 /usr/local/houmo-drv`

### 问题3: 设备节点不存在
**症状:** `ls: cannot access '/dev/xh2a*': No such file or directory`
**解决:** 检查驱动是否加载，重新执行modprobe

## 预期结果
- 2个NPU设备 (Device 0, Device 1)
- 每个设备24GB显存
- 设备节点: /dev/xh2a_ipu0, /dev/xh2a_ipu1, /dev/npucore

## 注意事项
- 内核版本必须匹配 (6.6.10)
- 需要root权限
- HAL库软链接必须正确
