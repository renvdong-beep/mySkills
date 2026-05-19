# HLAWOllama服务管理

管理Houmo LLM推理服务的启动、停止、状态检查。

## 触发条件
- 用户要求管理LLM服务
- 用户提到"HLAWOllama"、"ollama服务"、"推理服务"
- 需要启动/停止/重启服务

## 服务管理命令

### 查看服务状态
```bash
systemctl status HLAWOllama --no-pager
```

### 启动服务
```bash
systemctl start HLAWOllama
```

### 停止服务
```bash
systemctl stop HLAWOllama
```

### 重启服务
```bash
systemctl restart HLAWOllama
```

### 启用开机自启
```bash
systemctl enable HLAWOllama
```

### 禁用开机自启
```bash
systemctl disable HLAWOllama
```

## 日志查看

### 查看实时日志
```bash
journalctl -u HLAWOllama -f
```

### 查看最近日志
```bash
journalctl -u HLAWOllama -n 50
```

### 查看特定时间段日志
```bash
journalctl -u HLAWOllama --since "10 minutes ago"
journalctl -u HLAWOllama --since "2026-04-24 10:00"
```

### 搜索关键词
```bash
journalctl -u HLAWOllama | grep -iE "error|fail|HoumoNPU"
```

## 环境变量设置

```bash
export LD_LIBRARY_PATH=/root/houmo-HLIELLama-xh2/lib:/usr/local/houmo-drv/hal/lib:$LD_LIBRARY_PATH
export OLLAMA_MODELS=/root/models
export PATH=/root/houmo-HLIELLama-xh2/bin:$PATH
```

## 模型管理

### 列出已加载模型
```bash
/root/houmo-HLIELLama-xh2/bin/hlaw_ollama list
```

### 显示模型详情
```bash
/root/houmo-HLIELLama-xh2/bin/hlaw_ollama show qwen3-14b
```

### 删除模型
```bash
/root/houmo-HLIELLama-xh2/bin/hlaw_ollama rm qwen3-14b
```

### 创建模型
```bash
cat > /tmp/Modelfile << EOF
FROM /root/models/model.gguf
EOF
/root/houmo-HLIELLama-xh2/bin/hlaw_ollama create model-name -f /tmp/Modelfile
```

## API检查

### 检查服务版本
```bash
curl -s http://localhost:11434/api/version
```

### 检查模型列表
```bash
curl -s http://localhost:11434/api/tags
```

### 测试推理
```bash
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-14b",
  "prompt": "你好",
  "stream": false
}'
```

## 服务配置文件

位置: `/etc/systemd/system/HLAWOllama.service`

```ini
[Unit]
Description=HLAWOllama Service
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/root/houmo-HLIELLama-xh2
ExecStart=/root/houmo-HLIELLama-xh2/bin/hlaw_ollama serve
User=root
Group=root
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/root/models"
Environment="LD_LIBRARY_PATH=/root/houmo-HLIELLama-xh2/lib:/usr/local/houmo-drv/hal/lib"
Environment="PATH=/root/houmo-HLIELLama-xh2/bin"

[Install]
WantedBy=multi-user.target
```

修改配置后需要:
```bash
systemctl daemon-reload
systemctl restart HLAWOllama
```

## 注意事项
- 服务需要NPU驱动正确加载
- LD_LIBRARY_PATH必须包含HAL库路径
- 模型文件路径必须正确
- 默认端口11434
