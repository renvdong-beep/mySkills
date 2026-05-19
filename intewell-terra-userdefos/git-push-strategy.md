# 大改动 Git 推送策略

目录结构和文件都有重大变化时，安全推送到远程仓库。

## 触发条件
- 用户需要推送包含大量改动的代码到 git
- 新增目录、修改多个文件
- 用户提到"推送"、"git push"、"大改动"

## 执行步骤

1. **检查当前状态**
   ```bash
   git status          # 查看改动范围
   git remote -v       # 确认远程仓库
   git branch -a       # 查看分支
   git log --oneline -5  # 查看最近提交
   ```

2. **评估改动范围**
   - 新增目录数量
   - 修改文件数量
   - 是否影响其他开发者的工作

3. **推荐策略**

   **策略A：新分支 + MR（推荐）**
   - 适合：改动大、有其他开发者、需要 review
   ```bash
   git checkout -b <新分支名>
   git add <具体文件和目录>
   git commit -m "<提交信息>"
   git push -u origin <新分支名>
   # 然后在 GitLab/GitHub 上创建 Merge Request / Pull Request
   ```

   **策略B：直接推主分支**
   - 适合：改动确认无误、自己是唯一开发者、需要立即生效
   ```bash
   git add <具体文件和目录>
   git commit -m "<提交信息>"
   git push origin <分支名>
   ```

4. **提交规范**
   - commit message 简洁说明改动目的
   - `git add` 指定具体文件，不要用 `git add -A` 避免误提交临时文件
   - 排除工具目录、日志、缓存等无关文件

## 注意事项
- 推送前确认在目标环境已验证通过
- 不要提交临时配置文件
- 不要提交环境差异文件（含环境特定 IP/路径的配置）
- 如果 push 被拒绝（远端有新提交），先 pull 再 push
- 根据项目实际使用的 Git 平台（GitLab/GitHub/Gitea）调整 MR/PR 流程
