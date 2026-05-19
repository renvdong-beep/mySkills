# 日志分析

快速分析系统日志，定位问题。

## 触发条件
- 用户要求分析日志
- 用户提到"日志"、"log"、"错误"
- 需要排查问题

## 常用日志命令

### 内核日志
```bash
# 查看最近内核日志
dmesg | tail -50

# 实时查看内核日志
dmesg -w

# 搜索关键词
dmesg | grep -iE 'error|fail|warn'
dmesg | grep -i 'gpu'
dmesg | grep -i 'npu'
```

### 系统日志
```bash
# 查看系统日志
journalctl -xe

# 实时查看
journalctl -f

# 查看最近N条
journalctl -n 100

# 查看本次启动日志
journalctl -b

# 查看上次启动日志
journalctl -b -1
```

### 服务日志
```bash
# 查看特定服务日志
journalctl -u HLAWOllama -f
journalctl -u lightdm -n 50
journalctl -u sshd --since "1 hour ago"
```

## 日志分析脚本

```bash
#!/bin/bash
echo "=== 1. 内核错误 ==="
dmesg | grep -iE 'error|fail|warn' | tail -20

echo -e "\n=== 2. GPU/NPU相关 ==="
dmesg | grep -iE 'gpu|npu|mtgpu|xh2a' | tail -10

echo -e "\n=== 3. 显示相关 ==="
dmesg | grep -iE 'drm|dp|hdmi|display' | tail -10

echo -e "\n=== 4. 存储相关 ==="
dmesg | grep -iE 'nvme|sd|disk' | tail -10

echo -e "\n=== 5. 网络相关 ==="
dmesg | grep -iE 'eth|net|link' | tail -10

echo -e "\n=== 6. 系统服务错误 ==="
journalctl -p err -n 20
```

## 按组件查看日志

### GPU/显示
```bash
# GPU驱动日志
dmesg | grep -i mtgpu

# 显示驱动日志
dmesg | grep -i mtdisp

# DRM日志
dmesg | grep -i drm
```

### NPU
```bash
# NPU驱动日志
dmesg | grep -iE 'xh2a|npucore'

# NPU服务日志
journalctl -u HLAWOllama | grep -iE 'device|mem_total|HoumoNPU'
```

### 存储
```bash
# NVMe日志
dmesg | grep -i nvme

# 磁盘错误
dmesg | grep -iE 'I/O error|sector|ATA'
```

### 网络
```bash
# 网络接口日志
dmesg | grep -i eth

# NetworkManager日志
journalctl -u NetworkManager -n 50
```

## 日志级别说明

| 级别 | 说明 |
|-----|------|
| emerg | 系统不可用 |
| alert | 必须立即处理 |
| crit | 严重错误 |
| err | 错误 |
| warn | 警告 |
| notice | 正常但重要 |
| info | 信息 |
| debug | 调试信息 |

## 按级别过滤

```bash
# 只显示错误及以上
journalctl -p err

# 显示警告及以上
journalctl -p warning

# 显示所有级别
journalctl -p debug
```

## 时间过滤

```bash
# 最近时间
journalctl --since "1 hour ago"
journalctl --since "10 minutes ago"
journalctl --since "2026-04-24 10:00"

# 时间范围
journalctl --since "2026-04-24 10:00" --until "2026-04-24 12:00"
```

## 日志文件位置

| 日志 | 位置 |
|-----|------|
| 内核日志 | /var/log/dmesg |
| 系统日志 | /var/log/messages |
| 安全日志 | /var/log/secure |
| 启动日志 | /var/log/boot.log |
| Xorg日志 | /var/log/Xorg.0.log |

## 注意事项
- dmesg只显示内核环形缓冲区
- journalctl显示systemd管理的日志
- 某些日志需要root权限
- 日志可能被logrotate轮转
