# More calendar — 项目交接文档（HANDOFF）

> 面向对象：**完全没有上下文的新 AI 工程师**。  
> 最后核对时间：2026-11-02 22:44（Asia/Hong_Kong）  
> 项目根目录：`/Users/duishangque/Desktop/编程/SchoolEventInbox`

---

## 1. 项目是什么

一个**本地 macOS 学校事件收件箱**：

1. 用户粘贴邮件正文，或拖入邮件截图 / 按 `⌘V` 粘贴截图。
2. 截图在本地用 Vision OCR；只把邮件正文和 OCR 文本发送给 DeepSeek。
3. DeepSeek 通过 OpenAI-compatible API 抽取候选事件。
4. 用户在卡片上逐条检查、修改、确认。
5. 用户点击“写入 Apple 日历”后才写入 EventKit；默认跳过时间冲突。
6. 可管理由本工具写入的事件：删除、清空、批量平移。

**不做**：OAuth、后台监听邮箱、云端存储、自动写入未经确认的日历事件。

---

## 2. 最终 App 名称与构建产物

### 2.1 显示名称

最终用户可见名称是：

```text
More calendar
```

已同时设置：

- `CFBundleDisplayName = More calendar`
- `CFBundleName = More calendar`

来源文件：

- 源码模板：`02_Developer_Source/Support/Info.plist`
- 当前构建：`build/More calendar.app/Contents/Info.plist`

**2026-11-02 起，bundle 文件名也已改为用户可见名：**

```text
build/More calendar.app
```

历史 bundle 文件名是 `SchoolEventInbox.app`，用户明确要求改成 `More calendar.app`，已完成重命名并重新签名。注意：

- **可执行文件名仍是 `SchoolEventInbox`**（`Contents/MacOS/SchoolEventInbox`，`CFBundleExecutable = SchoolEventInbox`）。只改了 `.app` 目录名，SwiftPM product 名和可执行文件名未动，所以 Activity Monitor 里进程名仍显示 `SchoolEventInbox`，这是预期的。
- `build_app.sh` 的输出路径已同步改成 `../build/More calendar.app`，以后构建不会再产回旧名字。
- `CFBundleIdentifier` 仍为 `local.duishangque.SchoolEventInbox`，**不要改**：它和稳定签名一起决定 Keychain 授权，改了会导致已保存的 API Key 读不出来。

- 当前 App 只有一个：

```text
build/More calendar.app
```

### 2.2 窗口标题

`Sources/SchoolEventInbox/SchoolEventInboxApp.swift`：

```swift
WindowGroup("More calendar") { ... }
```

`Sources/SchoolEventInbox/Views/ContentView.swift` 中窗口居中逻辑也匹配：

```swift
guard let window = NSApp.windows.first(where: { $0.title == "More calendar" })
```

`Sources/SchoolEventInbox/AppDelegate.swift` 的兜底窗口标题也是 `More calendar`。

### 2.3 当前构建状态

- **功能已冻结（2026-11-03），版本 1.0.0**
- 构建时间：2026-11-03 00:13 左右（终版由 `build_app.sh` 重建并签名）
- 当前 App 签名：

```bash
codesign --verify --deep --strict --verbose=2 "build/More calendar.app"
# valid on disk
# satisfies its Designated Requirement
```

- 交付包：`01_User_Delivery/More calendar.zip`（3.8 MB，含新图标、新名字、按类型分配日历、批量删除、双语与冲突详情）
- 最新源码备份：`03_Backup_Archives/MoreCalendar_v1.0_Source_Backup.zip` — 已含 P1 修复
- 旧源码备份（仅代码，非当前版本）：`03_Backup_Archives/SchoolEventInbox_pre_incremental_20261101_1113.zip`
- 旧图标备份：`03_Backup_Archives/Icon_previous_20261102_2255/`

**旧 App 副本已清理：**

- 曾存在 `01_User_Delivery/SchoolEventInbox.app`
- 曾存在 `01_User_Delivery/SchoolEventInbox 2.app`
- 曾存在 `02_Developer_Source/build/SchoolEventInbox.app`

这些旧 App 已删除；`01_User_Delivery/` 现在**只允许**放 `More calendar.zip` + 中英文说明书，**绝对不要在交付目录里解压出 `.app`**。当前唯一 App bundle 是 `build/More calendar.app`。

---

## 3. 目录结构

