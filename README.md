# DayVDO
一款深度联动“日历””每日计划““待办清单” 主打 操作体验、使用逻辑、原生简洁 的 to-do list应用

#注意事项：
1. 软件开发于macOS 27.0，其他版本还没有实机测试过。
2. 软件还在开发中，很多功能还没有实现！

#用户数据
用户数据保存在用户的Application Support/DayVDO目录中。

#一些废话
施工中。。




## 更新版本号

在 Finder 中双击与本项目同级的 `DayVDO_` 文件夹内的 `更新版本号.command`，输入版本号（例如 `0.5.3`）并回车，即可同步更新设置页和打包脚本中的版本号。直接回车可取消，完成后再按回车退出。

脚本只修改工程中的版本号，不自动构建、提交或推送。已有 App 需要重新打包才会显示新版本；打包时的构建编号仍自动使用时间戳。

## macOS 27 独立兼容测试包

当前工程使用 Xcode 27 / macOS 27 SDK，并用 `xcode-select` 选中对应工具链。默认 Xcode Run 与 SwiftPM 构建已在 `Package.swift` 中统一链接设置；将来升级 SDK 时需同步更新该处 SDK 版本，最低部署版本仍为 15.0。

```sh
python3 Scripts/build_app.py --configuration debug --test --output-dir dist/check-debug
python3 Scripts/build_app.py --configuration release --output-dir dist/check-release
```

构建入口明确指定实际 SDK 和现有最低部署版本，检查 Mach-O、八语言资源及签名。输出目录内若已有同名应用会拒绝覆盖，请为下一次打包选择新的目录。包采用独立 bundle ID 和数据目录，不覆盖安装版或读取正式数据；Debug 可用 `--test-data /absolute/path/test-data.json` 指定独立测试夹具。

当前最低部署版本仍为 macOS 15；macOS 26 实机兼容性尚待验证。测试包采用 ad-hoc 签名，未公证。完整结果和验收边界见 [macOS 27 兼容验收记录](Docs/macOS27CompatibilityVerification.md)。
