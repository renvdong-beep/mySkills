# PyInstaller 打包调试

调试 PyInstaller 打包过程和打包后的运行问题。

## 触发条件
- PyInstaller 打包失败
- 打包后程序运行报错（ModuleNotFoundError、FileNotFoundError 等）
- 用户提到"pyinstaller"、"打包"、"spec"

## 执行步骤

1. **打包阶段问题**

   **问题A：ModuleNotFoundError**
   - 原因：动态导入的模块 PyInstaller 无法自动检测
   - 解决：在 spec 的 `hiddenimports` 中添加
   ```python
   hiddenimports=['module_name', 'package.submodule']
   ```

   **问题B：数据文件未包含**
   - 原因：非 Python 文件默认不打包
   - 解决：在 spec 的 `datas` 中添加
   ```python
   datas=[('源目录', '目标目录')]
   ```

   **问题C：动态库缺失**
   - 原因：C 扩展的依赖库未包含
   - 解决：在 spec 的 `binaries` 中添加，或用 `--collect-all`

2. **运行阶段问题**

   **问题A：FileNotFoundError（资源文件找不到）**
   - 原因：路径未适配 `_MEIPASS`
   - 调试：在程序中打印 `sys._MEIPASS` 确认资源目录
   - 解决：用 `sys._MEIPASS` 作为资源路径基础

   **问题B：onedir vs onefile 路径差异**
   - onedir：`sys._MEIPASS` = `_internal/` 目录，持久存在
   - onefile：`sys._MEIPASS` = 临时解压目录，每次运行不同
   - 注意 onefile 模式下不要缓存 `_MEIPASS` 路径

   **问题C：动态导入失败**
   - 调试：`pyinstaller --debug=all xxx.spec` 重新打包
   - 运行时查看详细错误信息

3. **调试技巧**
   - 打包时加 `--debug=all` 获取详细信息
   - 运行时加 `--console` 查看控制台输出（spec 中 `console=True`）
   - 检查 `build/xxx/warn-xxx.txt` 中的警告信息
   - 用 `pyi-archive_viewer dist/xxx` 查看打包内容

## 注意事项
- PySide6/PyQt 需要特殊处理：`hiddenimports` 和插件收集
- 修改 spec 后要删除 `build/` 和 `dist/` 重新打包
- onedir 模式启动更快，适合含大量资源的情况
- onefile 模式单文件分发，但启动慢（需解压）