```text
SchoolEventInbox/
├── HANDOFF.md                          ← 本文件
├── 01_User_Delivery/
│   ├── More calendar.zip               ← 交付包（新图标 + 新名字）
│   ├── 使用说明.txt
│   └── 使用说明_EN.txt
├── 02_Developer_Source/
│   ├── Package.swift
│   ├── Support/Info.plist
│   ├── Sources/
│   │   ├── SchoolEventInbox/           ← macOS App / SwiftUI 层
│   │   └── SchoolEventInboxCore/       ← 模型、解析、日历、日志、Keychain
│   ├── Tests/SelfTest/                 ← 81 项自测
│   ├── Scripts/
│   │   ├── build_app.sh
│   │   ├── run_selftest.sh
│   │   ├── generate_xcodeproj.py
│   │   └── make_icon.swift             ← 图标画布处理（1024 满铺）
│   ├── SchoolEventInbox.xcodeproj/     ← 生成物；未用 xcodebuild 编译
│   ├── AppIcon.iconset/                ← 10 个尺寸（16…512 + @2x）
│   ├── AppIcon.icns                    ← 当前图标，满铺 1024
│   ├── icon.png                        ← 原始素材 1254×1254
│   ├── icon_adjusted.png               ← 处理后的 1024 画布
│   ├── .gitignore
│   ├── User_Guide_EN.txt
│   ├── README.md
│   ├── TEST_REPORT.md
│   └── TODO.md
├── 03_Backup_Archives/
│   ├── MoreCalendar_v1.0_Source_Backup.zip          ← 当前源码备份（含 P1）
│   ├── SchoolEventInbox_pre_incremental_20261101_1113.zip
│   └── Icon_previous_20261102_2255/                     ← 旧图标备份
└── build/
    └── More calendar.app
```

### 3.1 当前没有的东西

- 没有 Git 仓库
- 没有完整 Xcode（只有 Command Line Tools）
- 没有 `xcodebuild` 可用环境
- 源码目录在 P2 清理后**没有 `.build`**；运行 `build_app.sh` 或自测后会重新生成，发布前需再清一次
- 没有后台守护进程或服务器

---

## 4. UI 布局结构

### 4.1 顶层窗口

文件：`02_Developer_Source/Sources/SchoolEventInbox/Views/ContentView.swift`

```text
WindowGroup("More calendar")
└── ContentView
    └── VStack(spacing: 0)
        ├── HStack(spacing: 0)
        │   ├── InputPane
        │   │   宽度：min 430 / ideal 450 / max 520
        │   ├── Divider
        │   └── EventListPane
        │       宽度：min 580，右侧自适应
        ├── Divider
        └── FooterBar
```

默认窗口：

```swift
.defaultSize(width: 1220, height: 820)
.frame(minWidth: 1080, minHeight: 700)
```

### 4.2 顶部工具栏

顺序：

1. **API Key**
   - 文件：`Views/ContentView.swift`
   - 打开 `APIKeySheet`
   - 状态用 `key` / `key.fill` 图标
2. **刷新日历权限**
   - 图标：`calendar.badge.clock`
   - 仅刷新 EventKit 授权状态
3. **管理事件（文字按钮）**
   - 这是本次修正的入口
   - 当前实现：

```swift
Button {
    model.showManagedEvents = true
} label: {
    Text(verbatim: "管理事件")
}
```

   - 注意：`Text(verbatim:)` 是故意的，避免英文界面把它翻译成 `Managed Events`。
4. **中 / EN**
   - 调用 `language.toggle()`

工具栏下方：

- API Key 提示条
- 日志清空确认 alert
- `APIKeySheet`
- `ManagedEventsView`

### 4.3 左侧输入面板

文件：`02_Developer_Source/Sources/SchoolEventInbox/Views/InputPane.swift`

包含：

- “输入”标题与 `WorkStatus`（空闲 / 识别中 / 解析中 / 写入中 / 完成）
- 邮件正文 `TextEditor`
- 字数统计
- 截图区域：
  - 拖入 png/jpg
  - 点击后 `⌘V` 粘贴
  - 剪贴板图片按钮
- API Key 状态（Keychain）
- “解析”按钮

### 4.4 右侧待确认列表

文件：

- `02_Developer_Source/Sources/SchoolEventInbox/Views/EventListPane.swift`
- `02_Developer_Source/Sources/SchoolEventInbox/Views/EventCard.swift`

`EventCard` 从上到下：

1. 类型菜单：图标 + 名称 + 下拉
   - `deadline` 橙色 `clock.badge.exclamationmark`
   - `appointment` 蓝色 `calendar.badge.clock`
   - `exam` 红色 `graduationcap.fill`
   - `birthday` 粉色 `birthday.cake.fill`
   - `activity` / `other` 灰色/次要色
2. 标题输入
3. 开始日期/时间
4. 结束日期/时间
5. 全天开关
6. 地点
7. 原文依据 `evidence`
8. 歧义说明 `notes`
9. 置信度滑块
10. 冲突提示 + “冲突仍写入”
11. 确认勾选
12. 生日提示条（仅 birthday）

### 4.5 底部状态栏

文件：`02_Developer_Source/Sources/SchoolEventInbox/Views/FooterBar.swift`

- 左侧：
  - 当前默认日历名称
  - 最近 14 天统计
  - 日历权限提示 / 升级按钮
- 右侧：
  - 清空日志
  - 导出最近 30 条
  - 写入 Apple 日历

### 4.6 管理事件面板

文件：`02_Developer_Source/Sources/SchoolEventInbox/Views/ManagedEventsView.swift`

