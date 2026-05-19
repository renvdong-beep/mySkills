# Git 提交规范与工作流

规范 Git 提交和分支管理，保持仓库历史清晰。

## 触发条件
- 用户要求提交代码
- 用户提到"commit"、"分支"、"merge"
- 需要创建 PR/MR

## 执行步骤

1. **提交前检查**
   - `git status` 确认改动范围
   - `git diff` 确认改动内容
   - 排除不应提交的文件（.env、临时配置、日志等）

2. **提交信息规范**
   格式：`<类型>: <简要描述>`
   
   常用类型：
   - `feat`: 新功能
   - `fix`: 修复 bug
   - `refactor`: 重构
   - `docs`: 文档
   - `chore`: 构建/工具变动
   - `perf`: 性能优化
   - `test`: 测试

   示例：
   ```
   feat: 新增外网构建缓存支持
   fix: 修复Docker容器内命令执行问题
   refactor: 将intewell-terra_appset移至gui目录
   ```

3. **分支策略**
   - `main/master`：生产版本
   - `dev`：开发主线
   - `feat/xxx`：功能分支
   - `fix/xxx`：修复分支
   - 功能分支从 dev 创建，完成后通过 MR 合并

4. **提交操作**
   ```bash
   # 指定文件添加，避免 git add -A
   git add <file1> <file2> <dir>/
   git commit -m "<类型>: <描述>"
   ```

5. **推送与合并**
   - 新分支：`git push -u origin <分支名>`
   - 已有分支：`git push origin <分支名>`
   - 在 Git 平台创建 MR/PR 进行 code review

## 注意事项
- 不要提交敏感信息（密码、密钥、.env）
- 不要用 `git add -A` 或 `git add .`，避免误提交
- 优先创建新 commit 而非 amend（除非明确要求）
- 合并冲突时逐文件解决，不要盲目选一方
