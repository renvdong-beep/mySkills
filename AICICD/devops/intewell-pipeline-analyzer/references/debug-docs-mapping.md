# 调试文档映射表

## 调试文档路径

- `/home/nando/AICICD/docs/debug/add-test-folder-process.md` - 新增测试包流程
- `/home/nando/AICICD/docs/debug/multi-package-parallel-cicd-debug.md` - 多包并行CI/CD
- `/home/nando/AICICD/docs/debug/obs-server-debug.md` - OBS服务调试
- `/home/nando/AICICD/docs/debug/gitlab-runner-debug.md` - GitLab Runner调试
- `/home/nando/AICICD/docs/debug/intewell-packer-debug.md` - Packer ISO构建
- `/home/nando/AICICD/docs/debug/feishu-terminal-bot-debug.md` - 飞书终端机器人

## 问题关键词匹配表

| 错误关键词 | 匹配文档 | 问题类型 |
|-----------|---------|---------|
| webhook | gitlab-webhook-bypass skill | GitLab webhook网络问题 |
| internal error | gitlab-webhook-bypass skill | GitLab webhook返回错误 |
| Host is unreachable | gitlab-webhook-bypass skill | 网络连接失败 |
| OBS does not exist | obs-server-debug.md | OBS项目不存在 |
| OBS 404 | obs-server-debug.md | OBS API返回404 |
| scheduler | obs-server-debug.md | OBS scheduler未运行 |
| scheduled | obs-server-debug.md | OBS构建一直scheduled |
| timeout | obs-server-debug.md | OBS构建超时 |
| Runner pending | gitlab-runner-debug.md | Runner不拉取job |
| Failed to load config | gitlab-runner-debug.md | Runner配置丢失 |
| sync 500 | multi-package-parallel-cicd-debug.md | sync-service错误 |
| Connection refused | multi-package-parallel-cicd-debug.md | 服务连接失败 |
| CVE | cicd-pipeline-services skill | CVE扫描问题 |