- Sheet 尺寸固定：`760 × 620`
- 内容：
  - Header：标题 + “仅显示本工具创建的事件”
  - 刷新
  - 关闭
  - 权限不足页 / 空状态 / 事件列表
  - 底部：全选、取消全选、已选择数量、清空所有、批量平移
  - 批量平移 sheet：+1h、-1h、+1d、-1d、+1w、自定义小时/分钟
  - 删除循环事件确认
  - 清空全部确认

入口有两个：

1. 顶部工具栏文字按钮 `管理事件`
2. App 菜单 `School Event` → `Managed Events` / `⌘⇧M`

---

## 5. 最近修改的 3 个核心文件

以下 3 个文件是本次四项修正最关键的改动。其他配套文件列在 5.4。

---

### 5.1 `Sources/SchoolEventInbox/Resources/system_prompt.txt`

**修改类型：解析规则（T4 的核心）**

**为什么改：**

原规则要求 `start/end` 必须包含年份；缺年份时要求置 null。用户提供的英文名单没有年份，因此模型直接失败/丢弃。现在明确支持：

- 英文月份全拼：
  - `January` / `Jan`
  - `February` / `Feb`
  - `March` / `Mar`
  - `April` / `Apr`
  - `May`
  - `June` / `Jun`
  - `July` / `Jul`
  - `August` / `Aug`
  - `September` / `Sep` / `Sept`
  - `October` / `Oct`
  - `November` / `Nov`
  - `December` / `Dec`
- 英文日期格式：`Month Day`、`Month Day, Year`
- **缺年份时默认当前年份**，并在 `notes` 写：
  - `缺年份，默认今年`
- 没有具体时分时：
  - `allDay = true`
  - `start = 当前年份-MM-DDT00:00:00+08:00`
  - `end = null`
  - `notes` 说明仅日期
- 一行一个“日期 - 姓名”的名单：
  - 每行拆为一条独立事件
  - `type = "birthday"`
  - `allDay = true`
  - `title = "姓名 + 生日"`
  - `location = null`
  - `needsConfirmation = true`
  - `notes` 包含“缺年份，默认今年”
- JSON schema 的 `type` 枚举新增：

```text
deadline|appointment|activity|exam|birthday|other
```

- `needsConfirmation` 对 `deadline`、`appointment`、`exam`、`birthday` 必须为 true。

**重要：**不要恢复“缺年份就置 null/丢弃”的旧规则。

---

### 5.2 `Sources/SchoolEventInbox/Views/EventCard.swift`

**修改类型：全天 UI + 生日 UI**

开始时间现在显式分支：

```swift
if draft.allDay {
    DatePicker("开始", selection: $draft.start, displayedComponents: .date)
        .id("start-all-day")
} else {
    DatePicker("开始", selection: $draft.start,
               displayedComponents: [.date, .hourAndMinute])
        .id("start-timed")
}
```

结束时间同样：

```swift
if draft.allDay {
    DatePicker("结束", selection: $draft.end, displayedComponents: .date)
        .id("end-all-day")
} else {
    DatePicker("结束", selection: $draft.end,
               displayedComponents: [.date, .hourAndMinute])
        .id("end-timed")
}
```

效果：

- 开启“全天”后 DatePicker **不再显示时间**
- 关闭后恢复日期 + 时间
- `.id(...)` 强制 SwiftUI 在分支切换时重建控件，避免复用旧的 DatePicker 配置

生日逻辑：

- `birthday` 类型：
  - 强制全天
  - 隐藏结束时间行
  - 禁用“全天”开关（保持 birthday 全天）
  - 显示“🎂 生日（将设为每年重复）”
- 普通类型切换回非全天时恢复时间选择

**写入 EventKit 的全天确认在 `CalendarService.swift`：**

```swift
event.isAllDay = isBirthday ? true : draft.allDay
```

生日额外：

```swift
event.startDate = calendar.startOfDay(for: ...)
event.endDate = calendar.startOfDay(for: ...).addingTimeInterval(86_400)
event.recurrenceRules = [
    EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
]
```

管理面板删除循环事件：

```swift
let span: EKSpan =
    (event.recurrenceRules ?? []).isEmpty ? .thisEvent : .futureEvents
```

---

### 5.3 `Sources/SchoolEventInbox/Views/ContentView.swift`

**修改类型：管理入口 + 窗口标题匹配**

旧实现是图标按钮：

```swift
Label("管理事件", systemImage: "calendar.badge.gearshape")
```

现在改为纯文字普通按钮：

```swift
Button {
    model.showManagedEvents = true
} label: {
    Text(verbatim: "管理事件")
}
```

重要细节：

- **2026-11-03 起已改为 `L10n.t("管理事件", "Managed Events")`**，随界面语言即时切换。
- 历史：早期为了让入口固定显示中文，曾用 `Text(verbatim:)` 写死；该临时行为已按用户要求移除，不要再改回 verbatim。
- 同一工具栏的「刷新日历权限」和两个 tooltip 也一并接入了 `L10n.t`。
- 点击后仍然设置 `model.showManagedEvents = true`，sheet 仍正常弹出。
- 工具栏里另一个日历图标是“刷新日历权限”，不要误删。

同时窗口居中判断从旧名改为：

```swift
$0.title == "More calendar"
```

---

