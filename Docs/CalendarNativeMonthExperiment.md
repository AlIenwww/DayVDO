# 原生月历滚动对照原型（2026-10-04）

## 状态

已实现隔离实验路径；未采用为正式滚动实现。已有一次有效 CPU 对照，用户反馈 B 更顺畅；尚无帧率或能耗收益结论。保留此前已有的 0.6.2 筛选、工具栏及其他未提交更改。

`CalendarNativeMonthExperiment` 仅在 DEBUG 编译条件、隔离测试 bundle ID 和 `DayVDONativeMonthPrototype = true` 三项同时满足时启用。普通 Release 使用原月历路径。测试包使用 Release 优化级别并额外定义 DEBUG，以便访问显式隔离数据文件。

## 实现与限制

- NSScrollView 承担位移；NSCollectionView 按周复用 NSHostingView，保留任务卡的现有 SwiftUI 视觉、编辑、拖动和撤销处理。
- 固定周高、确定的文档坐标；仅在尺寸变化时使原生布局失效。每周内部的命中区域以本地坐标保存，滚动时进行原生坐标转换。
- 原型使用完整快照替换来避免版本变化时先显示空数组。30 周窗口补充及修改时的快照构建暂在主线程进行；这是仍需测量的成本，不能先假定它足够快。
- 顶部测量容器延伸到标题下方；实际测量日期及星期栏高度，并在 AppKit 中计入窗口工具栏遮挡区域。原生视口保持完整大小，通过文档坐标预留标题区，更新高度时使用旧高度计算保留位置。日期及星期栏使用原生视口中的一个 `NSVisualEffectView`（`.titlebar`、`.withinWindow`）背景，SwiftUI 控件本身透明，避免跨容器背景遮住采样内容；原生材质仅覆盖日期及星期栏，上方窗口工具栏继续使用自己的材质，避免重复模糊。系统材质继续遵循窗口激活及辅助功能设置。
- 吸附直接逐帧更新 NSClipView 位置，使用 0.24 秒 ease-out 曲线。只在吸附期间运行定时器，按屏幕刷新率调度；滚轮、导航、窗口缩放及视图销毁均取消旧动画，取消后不执行旧重定位回调。启用系统“减少动态效果”时立即定位。
- 原型在滚动结束后做周／月吸附；停止时的手感、惯性反向、远距离重定位、辅助功能与八语言尚未完成完整验收。不能仅凭当前编译和拖动检查把它直接发布。

## 已做检查

- 实际打开隔离 B 包，进入月视图、显示 1,000 条压力数据、上下滚动。
- 原生拖动把“滚动压力 0768”起止日期各后移一天；⌘Z 后测试文件与 A 语义完全相同。
- 三项新增测试覆盖可见周边界、尺寸变化后的几何关系和六周视口的文档末端限制。
- 最终完整 Swift 测试：168 项通过，日志为 `/tmp/dayvdo-native-month-20261004/tests-final.log`。
- 正式 Release 和优化级别的隔离包均已构建；普通 Release 不启用原型。
- 本轮完整 Swift 测试共 171 项通过，覆盖实际 clip view 中间位置、取消旧吸附后的新滚动位置保留、标题背景覆盖及高度更新；日志为 `/tmp/dayvdo-native-month-20261004/tests-header-snap.log`。
- 本轮正式 Release 及优化级别隔离构建日志分别为 `release-header-snap.log`、`candidate-within-window.log`。新包为 `/tmp/dayvdo-native-month-20261004/DayVDOScrollBGlass.app`，使用独立的合成数据副本。

## 采样记录

所有文件位于 `/tmp/dayvdo-native-month-20261004/`，仅访问合成测试数据。

- `baseline-source/`：本轮开始时的源码副本。
- `DayVDOScrollA.app`：本轮优化前基线。
- `DayVDOScrollB.app`：原生原型。
- `A-cpu-1.trace`：自动滚动的采样冒烟检查。十二次事件约 2.14 秒发完，最终月份发生偏移；导出得到 2,200 个样本。证明采样可工作，不适合与人工持续滚动比较。
- `manual/DayVDOScrollA-20261004-120200-832480.trace`：约 30 秒，11 个 CPU 样本。
- `manual/DayVDOScrollB-20261004-120544-728734.trace`：约 30 秒，0 个 CPU 样本。

人工两次记录缺少滚动期间的有效样本；原因未确认。不能把样本少解释为性能或能耗改善，也不能给出改善百分比。

后续有效的 30 秒人工对照为 `manual/DayVDOScrollA-20261004-131839-709960.trace` 与 `manual/DayVDOScrollB-20261004-132021-848466.trace`。导出结果及计算保存在 `manual/comparison.json`：A/B 总 CPU 样本权重分别为 16,007/10,636 ms，主线程分别为 15,098/10,350 ms。用户反馈 B 更顺畅，但指出吸附跳转及标题白底；本轮修复这两项，尚未重新测量修复后的性能。

使用公开系统材质，不自定义模糊半径或透明度。

## 用户控制开始时间的录制方式

1. 打开 `DayVDOScrollA.app`，确认 macOS 顶部菜单显示 **DayVDOScrollA**。进入“日历 → 月”，清除筛选，点击“今天”，上下滚动两次预热后再次点“今天”。
2. 双击同目录的 `Record-A.command`。在终端看到准备说明后按回车，五秒内切回 **A 应用**。
3. 持续 30 秒上下滚动，约每秒换一次方向，每次移动一至两周，让任务密集区域经过标题下方；不要切页、编辑或调整窗口大小。30 秒后停止，回终端确认录制成功。
4. 对 B 应用重复相同步骤，运行 `Record-B.command`。两组使用同一输入设备、窗口大小、电源状态和相近滚动范围。
5. 回复“两组录制完成”并描述 B 相对 A 的顺滑程度、停止时跳动及闪烁。文件留在本机，由 Codex 分析，无需上传。

若不能双击 command，可在终端执行以下命令（A 完成后把应用路径中的 A 改成 B）：

```sh
python3 /Users/wuyuchen/PycharmProjects/DayVDO/Tools/record_calendar_scroll.py \
  /tmp/dayvdo-native-month-20261004/DayVDOScrollA.app \
  --output /tmp/dayvdo-native-month-20261004/manual
```

录制脚本只附加到已运行的指定隔离应用，不会打开正式应用、读取正式数据或覆盖旧 trace。脚本保存应用和测试数据哈希、时间、PID 及 xctrace 退出状态。CPU 样本仍需结合真实滚动和帧时间验收。
