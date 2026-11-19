# BgClicker — Windows 后台窗口连点器

轻量级原生 Windows 桌面连点工具，基于 Win32 `PostMessage` 向目标窗口投递点击消息，**不抢占物理鼠标、不切前台焦点**，零第三方依赖（使用 Windows 自带 `.NET Framework 4.x` 编译，生成单文件 `.exe` 仅约 20 KB）。

## 功能特点

- **后台点击不抢鼠标**：通过 `WindowFromPoint` 自动定位鼠标下最里层的子窗口句柄（支持嵌套渲染子窗口），用 `PostMessageW` 发送点击事件，不影响正常使用电脑。
- **全局热键（`RegisterHotKey`）**：
  - `F8`：锁定当前鼠标位置的目标窗口与相对坐标（也可点界面「锁定位置」按钮 2 秒倒计时锁定）
  - `F9`：开始 / 暂停连点
  - `F10`：停止连点
- **纯红细线准星标记**：基于 `UpdateLayeredWindow` 逐像素透明渲染，鼠标穿透、不抢焦点，目标窗口拖动时自动跟随。
- **灵活参数**：支持自定义点击间隔（默认 `50 ms`）、随机抖动（`±ms`）、按住时长、点击次数（`0` 为无限）、左键/右键切换、窗口置顶。

## 编译与运行

无需安装 Visual Studio 或 .NET SDK，在 Windows PowerShell 中直接运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

编译完成后双击生成的 `BgClicker.exe` 即可使用。

## 注意事项

- **权限隔离（UIPI）**：如果目标程序以管理员身份运行，请右键 `BgClicker.exe` 选择「以管理员身份运行」。
- **兼容性说明**：传统 Win32 窗口、浏览器/Chromium/Electron 渲染子窗口通常支持 `PostMessage` 后台点击；部分 UWP 应用（如 Win10/11 自带计算器）或使用 DirectInput / Raw Input 的游戏可能会忽略 `PostMessage` 消息。
- 窗口被其他窗口遮挡时一般仍可正常后台点击，但请不要将目标窗口最小化。

## License

MIT
