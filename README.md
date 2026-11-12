# SideReel

把指定显示器变成相框的 macOS 菜单栏小工具。在外接屏上全屏轮播你指定的图片文件夹，内置屏保持可用（随时 Touch ID），点一下播放屏幕即可退出。

<img src="docs/screenshot.png" width="320" alt="SideReel 菜单栏面板">

## 特性

- **指定显示器**播放，默认第一个外接显示器
- **随机不重复**（一轮播完才重复）或**按顺序**轮播
- 切换间隔 1–3600 秒，带淡入过渡
- **闲置自动开始**（1/2/5/10/15/30/60 分钟）或手动开始
- **点击该屏幕任意处或按 Esc 退出**
- 用无边框窗口实现，**不触发系统锁屏**，播放时阻止显示器休眠
- 支持 JPEG / PNG / HEIC / TIFF / GIF 等常见格式

## 系统要求

- macOS 26 或更高
- Apple Silicon（arm64）

## 安装

1. 从 [Releases](https://github.com/souvenirding/SideReel/releases) 下载 `SideReel-*-macOS-arm64.zip` 并解压。
2. 将 `SideReel.app` 拖入「应用程序」。
3. 应用为 ad-hoc 签名（未公证），首次启动请**右键 → 打开**以绕过 Gatekeeper。

## 使用

点击菜单栏的相框图标 → 选择图片文件夹与显示器 → 设置间隔和顺序 → 「开始播放」，或开启「闲置后自动开始」。

- 退出播放：点击播放屏幕任意位置，或按 `Esc`。
- 退出应用：面板底部「退出 SideReel」，或按 `⌘Q`。

> 应用本身不会锁屏；macOS 自身的屏幕保护 / 锁定设置仍独立生效。

## 从源码构建

需要 Xcode（可用 `DEVELOPER_DIR` 指定）：

```sh
./Scripts/build-app.sh   # 产物在 build/SideReel.app
```

运行引擎自测：

```sh
swift build -c release
./.build/release/SlideshowSelfTest <图片文件夹> [秒数] [显示器名]
```

## 许可证

[MIT](LICENSE)