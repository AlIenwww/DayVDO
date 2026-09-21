# DayVDO — A 白底石墨，矢量重建预览

以用户选定的 A 白底石墨为造型参考，重新绘制折带 D、回折面和浅蓝斜杠。没有把 AI 图片放进工程，也没有使用位图描摹纹理。

## 可编辑成品

- `DayVDO-Graphite-Clean.icon`：已由 Apple Icon Composer 27 的 `ictool` 成功读取并渲染的三层工程。
- `DayVDO-Graphite-Clean.icon/Assets/`：实际使用的三个 SVG 路径。1024 × 1024 画布，不预烘焙圆角背景、高光或阴影。
- `DayVDO-Graphite-Clean.icon/icon.json`：原生背景、渐变和玻璃材质参数。
- `DayVDO-Graphite-27.png`：1024 px 的 macOS Default 外观原生渲染。
- `DayVDO-Graphite-27-256.png`、`DayVDO-Graphite-27-64.png`：由原生渲染器分别生成的小尺寸预览。
- `layers/`：用于首次构建的平整矢量源图层。

`DayVDO-Graphite.icon` 是建立文件格式时使用的单层工作稿，不是最终候选。

## 材质

使用 Icon Composer 27.0 (129)，显式选择 design generation 27。

- 背景：苹果原生自动渐变，冷白色。
- 石墨主轮廓：两端线性渐变，内侧 specular，高光保持克制。
- 回折面：独立线性渐变，不叠加玻璃特效，避免接缝产生双重描边。
- 浅蓝斜杠：独立浅蓝渐变，15% translucency，保留原生玻璃边缘。
- 图层阴影：neutral，12%。

这些是可重复渲染的设计参数，不含随机噪声或 AI 绘制的反光。

## 复现

运行 `python3 render.py`。需要本机 Xcode 内的 Icon Composer 27，以及允许渲染器访问图标文件的执行环境。

## 验证与范围

已成功导出并目视检查 1024、256 和 64 px 的 Default 外观。此轮是选型预览，未替换应用资源，未制作或验证 Dark / Mono 外观，也未修改构建配置。

参考：

- https://developer.apple.com/icon-composer/
- https://developer.apple.com/videos/play/wwdc2025/361/

苹果推荐先制作简洁的矢量图层，再在 Icon Composer 中应用材质。这里沿用该流程；图标造型为 DayVDO 自有设计重建，不代表苹果官方设计。
