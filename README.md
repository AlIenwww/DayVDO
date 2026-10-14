# DayVDO

一款将日历、每日计划和待办清单联动的原生 macOS 应用，注重操作体验和简洁界面。目前仍在开发中。

## 构建环境

- 完整的 Xcode 27，包含 macOS 27 SDK 和 Swift 工具链。当前工程的链接配置使用 SDK 27。
- 项目使用 Swift Package Manager，目前没有第三方 Swift 依赖。

构建所需的源码、资源和 `Package.swift` 已包含在仓库中。编译产物、IDE 个人设置和缓存由每台电脑上的工具本地生成。

工程声明最低运行版本为 macOS 15；目前实机开发和验证环境为 macOS 27.0.1，其他系统版本尚未完成实机验证。

## 获取与运行

```sh
git clone https://github.com/AlIenwww/DayVDO.git
cd DayVDO
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift build
xcrun swift run DayVDO
```

如果 Xcode 安装在其他位置，请调整 `DEVELOPER_DIR`。也可以用 Xcode 打开仓库根目录下的 `Package.swift`。

## 测试

手动运行测试：

```sh
xcrun swift test
```

测试包含原生窗口交互检查，执行时可能出现测试窗口。

## 用户数据

应用的数据保存在 `~/Library/Application Support/DayVDO/`。
