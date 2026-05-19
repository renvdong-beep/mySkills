# 推理性能测试

测试LLM推理性能，验证SDK功能是否正常。

## 触发条件
- 用户要求测试推理性能
- 用户提到"推理测试"、"性能测试"、"tokens/s"
- 需要验证SDK功能

## 快速测试命令

### 简单推理测试
```bash
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-14b",
  "prompt": "你好",
  "stream": false
}'
```

### 流式推理测试
```bash
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-14b",
  "prompt": "你好",
  "stream": true
}'
```

## 完整性能测试脚本

```bash
#!/bin/bash
# 推理性能测试脚本

echo "=== 1. 检查服务 ==="
curl -s http://localhost:11434/api/version
echo ""

echo "=== 2. 检查模型 ==="
curl -s http://localhost:11434/api/tags | python3 -c "
import sys, json
d = json.load(sys.stdin)
for m in d.get('models', []):
    print(f\"模型: {m['name']}\")
    print(f\"大小: {m['size']/1e9:.1f} GB\")
    print(f\"参数: {m['details']['parameter_size']}\")
    print(f\"量化: {m['details']['quantization_level']}\")
"

echo ""
echo "=== 3. 推理测试 ==="
time curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-14b",
  "prompt": "请用100字介绍一下人工智能",
  "stream": false
}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('响应:', d.get('response', '')[:200], '...')
print('---')
print('生成Token数:', d.get('eval_count', 0))
print('评估耗时:', round(d.get('eval_duration', 0)/1e9, 2), '秒')
if d.get('eval_duration', 0) > 0:
    speed = d.get('eval_count', 0) / (d.get('eval_duration', 0)/1e9)
    print('推理速度:', round(speed, 2), 'tokens/s')
"

echo ""
echo "=== 测试完成 ==="
```

## 性能指标计算

```python
# 推理速度计算公式
推理速度 = 生成Token数 / 评估耗时(秒)

# 示例
生成Token数: 412
评估耗时: 20.81 秒
推理速度 = 412 / 20.81 = 19.8 tokens/s
```

## API响应字段说明

| 字段 | 说明 |
|-----|------|
| eval_count | 生成的Token数量 |
| eval_duration | 评估耗时(纳秒) |
| prompt_eval_count | 输入提示Token数 |
| prompt_eval_duration | 输入处理耗时(纳秒) |
| total_duration | 总耗时(纳秒) |
| response | 生成的文本内容 |

## 性能基准参考

| 模型 | 量化 | 推理速度 | 显存占用 |
|-----|------|---------|---------|
| qwen3-14b | Q4_0 | ~20 tokens/s | 48GB (双卡) |
| qwen3-14b | Q8_0 | ~15 tokens/s | 更高 |

## 检查NPU使用情况

```bash
# 查看服务日志中的NPU信息
journalctl -u HLAWOllama | grep -iE "device|mem_total|HoumoNPU"

# 预期输出:
# [HoumoNPU] hm_sys_get_device_info returned: 2 devices
# [HoumoNPU] Device 0: mem_total=24448, mem_used=0
# [HoumoNPU] Device 1: mem_total=24448, mem_used=0
```

## 批量测试

```bash
# 多次测试取平均值
for i in {1..5}; do
    echo "=== 测试 $i ==="
    curl -s http://localhost:11434/api/generate -d '{
      "model": "qwen3-14b",
      "prompt": "请用100字介绍一下人工智能",
      "stream": false
    }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('eval_duration', 0) > 0:
    speed = d.get('eval_count', 0) / (d.get('eval_duration', 0)/1e9)
    print(f'推理速度: {speed:.2f} tokens/s')
"
done
```

## 注意事项
- 服务必须正常运行
- 模型必须已加载
- 首次推理可能较慢(模型加载)
- 测试结果受输入长度影响
