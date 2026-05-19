# 系统硬件信息收集

快速收集M1000开发板的硬件信息，用于文档记录或问题排查。

## 触发条件
- 用户要求收集硬件信息
- 用户提到"硬件信息"、"系统配置"、"设备信息"
- 需要记录或排查硬件问题

## 执行步骤

1. **收集系统信息**
   ```bash
   cat /etc/os-release | grep -E "^NAME|^VERSION"
   uname -a
   ```

2. **收集CPU信息**
   ```bash
   lscpu | grep -E "^Architecture|^CPU\(s\)|^Model name|^CPU MHz"
   cat /proc/cpuinfo | grep "model name" | head -1
   ```

3. **收集内存信息**
   ```bash
   free -h
   cat /proc/meminfo | grep -E "MemTotal|MemAvailable"
   ```

4. **收集存储设备信息**
   ```bash
   lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
   df -h
   ```

5. **收集GPU/NPU驱动信息**
   ```bash
   lsmod | grep -E 'mtgpu|xh2a|npucore'
   ls /dev/xh2a* /dev/npucore 2>/dev/null | wc -l
   ```

6. **收集网络接口信息**
   ```bash
   ip addr | grep -E "^[0-9]|inet " | grep -v "127.0.0.1"
   ```

7. **收集显示设备信息**
   ```bash
   ls /sys/class/drm/ | grep -E "card|DP|HDMI"
   for i in 1 2 3 4; do
       cat /sys/class/drm/card0-DP-$i/status 2>/dev/null && echo "DP-$i"
   done
   ```

## 一键脚本

```bash
#!/bin/bash
echo "=== 系统信息 ==="
cat /etc/os-release | grep -E "^NAME|^VERSION"
uname -r

echo -e "\n=== CPU信息 ==="
lscpu | grep -E "^Architecture|^CPU\(s\)|^Model name"

echo -e "\n=== 内存信息 ==="
free -h | grep -E "Mem|Swap"

echo -e "\n=== 存储设备 ==="
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS 2>/dev/null || lsblk

echo -e "\n=== GPU/NPU驱动 ==="
lsmod | grep -E 'mtgpu|xh2a|npucore' || echo "未加载GPU/NPU驱动"

echo -e "\n=== 网络接口 ==="
ip -br addr

echo -e "\n=== 显示设备 ==="
ls /sys/class/drm/ 2>/dev/null | grep -E "DP|HDMI"
```

## 输出格式
生成Markdown表格格式，便于记录到文档：
```
| 项目 | 信息 |
|-----|------|
| 板子型号 | M1000 MQ50 Board |
| CPU | 12核 Cortex-A78 |
| 内存 | 32 GB |
| ...
```

## 注意事项
- 需要root权限查看某些设备信息
- NPU设备节点需要驱动正确加载
- 显示设备检查需要DRM驱动正常