### 5.4 其他配套改动（不是“3 个核心”，但必须知道）

- `Sources/SchoolEventInboxCore/Utilities/EnglishBirthdayListParser.swift`（新文件）
  - 对整段英文月份/日期/姓名名单做确定性归一化
  - 仅当**每一行**都匹配时启用
  - 输出 7 条 `birthday` / `allDay=true`
  - 自动补当前年份
  - `notes` 包含“缺年份，默认今年”
- `Sources/SchoolEventInboxCore/Services/DeepSeekService.swift`
  - API 返回 JSON 后解码
  - 若名单 fallback 命中，覆盖模型可能给出的 `other`
  - 不改 API 请求结构、不改模型
- `Sources/SchoolEventInbox/SchoolEventInboxApp.swift`
  - `WindowGroup("More calendar")`
  - 管理菜单命令 `⌘⇧M`
- `Sources/SchoolEventInbox/Views/ContentView.swift`
  - 文字按钮 + 标题匹配
- `Support/Info.plist` / `build/.../Info.plist`
  - `CFBundleDisplayName` / `CFBundleName` = `More calendar`
- `Sources/SchoolEventInbox/AppDelegate.swift`
  - 极端情况下 WindowGroup 恢复成无窗口时，兜底创建一个 `More calendar` 窗口
  - 正常启动不应创建重复窗口
- `Sources/SchoolEventInboxCore/Services/CalendarService.swift`
  - 生日全天 + 年度重复
  - 托管标签、删除、批量平移
  - 导入备注中的显示名改为 `More calendar`

---

## 6. 解析链路（新工程师最需要理解的部分）

```text
InputPane（正文 / 截图）
  ↓
AppModel.parse()
  ↓
OCRService（截图时本地 OCR）
  ↓
DeepSeekService
  ├── PromptLoader 读取 system_prompt.txt
  ├── DeepSeek OpenAI-compatible API
  ├── JSON 解码
  ├── EnglishBirthdayListParser（整段英文名单的确定性兜底）
  └── ParsedEventSanitizer
  ↓
ParsedEvent
  ↓
DraftFactory.makeDraft(s)
  ├── FlexibleDateParser 处理 ISO/日期
  ├── EventDraft 全天归一化
  └── 校验、默认值、冲突字段
  ↓
EventCard（人工确认）
  ↓
CalendarService.write()
  ↓
EventKit / Apple 日历
```

### 6.1 全天的两层保证

1. **UI**：`EventCard.swift` 的 `.date` 分支
2. **写入**：`CalendarService.write()` 的 `event.isAllDay = ...`
3. **Draft**：`EventDraft.calendarInterval` 对全天使用 `startOfDay`，结束为次日 00:00

### 6.2 7 个英文生日事件现在的情况

**是，已能解析，且已验证。**

实际输入：

```text
December 8 - Hayeon
January 22 - Olena
May 14 - Tina
Dec 21 - Lisa
Dec 2 - Jack
May 4 - Hanna
November 7 - Fiorelli
```

真实 DeepSeek 调用后的日志：

```json
"eventCount": 7,
"types": ["birthday","birthday","birthday","birthday","birthday","birthday","birthday"]
```

自测还额外检查：

- 7 条全部 `type == .birthday`
- 7 条全部 `allDay == true`
- 缺年份时使用当前年份（测试固定为 2026）
- 标题为“姓名 + 生日”
- `needsConfirmation == true`
- `notes` 包含“缺年份，默认今年”

注意：

- **fallback 只在 DeepSeek HTTP 成功返回后触发**。如果 API 失败、网络失败、Keychain 无 Key，仍会显示解析错误，不会静默生成 7 条本地事件。
- fallback 只匹配“整段输入都是英文月份+日+姓名”的情况；混合邮件内容仍主要依赖模型 + prompt。
- 日期无时区时按 `+08:00` / 当前系统的日期逻辑处理；这是当前项目的显式假设。

---

## 7. 管理事件面板（当前实现）

### 7.1 托管标签

`CalendarService.swift`：

```swift
managedTag = "[SchoolEventInbox-Managed]"
compatibilityTag = "[Managed by SchoolEventInbox]"
typeTagPrefix = "[SchoolEventInbox-Type:"
```

写入时**两个标签都写**，以兼容历史两版规格：

```text
[SchoolEventInbox-Managed]
[Managed by SchoolEventInbox]
[SchoolEventInbox-Type:birthday]
```

管理面板过滤条件为包含任一标签。

**已知限制：**

- 旧版本写过但没有任何标签的事件不会出现在管理面板。
- 不要只保留一个标签，除非确定做迁移并更新过滤逻辑。

### 7.2 时间范围

`fetchManagedEvents()` 读取：

```text
过去 1 个月 ~ 未来 1 年
```

### 7.3 权限

- 管理面板需要 **完整日历访问**。
- 权限不足时显示“需要完整权限才能管理”。
- `writeOnly` / `notDetermined` 显示“请求完整访问”按钮。
- `denied` / `restricted` 显示“打开系统设置”。
- **不会自动读取私人事件**；只按标签过滤。

