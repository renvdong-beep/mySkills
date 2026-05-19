# 网络配置

配置M1000开发板的网络连接。

## 触发条件
- 用户要求配置网络
- 用户提到"网络配置"、"IP地址"、"DHCP"
- 网络连接有问题

## DHCP配置

```bash
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << 'EOF'
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
ONBOOT=yes
DEVICE=eth0
EOF

systemctl restart NetworkManager
```

## 静态IP配置

```bash
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << 'EOF'
TYPE=Ethernet
BOOTPROTO=none
IPADDR=192.168.137.49
PREFIX=24
GATEWAY=192.168.137.1
DNS1=192.168.137.1
DEFROUTE=yes
ONBOOT=yes
DEVICE=eth0
EOF

systemctl restart NetworkManager
```

## 网络诊断命令

### 检查IP地址
```bash
ip addr show eth0
ip -br addr
```

### 检查路由
```bash
ip route
ip route show default
```

### 检查DNS
```bash
cat /etc/resolv.conf
nslookup google.com
```

### 测试连通性
```bash
ping -c 3 8.8.8.8
ping -c 3 google.com
```

### 检查网络接口状态
```bash
nmcli device status
nmcli connection show
```

## 网络故障排查脚本

```bash
#!/bin/bash
echo "=== 1. 网络接口状态 ==="
ip -br addr

echo -e "\n=== 2. 路由表 ==="
ip route

echo -e "\n=== 3. DNS配置 ==="
cat /etc/resolv.conf

echo -e "\n=== 4. 测试网关 ==="
GATEWAY=$(ip route | grep default | awk '{print $3}')
ping -c 2 $GATEWAY 2>/dev/null && echo "网关可达" || echo "网关不可达"

echo -e "\n=== 5. 测试外网 ==="
ping -c 2 8.8.8.8 2>/dev/null && echo "外网可达" || echo "外网不可达"

echo -e "\n=== 6. 测试DNS ==="
nslookup google.com 2>/dev/null && echo "DNS正常" || echo "DNS异常"
```

## 常见问题解决

### 问题1: 无法获取IP
```bash
# 重启NetworkManager
systemctl restart NetworkManager

# 重新获取DHCP
nmcli connection reload
nmcli connection up eth0
```

### 问题2: 默认网关错误
```bash
# 查看当前网关
ip route show default

# 删除错误网关
ip route del default via 10.192.1.1

# 添加正确网关
ip route add default via 192.168.137.1
```

### 问题3: DNS不工作
```bash
# 临时添加DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 永久配置DNS
nmcli connection modify eth0 ipv4.dns "8.8.8.8,8.8.4.4"
nmcli connection up eth0
```

### 问题4: 双网卡配置
```bash
# eth0: 外网
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << 'EOF'
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
ONBOOT=yes
DEVICE=eth0
EOF

# eth1: 内网
cat > /etc/sysconfig/network-scripts/ifcfg-eth1 << 'EOF'
TYPE=Ethernet
BOOTPROTO=none
IPADDR=10.192.2.2
PREFIX=24
DEFROUTE=no
ONBOOT=yes
DEVICE=eth1
EOF

systemctl restart NetworkManager
```

## M1000网络接口

| 接口 | MAC地址 | 用途 |
|-----|---------|------|
| eth0 | e8:78:29:58:4c:f6 | 主网络接口 |
| eth1 | e8:78:29:58:4c:f7 | 辅助网络接口 |
| wlp193s0u3i2 | - | WiFi接口 |

## 注意事项
- M1000有两个以太网接口
- 配置后需要重启NetworkManager
- DEFROUTE=yes的接口作为默认网关
- DNS可以在接口配置中指定
