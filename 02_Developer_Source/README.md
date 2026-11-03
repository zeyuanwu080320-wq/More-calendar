# More calendar

一个只在本机运行的 macOS 小工具：把学校邮件正文、预约确认截图、活动海报截图里的日期/截止/时间/地点抽成候选事件；用户逐条核对后，再写入 Apple 日历。

技术栈：SwiftUI + Vision（本地 OCR）+ EventKit + URLSession + DeepSeek `chat/completions`。

## 当前状态

- 用户交付包：`../01_User_Delivery/SchoolEventInbox.zip`（附中英双版使用说明）
- 源码备份：`../03_Backup_Archives/SchoolEventInbox_v1.0_Source_Backup.zip`
- 发布前完整自测：`99 passed, 0 failed, 1 skipped`（Keychain CLI 探测被当前命令沙箱拒绝；见下）
- 本次增量（全天/生日/管理/中英/标签）自测：`73 passed, 0 failed`
- 发布整理已删除测试截图、测试样本和 XCTest 代码；SelfTest 在样本缺失时会跳过样本/OCR 项
- 真实 DeepSeek 调用：你本机 2026-10-31 16:27 的日志已记录一次成功解析（2 条事件，约 1.9 秒）
- 真实 Apple 日历写入：未自动执行；若系统只授予“仅写入”，需要升级为完整访问（见“日历权限”）
- 本机没有完整 Xcode，已生成 `.xcodeproj` 并做 plist/路径校验；尚未用 `xcodebuild` 验证

## 直接运行

```bash
cd /Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source
open ../build/SchoolEventInbox.app
```

重新构建源码并运行：

```bash
./Scripts/build_app.sh --run
```

构建脚本会在本机没有 Xcode 时使用 Command Line Tools 的 SwiftPM，并自动选择与 Swift 编译器匹配的 `MacOSX26.5.sdk`。构建产物在源码上一层的 `build/SchoolEventInbox.app`；`01_User_Delivery/SchoolEventInbox.zip` 是分发包。

## 首次使用

1. 点右上角钥匙图标，填入 DeepSeek API Key，保存到 macOS Keychain。
2. 左侧粘贴 Outlook 邮件正文，或在图片区按 `⌘V` 粘贴截图，或拖入 `.png` / `.jpg`。
3. 点“解析”（`⌘R` / `⌘↩`）。图片先在本机 Vision OCR；只把 OCR 文本和邮件正文发给 DeepSeek。
4. 右侧逐条核对：类型、标题、开始/结束时间、全天、地点、原文依据、置信度、歧义说明。`deadline` / `appointment` / `exam` 默认确认且不可取消；普通活动也默认确认。
5. 点“写入 Apple 日历”。首次写入会请求完整日历权限。
6. 有时间冲突时：默认跳过冲突事件，底部显示“已写入 N 条，M 条时间冲突未写入”。在卡片里打开“冲突仍写入”后可再次写入。

## 管理事件与批量平移

- 顶部工具栏“管理事件”或菜单 `⌘⇧M` 打开管理面板。
- 只显示备注包含 `[SchoolEventInbox-Managed]` 或 `[Managed by SchoolEventInbox]` 的事件，绝不显示手动添加的私人事件。
- 可单条删除、清空所有（二次确认）、刷新。
- 支持多选、全选/取消全选，以及 +1h / -1h / +1d / -1d / +1w 或自定义小时+分钟的批量平移。
- 循环事件不允许批量平移；移动后保留持续时间、全天 00:00 规则、托管标签和冲突跳过提示。
- 删除循环事件使用 `.futureEvents`，移除未来的发生记录。

## 快捷键

- `⌘↩`：解析
- `⌘⇧↩`：写入 Apple 日历（按钮禁用时快捷键也不触发）
- `⌘V`：邮件文本框聚焦时粘贴文本；焦点不在文本框且剪贴板含图片时粘贴截图
- `⌘R`：解析（菜单快捷键，保留）
- `⌘⇧M`：打开管理事件
- 没有新增 `⌘A` 逻辑

## 生日与全天

- `birthday` 类型在卡片上显示 🎂 提示，强制全天并隐藏结束时间。
- 写入 EventKit 时生日事件使用 `isAllDay = true` 和年度重复规则；管理面板删除时使用 `.futureEvents`。
- 普通事件开启“全天”时，开始/结束 DatePicker 只显示日期；关闭后恢复时间选择。EventKit 全天区间统一归零到当天 00:00。

## 中英双语

- 工具栏“中/EN”一键切换；语言偏好保存在 `SchoolEventInbox.uiLanguage`。
- 英文静态文案由 `Resources/en.lproj/Localizable.strings` 提供，动态状态/错误由 `L10n` 映射。
- 源码内另附 `User_Guide_EN.txt`；交付目录含中英双版手册。

## 应用图标

`icon.png`（1024×1024 RGBA）先处理为 `processed_icon.png`：新建 1024×1024 透明画布，将原图缩放到 824×824 并居中（四边各 100px）。macOS 26 会给透明留白自动垫一层灰色底板，因此最终 icns 使用由同一原图派生的不透明品牌背景画布 `AppIcon_canvas.png`（824 前景保留，背景为同色系柔化延展），再生成 `AppIcon.iconset` 和 `AppIcon.icns`。`Scripts/build_app.sh` 在签名前把图标复制到 `../build/SchoolEventInbox.app/Contents/Resources/AppIcon.icns` 并设置 `CFBundleIconFile=AppIcon`；未使用 Asset Catalog。若 `AppIcon.icns` 不存在，构建会打印警告并继续，不中断。