### 7.4 删除

三种入口，语义各不相同，不要混淆：

| 入口 | 删除范围 | 二次确认 |
|---|---|---|
| 行内垃圾桶 | 单条 | 循环事件才确认 |
| **底部「删除选中」** | **仅勾选的事件** | 是，文案含数量 |
| 底部「清空所有」 | 全部带标签事件（不只是勾选的） | 是 |

- **「删除选中」**（2026-11-02 新增）：`CalendarService.deleteManagedEvents(ids:)` → `ManagedDeleteResult(deleted:failed:)`。
  - 只删传入 ID，未勾选的事件完全不受影响。
  - 循环事件自动用 `.futureEvents`。
  - 不存在的 ID 或非托管事件计入 `failed` 并跳过，不中断整批。
  - 删除后清空勾选并刷新列表。
  - 按钮在没有勾选时置灰；`.bordered` + 红色 tint，视觉上与「批量平移」同为主操作。
- **「清空所有」已弱化为纯文字次要操作**（`.plain` + 次级色），避免误点时连未勾选的一起删。
- 单条：列表删除按钮
- 循环事件：二次确认，使用 `.futureEvents`

### 7.5 批量平移

支持：

- `+1 小时`
- `-1 小时`
- `+1 天`
- `-1 天`
- `+1 周`
- 自定义小时 + 分钟

规则：

- 保持原持续时间
- 全天事件按整天平移，时间归零
- 循环事件拒绝批量平移
- 冲突事件跳过并汇总
- 使用 `.thisEvent` 保存
- 备注和托管标签不变

状态提示示例：

```text
成功平移 N 条，M 条因冲突失败
```

**冲突详情（2026-11-02 新增）**：不再只给数字。

- `ManagedShiftResult.conflictDetails: [ManagedShiftConflict]` 逐条记录
  `shiftedTitle`（被移动的事件）、`blockingTitle`（挡路的事件）、`newStart`、`blockingStart`。
- 视图层在 `applyShift` 后若 `conflictDetails` 非空，弹出「平移冲突详情」sheet，
  逐条显示「「A」平移后与「B」发生时间重叠，已跳过」加两侧时间。
- 底层把原来的 `hasConflict(start:end:excluding:) -> Bool` 换成
  `conflictingEvent(start:end:excluding:) -> EKEvent?`，因此能拿到挡路事件本身。
- **不要再退回"只返回计数"的实现**：静默失败是这次修掉的显式缺陷。

---

### 7.6 按类型分配日历（2026-11-02 新增，P3）

**为什么**：以前所有事件都写进同一个默认日历，Apple 日历里只能靠标题辨认，无法靠颜色区分考试 / 生日 / 截止。

**怎么实现**：`CalendarService.calendarForWriting(_:)`。

| 类型 | 日历标题 | 颜色 token | NSColor |
|---|---|---|---|
| deadline | `More Calendar - 截止` | orange | `systemOrange` |
| appointment | `More Calendar - 预约` | blue | `systemBlue` |
| exam | `More Calendar - 考试` | red | `systemRed` |
| birthday | `More Calendar - 生日` | purple | `systemPurple` |
| activity / other | `More Calendar - 活动` | green | `systemGreen` |

要点：

- **`EKCalendarColor` 在 EventKit 里不存在**。SDK 只有 `EKCalendar.color: NSColor` 和 `EKCalendar.CGColor`，所以映射做成 `ManagedCalendarColorToken` 枚举 + `nsColor` 计算属性。以后不要再找 `EKCalendarColor`。
- **activity 与 other 合并成一个日历**（`EventType.managedCalendarBucket`），否则两个日历要用同一种绿色，反而更乱。
- **`More Calendar - ` 前缀是唯一识别标记**：`EKCalendar` 没有 notes / 自定义字段，只能靠标题前缀跨启动匹配既有日历。
- 创建源优先顺序：默认日历所在账户（通常是 iCloud）→ 本地账户 → CalDAV。`.subscribed` / `.birthdays` 源不能放用户事件，永不使用。
- 创建失败或没有可用源时**不报错**，回退到 `defaultCalendarForNewEvents`，并通过 `routingNotice` 在底部状态栏提示「已回退到默认日历」。
- 同批次连续写同类型事件时，用 `routedCalendarIDs` 缓存 identifier，避免 `calendars(for:)` 尚未刷新导致重复建日历。
- **管理面板无需改动**：`fetchManagedEvents` 用 `calendars: nil` 跨全部日历取事件，仍按 `[SchoolEventInbox-Managed]` 标签过滤，所以删除 / 清空 / 批量平移照常工作。
- 自测只覆盖纯映射（16 条断言：标题、颜色、分桶、去重），**不会**在测试里创建真实日历。

**日历标题的语言同步（2026-11-02 新增）**：

