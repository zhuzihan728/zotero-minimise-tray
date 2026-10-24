# zotero-minimise-tray

Windows 专用 Zotero 插件，面向 Zotero 7–10。关闭主窗口时隐藏到系统托盘，Zotero 继续运行，同步及 Connector 保持可用。独立的阅读器窗口保持原有关闭行为。

## 安装

1. 下载 [`dist/zotero-mini-tray-0.2.0.xpi`](dist/zotero-mini-tray-0.2.0.xpi)。开发者也可以运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1` 重新构建。
2. 在 Zotero 的「工具 → 插件」中，点击齿轮 →「Install Add-on From File / 从文件安装插件」。
3. 选择 `dist/zotero-mini-tray-0.2.0.xpi`。

## 使用

- 点击主窗口的 × 或按 Alt+F4：隐藏到系统托盘，不退出。
- 单击托盘图标，或右键选择 **Open Zotero**：恢复窗口。
- 右键选择 **Exit Zotero**，或使用 Zotero「文件 → 退出」：正常退出。
- Windows 可能将图标放到任务栏的隐藏图标区域（向上箭头）。可在 Windows 设置中设置始终显示。
- 禁用或卸载插件会恢复已隐藏的窗口。

## 实现与限制

使用 Zotero bootstrap 生命周期和原生窗口可见性接口。托盘由无控制台窗口的 .NET WinForms 小程序实现，源码在 `helper/TrayHelper.cs`。插件运行时不会启动 PowerShell，不下载、不安装外部依赖，不打开网络端口，不访问文献库。辅助程序保存在 Zotero profile 的 `zotero-mini-tray` 目录，通过每次启动独立的临时状态目录交换恢复/退出信号；结束后清理状态目录。

只有托盘已就绪后才拦截关闭；辅助进程异常退出会恢复隐藏窗口。`scripts/build.ps1` 只在开发和打包时调用 Windows 自带的 .NET Framework C# 编译器，用户安装插件后不需要运行脚本。

目前仅支持 Windows。已在本机 Zotero 10.0.6 的独立 profile / 空文献库中通过集成测试：自绘标题栏 × 按钮、`window.close()`、Windows 原生 WM_CLOSE 消息触发隐藏、三轮隐藏恢复、辅助进程崩溃恢复、禁用恢复、退出取消及托盘退出后的清理。测试通过 Win32 `IsWindowVisible` 检查实际窗口可见性。托盘鼠标点击及不同窗口状态仍建议按下方清单手动验收；Zotero 7–9 尚未实测。

插件通过本仓库根目录的 `updates.json` 检查 GitHub 上的新版本。实现依据：[Zotero 插件开发文档](https://www.zotero.org/support/dev/zotero_7_for_developers)。

可运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-integration.ps1` 重复集成测试。测试创建独立的 `.test/run-*/profile` 和空文献库，不使用现有 Zotero profile。测试脚本默认使用 `C:\Program Files\Zotero\zotero.exe`，可通过 `-ZoteroPath` 指定其他位置。

## 验收

在测试 profile 中检查：关闭主窗口后任务栏按钮消失、托盘图标仍在；托盘单击/菜单恢复；连续多次关闭恢复；最小化/最大化后关闭恢复；独立阅读器正常关闭；文件菜单退出；托盘退出；禁用插件时恢复；辅助进程意外结束时恢复；退出被其他插件取消时仍可继续隐藏；Zotero 退出后辅助进程与托盘图标消失。
