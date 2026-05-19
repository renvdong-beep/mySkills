# GitLab CI + OBS Integration Patterns

## 通用 CI 模板设计

### 核心变量

| 变量 | 用途 | 默认值 |
|------|------|--------|
| PACKAGE_NAME | OBS子项目名和spec文件名 | CI_PROJECT_NAME |
| PACKAGE_DIR | 仓库中源码目录名 | PACKAGE_NAME |
| OBS_INTEGRATION_PROJECT | 集成项目名 | home:Admin |
| OBS_POLL_INTERVAL | 构建等待轮询间隔(秒) | 30 |
| OBS_POLL_TIMEOUT | 构建等待超时(秒) | 600 |

### 5阶段流水线

```
build → obs-trigger → obs-wait → sync → update-repo
```

1. **build**: 打包源码 tar.gz
2. **obs-trigger**: 上传源码到OBS子项目，触发构建
3. **obs-wait**: 轮询sync-service的obs-build-status端点，等待构建完成
4. **sync**: 从集成项目sync-all同步RPM到本地仓库
5. **update-repo**: 调用sync-service的update-repo端点更新repodata

### OBS子项目映射规则

- GitLab项目 `renwd/hello-world` → OBS子项目 `home:Admin:hello-world`
- CI_PROJECT_NAME 自动映射，但需要 PACKAGE_NAME 变量覆盖（因为GitLab项目名可能和包名不同）
- 例如：GitLab项目名 `intewell-test`，但包名是 `hello-world`，需要设置 `PACKAGE_NAME=hello-world`

## 关键陷阱

### 1. artifacts 路径不支持变量展开

```yaml
# ❌ 错误 - GitLab CI不会展开artifacts中的变量
artifacts:
  paths:
    - "${PACKAGE_NAME}-1.0.0.tar.gz"

# ✅ 正确 - 用通配符
artifacts:
  paths:
    - "*.tar.gz"
```

### 2. CI_PROJECT_NAME ≠ 包名

GitLab项目名(CI_PROJECT_NAME)可能和OBS包名不同。必须提供PACKAGE_NAME变量覆盖。
当前项目：CI_PROJECT_NAME=intewell-test, PACKAGE_NAME=hello-world

### 3. GitLab Runner Tag 匹配问题

给Runner添加tag后，Pipeline可能直接failed无jobs创建：
- API显示Runner有tag，但项目Runner列表可能显示空tag
- 可能需要重启Runner容器刷新配置
- 备选方案：CI模板和Runner都不用tag，或确保tag完全一致

### 4. OBS _link 包上传

在集成项目创建_link包链接子项目：
```xml
<link project="home:Admin:hello-world" package="hello-world"/>
```
上传方式必须用 `-T` 文件上传（不能用 `--data-binary @-` 管道方式，会丢失数据）：
```bash
echo '<link project="home:Admin:hello-world" package="hello-world"/>' > /tmp/_link
curl -u Admin:admin123 -X PUT -T /tmp/_link \
  "http://localhost:4455/source/home:Admin/hello-world/_link"
```

### 5. sync-service 新端点

| 端点 | 方法 | 用途 |
|------|------|------|
| /update-repo/{arch} | POST | 运行createrepo_c更新仓库元数据 |
| /obs-build-status/{project}/{package} | GET | 查询OBS构建状态(返回all_done+各架构状态) |
| /sync-all/{project}/{repo}/{arch} | POST | 同步项目所有RPM到本地仓库 |

### 6. Docker容器代码更新

sync-service等服务的代码打包在Docker镜像中，不是挂载的。修改代码后必须：
1. 重新构建镜像：`docker build -t sync-service:latest .`
2. 停掉旧容器：`docker stop sync-service && docker rm sync-service`
3. 用新镜像启动：`docker run -d --name sync-service --network host ...`
4. 仅 `docker restart` 不会加载新代码