## 日历权限

为了“写入前检查冲突”，本工具需要**完整日历访问**，不仅是“仅写入”：

- 若底部显示“仅有写入权限，无法检查冲突”，点“升级为完整访问”，在系统提示中允许。
- 若权限被拒绝：“写入”按钮会禁用，底部有“打开系统设置”的链接。
- 不会在后台读取或监听日历；只在点击写入时查询同一时间段的事件。

## API Key 与 Keychain

- service：`local.duishangque.SchoolEventInbox`
- account：`deepseek-api-key`
- UI **不会回显**已保存的 Key。
- Key 不写入代码库、`UserDefaults`、日志或导出文件。
- 启动时不访问 Keychain，避免一打开就弹系统解锁框。
- 本机曾重新构建 `.app`，旧 ad-hoc 签名变化后，旧 Keychain 条目可能要求一次系统授权：
  - 首次解析弹出 Keychain 密码时，选择 **Always Allow**；或
  - 打开“API Key”重新保存一次（会重建当前构建的访问 ACL）。
- 之后的构建使用稳定 designated requirement：`identifier "local.duishangque.SchoolEventInbox"`。

## 隐私边界

- 粘贴/拖入的图片只在内存中处理，不落盘。
- 只把邮件正文 + OCR 文本发给 DeepSeek；不发送图片二进制。
- 每次解析写一条结构化摘要：`ts / inputType(email|image) / eventCount / types / editedFields / error / durationMs`；编辑字段在写入记录中补充。
- 日志不记录邮件原文、标题、地点、evidence、图片路径、邮箱、学号/身份证/手机号。
- 日志入库前和导出前各执行一次脱敏：邮箱、10 位以上连续数字、身份证形态 → `[REDACTED]`。
- 日志文件权限 `0600`：`~/Library/Application Support/SchoolEventInbox/log.jsonl`。
- 底部“导出最近 30 条”导出脱敏 JSONL。
- 底部“清空日志”会先弹一次确认，只删除 `log.jsonl`，不删除其他文件。

## 自测

```bash
./Scripts/run_selftest.sh
```

日志写到 `build/selftest.log`。自测覆盖：

- 5 个样本输入与 JSON 契约
- 邮件拆分成 deadline/activity、缺年份、重复语义、空结果
- DeepSeek 请求头/模型/`response_format=json_object`/错误映射（本地网络桩）
- Vision OCR 真实图片（预约、海报、无日期）
- 日期/时区/歧义
- 日志摘要字段、入库/导出脱敏、最近 30 条导出、旧日志迁移、清空日志、权限、统计
- 生日类型、托管标签、全天区间、73 项增量自测
- Keychain 与日历权限状态

## Xcode 工程

```bash
open SchoolEventInbox.xcodeproj
```

工程由 `Scripts/generate_xcodeproj.py` 生成，包含：

- `SchoolEventInbox` App target（唯一 target）
- shared scheme
- 发布版不再包含测试 fixtures 或 XCTest target

因本机只有 Command Line Tools，`xcodebuild` 不可用；已用 `plutil` 和路径校验，但未在 Xcode 中实际编译。SwiftPM 构建覆盖了同一批源码。

## 目录

```text
Sources/SchoolEventInbox/           SwiftUI App、AppModel、图片/Keychain UI
Sources/SchoolEventInboxCore/       模型、日期解析、OCR、DeepSeek、EventKit、日志
Sources/SchoolEventInbox/Resources/system_prompt.txt
Tests/SelfTest/                     Command Line Tools 可运行的自测
（发布整理已删除测试 fixtures 与 XCTest 代码）
icon.png                            1024×1024 RGBA 原图
processed_icon.png                  1024 透明画布 + 824 居中图标（透明中间态）
AppIcon_canvas.png                  不透明品牌背景画布（用于 macOS 26 图标）
AppIcon.iconset/                    sips 生成的 10 个尺寸
AppIcon.icns                        iconutil 生成的多尺寸图标
Scripts/build_app.sh                本地构建 .app + 图标 + 稳定签名
Scripts/run_selftest.sh             运行最终自测
Scripts/generate_xcodeproj.py       生成 Xcode 工程
User_Guide_EN.txt                  英文使用说明（源码目录）
Sources/SchoolEventInbox/Views/ManagedEventsView.swift   管理事件/批量平移
Sources/SchoolEventInbox/LanguageManager.swift           中英切换
```

## 不做的事

- 不做 Outlook OAuth / Microsoft Graph
- 不后台监听邮箱、相册、剪贴板
- 不做重复事件规则编辑器
- 不做跨平台、账号、云同步、多设备协作
- 不做分享、模板市场、分发/上架
- 不替用户判断“一定不会漏”

## 已知限制

见 [TODO.md](TODO.md) 和 [TEST_REPORT.md](TEST_REPORT.md)。
