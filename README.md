# BgClicker — 跨平台后台窗口连点器（Windows / macOS）

轻量级原生桌面连点工具，零第三方依赖：
- **Windows 版**（`BgClicker.cs`）：基于 Win32 `PostMessageW` 向目标子窗口投递点击消息，使用系统自带 `.NET Framework 4.x` 编译，单文件 `.exe` 仅约 20 KB。
- **macOS 版**（`macos/BgClicker.swift`）：基于 AppKit + CoreGraphics `CGEventPostToPid` 定向进程投递（不抢鼠标）+ Carbon 全局热键，使用系统 `swiftc` 编译为原生 `BgClicker.app`。

## 功能特点

- **后台点击不抢鼠标**：自动定位目标窗口及相对坐标，窗口拖动时自动跟随。
- **全局热键**：
  - `F8`：锁定当前鼠标位置的目标窗口与相对坐标（也可点界面「锁定位置」按钮 2 秒倒计时锁定）
  - `F9`：开始 / 暂停连点
  - `F10`：停止连点
- **纯红 1px 细线准星标记**：透明穿透、不抢焦点，方便确认点击位置。
- **灵活参数**：默认间隔 `50 ms`、随机抖动（`±ms`）、按住时长（`10 ms`）、点击次数（`0` 为无限）、左键/右键切换、窗口置顶。

## 编译与运行

### Windows

无需安装 Visual Studio 或 .NET SDK，在 PowerShell 中直接运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

双击生成的 `BgClicker.exe` 即可使用。

### macOS

需已安装 Xcode Command Line Tools（`xcode-select --install`），在终端中运行：

```bash
chmod +x macos/build.sh
./macos/build.sh
open macos/BgClicker.app
```

首次运行请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 `BgClicker`（界面顶部提供一键跳转按钮）。

> 你也可以直接在 GitHub 仓库的 **Actions** 页面下载每次自动构建好的 `BgClicker-windows` 和 `BgClicker-macos` 产物。

## 注意事项

- **Windows**：如果目标程序以管理员身份运行，请右键 `BgClicker.exe` 选择「以管理员身份运行」（UIPI 限制）；部分 UWP 应用（如 Win10/11 计算器）或 DirectInput 游戏不响应 `PostMessage`。
- **macOS**：采用 `CGEventPostToPid` 定向进程投递（不抢鼠标）；部分应用（如微信小程序游戏）在失焦后会忽略后台点击，需保持目标窗口处于聚焦状态。

## License

MIT