- `EventType.managedCalendarLabel(for:)` 给出中/英后缀：截止/预约/考试/生日/活动 ↔ Deadline/Appointment/Exam/Birthday/Activity。
- `CalendarService.titleLanguage` 决定新建日历用哪种语言；`AppModel` 在初始化与语言切换时同步它。
- `calendarForWriting` 先按当前语言找，找不到**再按另一种语言找并改名**，因此不会因为切换语言而重复建两个日历。
- `syncManagedCalendarTitles(to:)` 在切换语言时遍历所有带前缀的日历并改名；
  **需要完整日历权限**，权限不足或改名失败时**静默 return，不报错、不阻断主流程**。
- `managedCalendarBucket(forTitle:)` 是标题→类型的反向解析，改名逻辑依赖它。

**已知边界**：

- 清空事件不会删除这些空日历；如要清理，需在 Apple 日历里手动删。
- 改名只处理带 `More Calendar - ` 前缀且属于已知类型后缀的日历；用户自己改过名的日历不会被接管。
- 若用户自己建了同名 `More Calendar - 考试`，会被直接接管（前缀即约定）。
- 写入权限为「仅写入」时无法建日历，会全部回退到默认日历。

---

## 8. 编译、测试、打包命令

### 8.1 环境

- macOS 26.6.2
- Apple M5
- Command Line Tools，**没有完整 Xcode**
- SDK：`/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`
- SwiftPM
- 构建脚本默认使用 debug 构建（不是 release）

### 8.2 构建最新 App

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source"
./Scripts/build_app.sh
```

输出：

```text
../build/More calendar.app
```

脚本会：

- `swift build --disable-sandbox`
- 自动选择 SDK
- 复制可执行文件
- 复制 `Support/Info.plist`
- 复制 SwiftPM 资源 bundle
- 复制 `en.lproj`
- 如果 `AppIcon.icns` 存在，复制并设置 `CFBundleIconFile`
- **`AppIcon.icns` 现在存在于源码目录**（2026-11-02 更换的满铺 1024 新图标），重建会自动带上图标，不会再出现“跳过图标”的警告。旧的 `AppIcon_canvas.png` / `processed_icon.png` 已被用户删除，不要恢复。
- 使用稳定 ad-hoc 签名：
  - identifier：`local.duishangque.SchoolEventInbox`
  - designated requirement：`identifier "local.duishangque.SchoolEventInbox"`

构建并运行：

```bash
./Scripts/build_app.sh --run
```

### 8.3 直接 SwiftPM 命令

如果不想用脚本：

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

CLANG_MODULE_CACHE_PATH="$PWD/.build/clangcache" \
swift build \
  --disable-sandbox \
  --sdk "$SDK" \
  --cache-path "$PWD/.build/cache" \
  --scratch-path "$PWD/.build/scratch" \
  --manifest-cache local
```

### 8.4 自测

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source"
./Scripts/run_selftest.sh
```

最近结果：

```text
RESULT: 81 passed, 0 failed
```

自测会创建：

- `02_Developer_Source/.build/`
- `02_Developer_Source/build/selftest.log`

发布前要清理它们。

### 8.5 Xcode 工程

没有完整 Xcode，不能 `xcodebuild`。但可以生成并验证 project：

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source"
python3 Scripts/generate_xcodeproj.py
plutil -lint SchoolEventInbox.xcodeproj/project.pbxproj
```

生成的 Xcode 工程包含：

- App target
- AppDelegate / LanguageManager / ManagedEventsView
- `en.lproj`
- 资源文件夹

**不要声称已经用 Xcode 编译过；当前实际编译路径只有 SwiftPM + build_app.sh。**

### 8.6 打包为交付 zip

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox"

rm -f "01_User_Delivery/More calendar.zip"
ditto -c -k --norsrc --noextattr --keepParent \
  "build/More calendar.app" \
  "01_User_Delivery/More calendar.zip"
```

注意：`01_User_Delivery/` 里**只能**有这个 zip 和两份说明书；打包后不要在里面解压验证，要验证就解到 `/tmp`。

### 8.7 源码备份 zip

**必须先清理 `.build`，否则会把几百 MB 缓存打进源码包。**

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox"

rm -rf 02_Developer_Source/.build 02_Developer_Source/build
find . -name '.DS_Store' -delete

rm -f 03_Backup_Archives/MoreCalendar_v1.0_Source_Backup.zip
ditto -c -k --norsrc --noextattr --keepParent \
  02_Developer_Source \
  03_Backup_Archives/MoreCalendar_v1.0_Source_Backup.zip
```

当前源码包约 4.4 MB；如果变成 100 MB 以上，通常是误把 `.build` 打进去了。

### 8.8 最终验证

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox"

APP="build/More calendar.app"

# 名称
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP/Contents/Info.plist"

# 图标
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist"
ls -lh "$APP/Contents/Resources/AppIcon.icns"

# 英文资源
find "$APP/Contents/Resources" -maxdepth 2 -name Localizable.strings -print

# 签名
codesign --verify --deep --strict --verbose=2 "$APP"

# zip 完整性 + 顶层条目必须是 "More calendar.app/"
unzip -t "01_User_Delivery/More calendar.zip"
unzip -l "01_User_Delivery/More calendar.zip" | head -6
```

预期：

```text
More calendar
More calendar
AppIcon
... valid on disk
... satisfies its Designated Requirement
```

### 8.9 发布前清理

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox"
rm -rf 02_Developer_Source/.build 02_Developer_Source/build
find . -name '.DS_Store' -delete
find 02_Developer_Source -name 'xcuserdata' -type d -prune -exec rm -rf {} +
```

