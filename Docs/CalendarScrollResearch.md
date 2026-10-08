# 月视图滚动：Apple 官方资料调研

日期：2026-10-04。范围：月视图任务密集区域上下滚动，以及编辑后任务闪烁。本文是调研和候选方案，尚未实现新滚动容器，也没有新的帧率或能耗实测结果。

## 证据边界

本次没有找到 Apple 公开说明 macOS Calendar 月视图内部架构的资料。不能把 AppKit 的机制、快捷指令的案例，或第三方日历实现说成 Calendar 本身的优化方案。

用户反馈之前的优化体感不明显；不以那一轮改法作为新方案依据。以下代码观察来自当前工作区。

## 官方资料与适用范围

1. [Use SwiftUI with AppKit — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10075/)。Apple 的快捷指令使用 NSCollectionView 承载 SwiftUI 卡片；复用单元时保留 NSHostingView，更新其内容，避免反复移除、创建子视图。这个案例支持尝试混合架构，并不保证迁移后的 DayVDO 更快。
2. [AppKit Release Notes：Responsive Scrolling](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/)。历史文档解释预绘制视口外区域，让滚动复用已经绘制的内容，并描述系统在内存、能耗和预绘制范围之间的权衡。具体机制不能直接当作当前 SwiftUI 内部实现的说明；现行 API 仍提供 [isCompatibleWithResponsiveScrolling](https://developer.apple.com/documentation/appkit/nsview/iscompatiblewithresponsivescrolling) 和 [prepareContent(in:)](https://developer.apple.com/documentation/appkit/nsview/preparecontent(in:))。不要未经验证就强制覆盖兼容性属性。
3. [NSCollectionViewLayout](https://developer.apple.com/documentation/appkit/nscollectionviewlayout?changes=_1) 与 [局部布局失效](https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext)。固定周行可以使用确定的布局坐标；内容变化时标记受影响的项目，避免全量失效。跨周任务移动需要同时处理原周和目标周。
4. [Optimize SwiftUI performance with Instruments — WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/) 与 [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)。使用 SwiftUI 更新轨道、Time Profiler 和 Animation Hitches 区分更新、布局、提交及渲染阶段。CPU 百分比或单张截图不能代替滚动掉帧数据。
5. [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)。多个自定义玻璃效果可通过 GlassEffectContainer 合并；应限制同时显示的效果数量。这不意味着给只有一个效果的控件再包一层容器就能明显提速。
6. [Canvas](https://developer.apple.com/documentation/swiftui/canvas)。Apple 明确提醒 Canvas 不为每个绘制元素提供交互和辅助功能；日历以文字、选择和拖动为核心，不优先采用整页 Canvas 重写。

## 当前代码观察

- `CalendarView.swift` 的 CalendarTimeline 已经使用 LazyVStack、固定周行高度、209 个虚拟周和分段内容窗口；`CalendarWindowSnapshot.swift` 已预计算周任务布局。单纯“改成懒加载”不是新的解决方案。
- `CalendarDateGrid.swift` 每周读取相对视口的几何位置，聚合任务命中区域，组合多层任务卡和日期控件。它是需要用 Instruments 验证的更新路径，尚不能凭阅读代码判定为主要掉帧原因。
- `PageTopBar.swift` 使用系统 safeAreaBar；低版本使用 `.bar`。`CalendarDisplayModePicker.swift` 给整个切换控件应用一次玻璃效果。没有发现每张月历任务卡都独立套玻璃效果的情况。
- `CalendarTimeline.currentSnapshot` 在数据版本不一致时返回 nil，行数据随后取 `[]`；新的异步快照准备完成后再次出现任务。这是编辑后闪烁的可疑路径，需要与滚动性能分别验收。

## 新候选：可复用的原生周行

先在隔离原型中尝试 NSScrollView + NSCollectionView，以一周为复用单元，保留既有任务卡视觉与 SwiftUI 编辑器。每周内部允许跨列任务，避免把跨日条拆成七个独立单元。

- 按窗口大小直接确定周高，使用确定坐标。宽高变化时重排；普通位移不改变周内布局。
- 复用周行中的 hosting view，只在周内容、尺寸或交互状态改变时更新。
- 让原生滚动容器负责位移和预绘制；不把每个滚动事件映射成整个 SwiftUI 月历的状态更新。
- 更新时保留连续显示的数据，按稳定 ID 更新受影响周。筛选改变也不能先发布空数组再填回内容；隐藏项仍需及时消失。
- 保留半透明标题和星期行，以及日期选择、更多任务、拖动调整日期、草稿、撤销、键盘和辅助功能。

以上是待测架构假设。SwiftUI 的现有滚动也可能已获得系统底层优化，换成 AppKit 本身不构成性能收益证据。原生原型还需要验证顶栏下透视、吸附、惯性反向、返回今天及窗口缩放，不能以普通列表 demo 的表现替代。

## 对照方法与采用条件

1. 保存本轮开始时的源码和隔离测试包；候选与基线使用同一编译优化等级、数据、筛选、月份、窗口及显示刷新率。保留两份可供用户直接切换的应用。
2. 先在同一实现中对照半透明与临时不透明标题，以判断玻璃渲染的贡献；这个开关只用于诊断，不作为产品外观更改。
3. 分别测量普通与密集任务月份的持续滚动。冷加载和预热后滚动分开记录，两组交替重复采样。采样期间避免高频辅助功能树读取，防止工具自身工作混入应用 CPU。
4. 记录每单位时间的 hitch 次数、总超时、帧时间分布、主线程更新及渲染耗时；另测滚动与静止时能耗。不要把 CPU 降低直接写成省电结论。
5. 编辑、完成、拖动、筛选及撤销均检查是否整片闪烁；同样检查滚动位置和选中项。运行测试、Release 构建和手势回归。
6. 只有重复测量显示收益，且用户能在同数据两包之间观察到改善，才把新容器替换到正式路径。若主要成本在 GPU 或文本渲染，依据采样调整范围，不继续盲目扩展缓存或扩大重写。

本次仅新增此调研记录，未修改产品实现、版本或持久化格式。
