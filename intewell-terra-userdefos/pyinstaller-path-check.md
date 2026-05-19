# PyInstaller 打包路径兼容性检查

修改项目目录结构后，确保 PyInstaller 打包和安装后路径不受影响。

## 触发条件
- 项目目录结构发生变化
- 移动/重命名了资源目录
- 修改了打包脚本或 .spec 文件

## 执行步骤

1. **检查路径解析逻辑**
   - 读取主程序顶部的路径变量定义（如 `PROJECT_ROOT`、`GUI_DIR` 等）
   - 确认开发模式和打包模式的路径基础是否正确
   - 典型模式：
   ```python
   if getattr(sys, 'frozen', False):
       PROJECT_ROOT = sys._MEIPASS          # _internal/
   else:
       PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
   ```
   - 注意：不同项目的变量命名和层级关系可能不同

2. **检查 .spec 文件 datas 映射**
   - `datas` 中 `(源目录, 目标名)` 的目标名决定了 `_internal/` 下的目录名
   - 目标名不要随意改，否则安装后路径会断
   - 检查所有 datas 条目是否与实际目录结构一致

3. **检查打包/拷贝脚本**
   - cp 源路径是否指向正确位置
   - spec 模板中的 datas 是否与实际目录一致
   - 安装脚本中的路径引用是否正确

4. **检查安装后路径**
   - 确认安装目录结构（如 `/opt/<app>/`、`/opt/<app>/_internal/`）
   - 确认 `_internal/` 下的目录结构与 spec datas 映射一致

5. **验证各运行模式**
   - **开发模式**：直接运行源码 — 路径基于源码目录
   - **打包模式**：PyInstaller onedir/onefile — 路径基于 `_internal/` 或临时目录
   - **安装后模式**：安装到系统目录 — 路径与打包模式相同

## 关键检查清单
- [ ] 路径基础变量定义是否正确（开发/打包两种模式）
- [ ] .spec datas 目标名是否与代码中引用的目录名一致
- [ ] 打包脚本 cp 源路径是否正确
- [ ] 安装后资源目录结构是否完整
- [ ] 资源文件（图标、配置等）路径是否能正确解析

## 注意事项
- 非 PyInstaller 项目（如 Nuitka、cx_Freeze）的路径解析方式不同，需根据实际工具调整
- onedir 和 onefile 模式的路径解析有差异，onefile 用临时目录
- 如果项目没有安装后模式，可跳过相关检查