---

## 9. 当前已验证 / 未验证状态

### 9.1 已验证

- `CFBundleDisplayName` 和 `CFBundleName` = `More calendar`
- 窗口标题截图确认 `More calendar`
- 顶部文字按钮 `管理事件` 可见，点击可打开管理面板
- 管理面板空状态/已有托管事件列表可显示
- 全天 DatePicker 显式 `.date` 分支
- EventKit `isAllDay` 代码路径
- 7 条英文生日真实 API 解析日志：`eventCount=7`，types 全部 `birthday`
- 英文生日解析单元测试：
  - 7 条
  - 全部 `birthday`
  - 全部 `allDay`
  - 当前年份
  - 缺年份 notes
- 81 项自测通过
- App 签名通过
- 最新 zip 可解压，App 名称和签名正确

**真实环境端到端验收（2026-11-02，P0 已通过）：**

- 用户本人与朋友在各自真实 Mac、真实日历权限下各自跑过完整流程，全部正常：
  - 写入 Apple 日历
  - 删除托管事件
  - 批量平移
  - 全天事件隐藏时间
  - 中英文切换
- 结论：**P0（真实日历端到端验收）已完成，不再需要旁听日志核对。**

**P3 按类型分配日历（代码侧已验证）：**

- 纯映射 16 条自测断言通过：五种类型 → 五个不同日历标题 + 五种不同颜色；`other` 归入活动桶。
- 干净构建 0 条代码警告；`strings`/字节检索确认新逻辑与新文案已进入 `More calendar.app` 二进制。
- **尚未在真实账户里执行建日历**：这一步会在用户账号下产生真实日历，必须由用户本人验收（见 §9.2 第 1 条）。
- 后续 P1 修复（`CalendarService` tags 改为 `nonisolated`）之后重跑自测仍为 `81 passed, 0 failed`。

### 9.2 尚未完成或需要人工验证

1. **P3 按类型分配日历的真实验收（待用户执行）**
   - 需要完整日历权限 + 真实账户；自动化测试不会去建真实日历。
   - 验收步骤：解析一段同时含「考试」和「生日」的文本 → 分别写入 → 在 Apple 日历中确认它们分别落在 `More Calendar - 考试`（红）与 `More Calendar - 生日`（紫），而不是同一个日历。
   - 再确认管理面板能看到并删除这两条事件。
   - 若权限只有「仅写入」，会全部回退到默认日历，这是预期行为。

2. **Keychain**
   - 自测在命令沙箱里读取 Keychain 返回 `OSStatus 100001`，所以 selftest 跳过 Keychain 用例。
   - App 内已有 API Key（界面显示“Keychain 中已有 API Key”）。
   - 需要 App 内验证保存、读取、删除流程；不要让 CLI 读取或打印 Key。

3. **Xcode 工程**
   - 已生成并通过 `plutil` 校验。
   - 未用 `xcodebuild` 编译（本机没有完整 Xcode）。
   - 不要声称 Xcode 构建通过。

4. **英文生日 fallback 的边界**
   - 只在 DeepSeek HTTP 成功返回后生效。
   - 只匹配整段输入都是 `Month Day - Name` 的名单。
   - 混合邮件、带额外正文的名单仍依赖 prompt + 模型。
   - 如果 API 失败，不会生成本地 7 条事件。

5. **日期/时区**
   - prompt 对“只有日期”的情况要求使用 `+08:00`。
   - fallback 使用当前系统时区构造 00:00。
   - 非中国时区或跨日边界需要额外验证。

6. **App 窗口恢复兜底**
   - `AppDelegate.swift` 增加了一个“无窗口时创建 fallback 窗口”的逻辑。
   - 正常启动会优先使用 SwiftUI WindowGroup。
   - 如果发现出现两个窗口或窗口不激活，优先检查这里。

7. **旧事件**
   - 旧版本写入但没有托管标签的事件不会出现在管理面板。
   - 这是设计上的保守行为，不要为了“看起来完整”而展示所有日历事件。

8. **管理按钮双语**
   - 工具栏入口已接 `L10n.t`，中/英即时切换，详见 §5.3。
   - 管理面板整体（按钮、空状态、权限页、弹窗）已改用 `L10n.t`，不再依赖 bundle 查表。

---

## 10. 安全与不可破坏的约束

1. **不要重写整个项目。**
2. **不要改 DeepSeek 请求结构、模型名、JSON 核心字段**，除非用户明确要求。
3. **不要删除托管标签兼容逻辑。**
4. **不要读取/打印用户 API Key。**
5. **不要未经用户确认写入或删除真实日历事件。**
6. **不要删除源码备份**（`03_Backup_Archives/*.zip`）；它们是代码备份，不是旧 App。
7. **不要改变稳定签名设置**：
   - `identifier "local.duishangque.SchoolEventInbox"`
   - designated requirement 同上
   - 改变会导致 Keychain 访问异常。
