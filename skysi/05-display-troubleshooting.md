# 显示问题排查

排查M1000开发板的显示输出问题。

## 触发条件
- 用户报告显示问题
- 用户提到"显示不工作"、"黑屏"、"HDMI"、"DP"
- 需要排查显示输出

## 排查步骤

### 1. 检查显示管理器状态
```bash
systemctl status lightdm --no-pager
```

### 2. 检查DRM设备
```bash
ls -la /sys/class/drm/
```

### 3. 检查显示连接状态
```bash
for i in 1 2 3 4; do
    if [ -f "/sys/class/drm/card0-DP-$i/status" ]; then
        echo "DP-$i: $(cat /sys/class/drm/card0-DP-$i/status)"
    fi
done
```

### 4. 检查GPU驱动
```bash
lsmod | grep -E 'mtgpu|mtdisp'
```

### 5. 检查显示模式
```bash
for i in 1 2 3 4; do
    status=$(cat /sys/class/drm/card0-DP-$i/status 2>/dev/null)
    if [ "$status" = "connected" ]; then
        echo "=== DP-$i 支持的模式 ==="
        cat /sys/class/drm/card0-DP-$i/modes | head -5
    fi
done
```

### 6. 检查内核日志
```bash
dmesg | grep -iE 'mtdisp|DisplayPort|link training|hdmi' | tail -20
```

## 一键排查脚本

```bash
#!/bin/bash
echo "=== 1. 显示管理器状态 ==="
systemctl is-active lightdm

echo -e "\n=== 2. DRM设备 ==="
ls /sys/class/drm/ | grep -E "card|DP|HDMI"

echo -e "\n=== 3. 显示连接状态 ==="
for i in 1 2 3 4; do
    if [ -f "/sys/class/drm/card0-DP-$i/status" ]; then
        status=$(cat /sys/class/drm/card0-DP-$i/status)
        enabled=$(cat /sys/class/drm/card0-DP-$i/enabled 2>/dev/null)
        echo "DP-$i: $status, enabled=$enabled"
    fi
done

echo -e "\n=== 4. GPU驱动 ==="
lsmod | grep -E 'mtgpu|mtdisp' || echo "GPU驱动未加载"

echo -e "\n=== 5. 显示日志 ==="
dmesg | grep -iE 'DisplayPort.*loaded|link training success' | tail -5
```

## 常见问题解决

### 问题1: LightDM启动失败
```bash
# 安装greeter
dnf install -y lightdm-gtk
systemctl restart lightdm
```

### 问题2: 显示器未检测到
```bash
# 检查连接
cat /sys/class/drm/card0-DP-*/status

# 如果都是disconnected，检查:
# 1. 线缆是否连接
# 2. 是否使用了正确的接口
# 3. 是否需要DP-to-HDMI转接线
```

### 问题3: 黑屏但有信号
```bash
# 重启显示管理器
systemctl restart lightdm

# 检查Xorg日志
cat /var/log/Xorg.0.log | tail -50
```

## M1000显示架构说明

**重要:** M1000开发板只有DisplayPort (DP) 输出接口，没有原生HDMI。

| 组件 | 说明 |
|-----|------|
| GPU | 摩尔线程 mtgpu |
| 显示控制器 | 4路 DisplayPort (DP-1 ~ DP-4) |
| 物理接口 | DP接口 |
| HDMI支持 | 需要DP-to-HDMI转接线 |

### 显示输出路径
```
GPU (mtgpu) → DisplayPort控制器 (mtdisp) → DP物理接口 → [DP-to-HDMI转接线] → 显示器
```

## 验证显示正常

```bash
# 检查DP-2是否连接并启用
cat /sys/class/drm/card0-DP-2/status   # 应显示 "connected"
cat /sys/class/drm/card0-DP-2/enabled  # 应显示 "enabled"

# 检查显示模式
cat /sys/class/drm/card0-DP-2/modes    # 应显示支持的分辨率
```

## 注意事项
- M1000没有原生HDMI，只有DP
- 使用HDMI显示器需要DP-to-HDMI转接线
- 建议使用主动式转接线(带芯片)
- 检查是否使用了正确的DP接口(有4个)
