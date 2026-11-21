# DayVDO Changelog / 更新日志

[English](#english) · [简体中文](#简体中文)

## English

### v0.9.2 — Tutorials and calendar fixes

**Added**

- Added a bilingual changelog covering this and earlier releases, linked from the README.
- Added five optional lessons covering dates and estimated duration, time blocks, rescheduling in Calendar, projects and tags, and search and filters. Each lesson can be practiced with separate sample data.
- Added a Tutorials browser under **Settings → Help**. Select a topic to watch a short in-app recording or start its practice. Click a video to pause, resume, or replay it.
- Added **Schedule Time…** to the Today to-do menu so you can enter a start time directly.

**Improved**

- Rebuilt the first-run guide around a single to-do. Create and schedule it in Today, find its time block in Calendar, then mark it complete in All To-Dos.
- The introduction now explains the timeline before asking you to schedule anything. The Calendar step starts in month view and shows how to switch to week view.
- Moved practice prompts alongside the controls they refer to. The final step can guide you through Settings and Help to reopen the tutorials.
- Updated the welcome screen with the DayVDO icon and always-visible language and appearance controls. Language changes now update the open guide immediately.
- Redesigned the time-block popover to make the time and status easier to read and to give **Edit time block** a dedicated button.

**Fixed**

- Fixed some Settings controls retaining the previous language after an in-app language switch.
- Fixed a single click on the empty week-view timeline opening the scheduling popover and showing a blue focus outline.
- Fixed quitting DayVDO while an in-app popover is open.
- Fixed the completion circle in Calendar so clicking it marks a to-do complete or undoes completion.
- Fixed guide highlights that failed to enclose toolbar buttons and prompts that could briefly appear in the wrong place as a step changed.
- Fixed a flash when opening the new to-do editor for the first time during practice and placed keyboard focus in the title field.

### v0.9.1 — Duration settings and interface improvements

**Added**

- Added hours, minutes, and mixed display modes under **Settings → To-Dos & Scheduling → Estimated Duration Unit**. In mixed mode, entering 90 minutes in the minutes field now converts to 1 hour and 30 minutes.
- Added a separately configurable Calendar dragging animation for moving and resizing items, creating items by dragging, and returning items to their original position on Esc.
- Added a separately configurable Calendar animation for transitions between Not Started, In Progress, and Completed.
- Added a separately configurable All To-Dos list animation for items appearing or disappearing when to-dos, subtasks, or projects are added, deleted, or filtered.

**Improved**

- Refined the getting-started guide with shorter introductions and prompts that point to the app controls used during practice.
- Updated Settings with previews for animation effects and illustrations in the Glossary.
- Improved the filter popover so its scrollable options stay clear of the header.
- Added color dots to the project and tag pickers in the to-do editor. Tagged projects show their assigned tag color.
- Restored the list icon on the button that opens Calendar date details.
- Updated the DayVDO app icon.
- Rewrote the bilingual README and added screenshots of Today and Calendar.

**Fixed**

- Fixed the guide’s **System Default** language option so it follows the macOS language.
- Fixed a single click on an empty Today timeline opening the time-block editor.
- Fixed areas of the interface, including parts of the filter panel, that kept the old accent color.
- Fixed projects becoming impossible to collapse after being selected in a filter.
- Fixed an empty project disappearing when it was selected in a filter.

### v0.9.0 — Settings and getting started

**Added**

- Added an interactive guide for creating, scheduling, and completing a to-do. Practice uses separate sample data and can be resumed from **Settings → Help**.
- Added settings for the startup page, default urgency, and default time-block duration.
- Added customizable keyboard shortcuts and individual switches for animation effects.
- Added a glossary explaining terms used in DayVDO.

**Improved**

- Reorganized Settings into categories within the main window.
- Standardized the names of features and controls across the app.
- Removed the repeated heading and introductory text from the new to-do form.

### v0.8.2 — Subtask dragging and filter controls

**Improved**

- Made subtasks move out of the way more reliably during reordering, with fewer repeated shifts between adjacent rows and smoother feedback in larger projects.
- Moved project and tag filter choices into searchable multi-select panels. The search field stays in place while the results scroll.
- Removed the dash icon from the **None** urgency option in the to-do editor.
- Refined the appearance of the week/month calendar switcher.

### v0.8.1 — Timeline and drag refinements

**Improved**

- Clicking outside a selected time block now deselects it.
- Refined drag feedback when reordering subtasks in All To-Dos.
- Reduced unnecessary layout updates while interacting with time blocks in Today and Calendar.

**Fixed**

- Corrected time blocks that appeared lower on the Today and week timelines than their scheduled times.

### v0.8.0 — Planning and calendar improvements

**Added**

- Added date filters to All To-Dos and Calendar.
- Added the option to create a project directly from the to-do editor.

**Improved**

- Moved Calendar to the second position in the sidebar, followed by All To-Dos.
- Reorganized the to-do editor and added a clock icon beside Estimated Duration.
- Removed the dash icon from the **None** importance option in the to-do editor.
- Improved the responsiveness of Calendar’s week view when opening it or scrolling.
- Prepared the Today timeline before displaying the main window so existing time blocks appear with the first view.

**Fixed**

- Fixed scrolling in the Today to-do list spilling into the timeline upon reaching either end of the list.
- Fixed startup flicker caused by the selected appearance being applied after the window became visible.
- Fixed dragging a to-do to another week in Calendar’s week view.
- Fixed creating a standalone time block that ends at midnight. You can now drag down to 24:00 or drag up from it.
- Fixed dropping a subtask at the bottom of its project.

### v0.7.1 — Time-block editing and calendar navigation

**Improved**

- Refined the time-block editor layout. Press Return to save changes and close the editor.
- Improved the layout of time blocks that appear side by side on the timeline.
- Refined the appearance of the Scheduled and Unscheduled groups in Today.
- Aligned Today’s date controls with Calendar by moving **Today** and the previous and next buttons to the right.
- At startup, Today opens the timeline at the earliest scheduled block, or at the current time if nothing is scheduled.
- Drag a time block back to the to-do list to remove that block and keep the to-do.
- Enabled horizontal navigation between weeks within the week view.
- Removed the right-click toolbar options for displaying buttons as text only or as icons with text.

**Fixed**

- Reduced delays when switching Calendar between week and month views.
- Fixed visible flicker when Calendar refreshes.
- Fixed the appearance when switching from Dark back to the system setting.
- Fixed the week view divider so it follows the pointer during a drag.

### v0.7.0 — Timeline controls and rescheduling

**Improved**

- Single-click a time block to select it.
- Double-click the title of a linked time block to edit its to-do, or double-click elsewhere on the block to edit its schedule. The right-click menu also offers access to the linked to-do.
- Press Esc to close the time-block editor, including after drawing a standalone block.
- When rescheduling a to-do leaves linked blocks outside its new date range, choose whether to keep those blocks as standalone arrangements, delete them, or cancel the date change. Today’s list reflects the new date range after the change is saved.
- Improved snapping when drawing a standalone block near an existing block.
- For a to-do whose estimated time is fully scheduled, the drag prompt now says **Continue scheduling** without specifying a fixed 30-minute addition.
- Updated the Calendar week/month switcher to use a native segmented control.

**Fixed**

- Adjusted the current-time line to keep the time labels legible and preserve the color of blocks beneath it.

### v0.6.2 — Calendar filters and scrolling

**Added**

- Added Calendar filters that apply to the calendar grid, date details, and linked time blocks.

**Improved**

- Centered the week/month switcher in the toolbar, with a Liquid Glass appearance on supported macOS versions.
- Refined the translucent toolbar so content remains visible through it as it scrolls underneath.
- Improved Calendar scrolling performance.

### v0.6.1 — Sidebar and project-list refinements

**Improved**

- Reduced delays when switching between pages in the sidebar.

**Fixed**

- Fixed project folder icons shifting in All To-Dos.

### v0.6.0 — Week view and calendar editing

**Added**

- Added a week view with multi-day to-dos above the daily timelines. Drag the divider to give either section more room.
- Added drag-to-create in Calendar. Drag across empty dates to set the range for a new to-do.
- Added direct date editing in Calendar. Drag a to-do bar to move it or drag either end to adjust the date range.
- Added a right-click menu for calendar to-dos and Delete-key support for the selected bar. Selected items can also be edited with Return or copied and pasted onto another date.

**Improved**

- Added compatibility updates for macOS 27.

### v0.5.2 — All To-Dos filters and overdue items

**Added**

- Added filters to All To-Dos, including project, tag, and status.
- Made overdue to-dos visible in All To-Dos and added a dedicated Overdue filter.

**Improved**

- Reduced delays when switching between pages.

### v0.5.1 — In-progress status and planning fixes

**Added**

- Added an **In Progress** status for to-dos.
- Added separate start and end dates so a to-do can span multiple days.

**Improved**

- Highlighted the currently active time block on the Today timeline.
- Improved how tag colors appear in the to-do editor.
- Made the clickable area for calendar date selection align with its visible target.
- Enlarged the clickable area for opening or closing a project.

**Fixed**

- Fixed Calendar disappearing when the window was maximized.
- Fixed erratic upward scrolling in All To-Dos.
- Fixed the Scheduled and Unscheduled groups in Today failing to update immediately after scheduling changes.
- Fixed time blocks that could not be edited from the timeline.

### v0.5.0 — Daily timeline

**Added**

- Added a daily timeline to Today. Drag a to-do onto it to schedule time, or draw a standalone block in an empty slot.
- Added estimated duration to the to-do editor.

**Improved**

- Grouped Today’s list into Unscheduled, Scheduled, and Completed.

### v0.4.1 — Layout and scrolling fixes

**Improved**

- Adjusted control widths to accommodate longer translations.
- New projects start collapsed in All To-Dos. The app remembers each project’s expanded or collapsed state.

**Fixed**

- Fixed calendar scroll positioning when the window is resized.

### v0.4.0 — Data recovery and calendar navigation

**Added**

- Added automatic local backups and the option to recover from one if the main data file is damaged.

**Improved**

- Improved the feedback when a change could not be saved and made it possible to retry.
- Expanded undo and redo support for edits to to-dos, projects, and tags.
- Improved the way Calendar snaps to weeks and months during scrolling.

**Fixed**

- Kept saved to-do dates stable when switching time zones.

### v0.3.0 — Projects and tags

**Added**

- Added projects for grouping related to-dos, with expandable child lists and progress indicators in All To-Dos.
- Added color-coded tags for organizing to-dos across projects.

### v0.2.0 — Language and appearance settings

**Added**

- Added interface language selection.
- Added System, Light, and Dark appearance options.
- Added an urgency field alongside importance.

**Improved**

- Updated Calendar and the date picker.

### v0.1.0 — Initial version

**Added**

- Introduced DayVDO for macOS with Today, All To-Dos, and a monthly calendar.
- Added locally stored to-dos with notes, due dates, priorities, and completion status.

## 简体中文

### v0.9.2 — 新手教程与日历修复

**新增**

- 新增中英双语更新日志，收录当前及以往版本的更新内容，可从 README 打开。
- 新增五个进阶练习，分别介绍日期与预计时长、时间块、日历改期、项目与标签、搜索与筛选。每个练习使用独立的示例数据。
- 「设置 → 帮助」新增「使用教程」窗口。选择专题即可观看应用内实录或开始练习，点击视频画面可暂停、继续或重播。
- 「今日安排」的待办菜单新增「安排时间…」，可直接输入开始时间。

**改进**

- 重做首次引导，用同一条待办串起三个页面。在「今日安排」新建并安排时间，到「日历」找到时间块，再到「总待办」标记完成。
- 引导先解释时间线的用途，再请用户安排时间。日历环节先展示月视图，再说明如何切到周视图。
- 将操作提示放到对应的控件旁。结尾可以逐步引导用户通过「设置」和「帮助」重新打开教程。
- 欢迎页使用 DayVDO 图标，直接展示语言和外观选项。切换语言后，当前引导界面即时更新。
- 重新排版时间块弹窗，让时间和状态更容易查看，并为「编辑安排」提供独立按钮。

**修复**

- 修复切换应用语言后，设置中的部分控件未即时更新的问题。
- 修复单击日历周视图的时间线空白处时，意外弹出安排窗口并出现蓝色焦点边框的问题。
- 修复应用内弹窗打开时无法退出 DayVDO 的问题。
- 修复日历中的待办完成圆圈无法点击的问题。现在可点击圆圈标记完成或取消完成。
- 修复引导高亮框无法完整包住工具栏按钮，以及切换步骤时提示框偶尔出现在错误位置的问题。
- 修复练习中首次打开新建待办窗口时的闪烁，并让光标直接落在标题输入框。

### v0.9.1 — 时长设置与界面改进

**新增**

- 「设置 → 待办与安排 → 预计时长单位」新增小时、分钟和混合三种模式。混合模式下，在分钟栏输入 90 会自动换算为 1 小时 30 分钟。
- 日历新增拖拽动画，涵盖移动、调整长短、拖动空白处创建以及按 Esc 回位，可在设置中单独关闭。
- 日历新增待办状态切换动画，涵盖未开始、进行中和已完成，可在设置中单独关闭。
- 「总待办」新增列表过渡动画。增删待办、子任务和项目，或筛选使条目隐藏、重新出现时，会播放过渡效果。此项可单独关闭。

**改进**

- 简化新手指引的介绍，让练习提示指向应用中的实际控件。
- 为动画设置加入效果预览，为词典添加示意图。
- 调整筛选弹窗的滚动区域，避免筛选选项与顶部标题重叠。
- 待办编辑器的项目与标签列表新增颜色圆点。带标签的项目显示所关联的标签颜色。
- 将日历日期详情按钮恢复为清单图标。
- 更新 DayVDO 应用图标。
- 重写中英双语 README，加入「今日安排」和「日历」截图。

**修复**

- 修复引导中「系统默认」语言选项未正确跟随 macOS 系统语言的问题。
- 修复单击「今日安排」的时间线空白处时意外打开安排弹窗的问题。
- 修复筛选面板等部分界面未随主题色更新的问题。
- 修复筛选选中某个项目后，该项目无法收起的问题。
- 修复筛选选中空项目后，该项目消失的问题。

### v0.9.0 — 设置与新手指引

**新增**

- 新增互动新手指引，可练习新建待办、安排时间和标记完成。练习使用独立的示例数据，可从「设置 → 帮助」继续。
- 新增启动页面、默认紧急度和默认安排时长设置。
- 新增自定义快捷键和分项动画开关。
- 新增词典，解释 DayVDO 使用的功能术语。

**改进**

- 将设置移入主窗口，并按类别重新组织。
- 统一应用各页面的功能名称与控件文案。
- 移除新建待办表单顶部重复的标题和说明。

### v0.8.2 — 子任务拖动与筛选

**改进**

- 改善项目内子任务拖动时的让位动画，减少相邻条目来回跳动，让大项目中的排序更顺畅。
- 项目和标签筛选改用可搜索的多选面板。滚动结果时，搜索框保持在原位。
- 移除待办编辑器中紧急度「无」选项前的横杠图标。
- 调整日历顶部周／月切换控件的样式。

### v0.8.1 — 时间线与拖动改进

**改进**

- 选中时间块后，点击其他位置即可取消选中。
- 改善「总待办」中拖动子任务排序时的反馈和动画。
- 减少「今日安排」和日历时间线在操作时间块时不必要的界面刷新。

**修复**

- 修复「今日安排」和周时间线上的时间块显示位置低于实际安排时间的问题。

### v0.8.0 — 今日安排与日历改进

**新增**

- 「总待办」和「日历」新增日期筛选。
- 新建或编辑待办时，可以直接创建项目。

**改进**

- 将「日历」移至侧栏第二项，「总待办」移至第三项。
- 重新排版待办编辑器，并为「预计时长」添加时钟图标。
- 移除待办编辑器中重要度「无」选项前的横杠图标。
- 改善日历周视图打开和滚动时的响应速度。
- 启动时先准备今日时间线，现有时间块随主窗口一同显示。

**修复**

- 修复「今日安排」中的待办列表滚动到顶或底时带动时间线的问题。
- 修复主窗口出现后才应用外观设置造成的启动闪烁。
- 修复日历周视图中的待办无法拖到其他周的问题。
- 修复普通安排无法拖动创建到午夜的问题。现在可向下拖到 24:00，也可从 24:00 向上拖出一段安排。
- 修复子任务无法拖到项目末尾的问题。

### v0.7.1 — 安排编辑与日历导航

**改进**

- 调整安排编辑弹窗的布局。编辑后按回车即可保存并关闭。
- 调整时间线中并排时间块的样式。
- 改善「今日安排」中「已安排」和「未安排」分组的外观。
- 将「今天」和前后日期按钮移到右侧，与日历的日期导航布局一致。
- 启动时，今日时间线定位到最早的安排。当天没有安排时，定位到当前时间。
- 将时间块拖回待办列表，可移除该时间块并保留待办。
- 日历周视图内可横向滚动切换周次。
- 移除顶部工具栏右键菜单中「仅文字」和「图标加文字」的显示选项。

**修复**

- 减少日历周／月视图切换时的卡顿。
- 修复日历刷新时的闪烁。
- 修复深色外观切回跟随系统时的显示问题。
- 修复日历周视图分隔线拖动时无法实时跟随光标的问题。

### v0.7.0 — 时间线交互与待办改期

**改进**

- 单击时间块即可选中。
- 双击关联时间块的标题可编辑待办，双击块内其他位置可编辑安排。也可通过右键菜单编辑关联待办。
- 在拖动空白时段等操作后打开的安排编辑弹窗中，按 Esc 可关闭。
- 待办改期后，如果部分时间块落在新日期范围之外，可以将这些时间块保留为普通安排、删除安排，或取消改期。保存后，「今日安排」的待办列表按新的日期范围显示。
- 改善在已有时间块附近拖动创建普通安排时的吸附。
- 待办排满预计时长后再次拖入时间线，提示选项显示「继续安排」。
- 日历周／月切换改用系统原生分段控件。

**修复**

- 调整当前时间线的绘制，避免红线遮挡左侧时间刻度或影响下方时间块的颜色。

### v0.6.2 — 日历筛选与滚动

**新增**

- 日历新增筛选，可同时作用于日历网格、日期详情和关联时间块。

**改进**

- 将周／月切换控件移到工具栏中央，并在支持的 macOS 版本上使用液态玻璃样式。
- 调整顶部工具栏的半透明效果，滚动到下方的内容仍可透过工具栏看到。
- 改善日历滚动性能。

### v0.6.1 — 页面切换与项目列表

**改进**

- 减少通过侧栏切换页面时的卡顿。

**修复**

- 修复「总待办」中项目文件夹图标跳动的问题。

### v0.6.0 — 日历周视图与直接编辑

**新增**

- 新增日历周视图，在每日时间线上方显示跨天待办。可拖动分隔线调整上下两区的空间。
- 可拖过日历中的空白日期，为新待办设置日期范围。
- 可直接拖动日历中的待办条改期，或拖动两端调整开始和结束日期。
- 日历待办新增右键菜单，选中后可按 Delete 删除、按回车编辑，也可复制并粘贴到另一个日期。

**改进**

- 适配 macOS 27。

### v0.5.2 — 总待办筛选与逾期提示

**新增**

- 「总待办」新增筛选，可按项目、标签和状态等条件查找待办。
- 「总待办」显示逾期状态，并添加独立的逾期筛选条件。

**改进**

- 减少切换页面时的卡顿。

### v0.5.1 — 进行中状态与安排修复

**新增**

- 待办新增「进行中」状态。
- 待办可分别设置开始和结束日期，覆盖连续多天。

**改进**

- 在今日时间线上突出显示当前正在进行的安排。
- 改善待办编辑器中的标签颜色显示。
- 将日历日期的可点击区域与视觉位置对齐。
- 扩大项目展开和收起按钮的可点击区域。

**修复**

- 修复窗口最大化后日历消失的问题。
- 修复「总待办」向上滚动时出现的异常跳动。
- 修复安排变化后，「今日安排」中的「已安排」和「未安排」分组未及时刷新的问题。
- 修复部分时间块无法从时间线编辑的问题。

### v0.5.0 — 每日时间线

**新增**

- 在「今日」页面新增每日时间线。可把待办拖入时间线留出时间，也可在空白时段拖出普通安排。
- 待办编辑器新增预计时长。

**改进**

- 「今日」待办列表按未安排、已安排和已完成分组。

### v0.4.1 — 布局与滚动修复

**改进**

- 调整控件宽度以适应较长的译文。
- 「总待办」中新项目默认收起，应用会记住各项目的展开状态。

**修复**

- 修复调整窗口大小时的日历滚动定位问题。

### v0.4.0 — 数据恢复与日历导航

**新增**

- 新增自动本地备份。主数据文件损坏时，可以选择从备份恢复。

**改进**

- 改善数据保存失败时的提示，并支持重试。
- 扩展待办、项目和标签编辑的撤销与重做支持。
- 改善日历滚动时按周和月定位的体验。

**修复**

- 修复切换时区时已保存的待办日期可能发生偏移的问题。

### v0.3.0 — 项目与标签

**新增**

- 新增项目，用于归拢相关待办。「总待办」可展开项目下的子任务并查看项目进度。
- 新增颜色标签，可跨项目分类待办。

### v0.2.0 — 语言与外观设置

**新增**

- 新增界面语言选择。
- 新增跟随系统、浅色和深色外观设置。
- 待办可分别设置重要度与紧急度。

**改进**

- 改进日历和日期选择控件。

### v0.1.0 — 初始版本

**新增**

- 推出 macOS 版 DayVDO，提供「今日」「总待办」和月历。
- 可为待办填写备注、截止日期和优先级，并记录完成状态。待办数据保存在本机。