8. **图标当前状态**（2026-11-02 更换）：`02_Developer_Source/AppIcon.icns` 是满铺 1024 的新图标，可正常参与构建。除非用户要求，不要再改图标。
   - 关键经验：**macOS 26 会判定图案未铺满画布的图标为“旧式图标”，并在其后垫一块灰底板**。所以画布必须满边不透明，不要再用“图案缩到 824 + 透明画布”的旧做法。
   - 处理脚本：`Scripts/make_icon.swift`（裁掉原图透明留白 → 等比放大铺满 1024 → 用插画边框色渐变补满四角）。
   - 旧图标备份在 `03_Backup_Archives/Icon_previous_20261102_2255/`。
9. **`AppIcon_canvas.png` / `processed_icon.png` 已被用户删除，不要恢复。** `icon.png`（原始 1254×1254 素材）、`icon_adjusted.png`、`AppIcon.iconset/` 仍保留。
10. **不要改 `More Calendar - ` 日历标题前缀**，也不要删掉已有的事件备注托管标签。
    - 日历靠标题前缀识别，事件靠备注标签识别；两者任一改动，都会让下次写入重复建日历、或让管理面板认不出旧事件。
    - `EKCalendar` 没有 notes 字段，前缀是唯一可行的日历标记，不要改成"存到某个 UserDefaults 列表"之类的方案。
    - 事件备注标签（`[SchoolEventInbox-Managed]` / `[Managed by SchoolEventInbox]`）虽然带旧名，但**不可重命名**：已写入的真实事件用的就是这两个字符串。
11. **不要用 `rm -rf` 清理未确认的路径**；先 `realpath` 检查。

---

## 11. 新工程师建议阅读顺序

1. `README.md` — 产品、功能、已知限制
2. `TODO.md` — 历史增量与未完成项
3. `TEST_REPORT.md` — 自测明细
4. 本文件 `HANDOFF.md`
5. `Sources/SchoolEventInboxCore/Models/` — 数据模型
6. `Sources/SchoolEventInboxCore/Services/DeepSeekService.swift` — 解析入口
7. `Sources/SchoolEventInboxCore/Utilities/EnglishBirthdayListParser.swift` — 英文名单兜底
8. `Sources/SchoolEventInboxCore/Services/CalendarService.swift` — 日历写入/管理
9. `Sources/SchoolEventInbox/Views/ContentView.swift` — 主 UI
10. `Sources/SchoolEventInbox/Views/EventCard.swift` — 卡片交互
11. `Sources/SchoolEventInbox/Views/ManagedEventsView.swift` — 管理面板

---

## 12. 当前最终产物一览

```text
App:
/Users/duishangque/Desktop/编程/SchoolEventInbox/build/More calendar.app

交付包:
/Users/duishangque/Desktop/编程/SchoolEventInbox/01_User_Delivery/More calendar.zip

中文说明:
/Users/duishangque/Desktop/编程/SchoolEventInbox/01_User_Delivery/使用说明.txt

英文说明（交付）:
/Users/duishangque/Desktop/编程/SchoolEventInbox/01_User_Delivery/使用说明_EN.txt

英文说明（源码）:
/Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source/User_Guide_EN.txt

当前源码:
/Users/duishangque/Desktop/编程/SchoolEventInbox/02_Developer_Source

当前源码备份:
/Users/duishangque/Desktop/编程/SchoolEventInbox/03_Backup_Archives/MoreCalendar_v1.0_Source_Backup.zip

仅保留的最新 App bundle:
/Users/duishangque/Desktop/编程/SchoolEventInbox/build/More calendar.app
```

---

**一句话交接：**

> 显示名与 bundle 名都是 `More calendar`，唯一可运行 App 是 `build/More calendar.app`，交付包是 `01_User_Delivery/More calendar.zip`。**P0 已通过**：用户本人与朋友在真实 Mac、真实日历权限下验证了写入 / 删除 / 批量平移 / 全天隐藏时间 / 中英切换，全部正常。**P1 已完成**：`CalendarService` 三个托管标签常量改为 `nonisolated`，Swift 6 actor-isolation warning 清零，自测仍 `81 passed, 0 failed`。**P2 已完成**：清理 `.build` 与冗余备份解压目录、重打源码 zip、本文件目录树已对齐真实状态。**P2 补充**：bundle 已按用户要求重命名为 `More calendar.app`，`build_app.sh` 输出路径同步、重新签名并重打交付 zip，中英文说明书内的旧名已全部改为 `More calendar`（仅保留代码内部备注标签 `[SchoolEventInbox-Managed]` / `[Managed by SchoolEventInbox]` 不变）。**P3 已实现**：事件按类型自动写入独立日历（`More Calendar - 考试 / 生日 / 截止 / 预约 / 活动`），在 Apple 日历里靠颜色区分；创建失败自动回退默认日历；管理面板仍按托管标签跨日历识别。纯映射 16 条自测通过（总计 `97 passed, 0 failed`），但**真实建日历需用户本人验收**。
