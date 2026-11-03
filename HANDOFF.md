# More calendar — 项目交接文档（HANDOFF）

> 面向对象：**完全没有上下文的新 AI 工程师**。  
> 最后核对时间：2026-11-03 22:40（Asia/Hong_Kong）  
> 当前版本：**2.0.0（build 3）**  
> 项目根目录：`/Users/duishangque/Desktop/编程/SchoolEventInbox_V2.0`

---

## 0. 30 秒速览

| 项 | 值 |
|---|---|
| 是什么 | macOS 本地应用：邮件/截图/纯文本 → DeepSeek 抽取 → 人工逐条确认 → 写入 Apple 日历或提醒事项 |
| 版本 | 2.0.0（build 2） |
| 架构 | 写入选 `TargetProvider` 协议；EventKit 只存在于两个 Provider 文件里，Google 走 REST |
| 自测 | **200 passed, 0 failed** |
| 构建 | `02_Developer_Source/Scripts/build_app.sh` → `build/More calendar.app` |
| 仓库 | `https://github.com/zeyuanwu080320-wq/More-calendar.git`，发布分支 `main`，tag `v2.0.0` |
| 不做 | OAuth、后台监听邮箱、云端存储、未经确认的写入 |

**V2.0 相比 V1.0 做了四件事**（外加版本号）：

1. 写入侧从写死 EventKit 的 `CalendarService`，改为 `TargetProvider` 协议 + 多个 Provider。
2. 新增 **Apple 提醒事项** 作为第二个写入目标。
3. 新增 **纯文本输入**（跳过 OCR），并让「输入来源 / 写入目标」跨启动记忆。
4. 新增 **Google 日历**（OAuth 2.0 PKCE + loopback），并已由用户真机验收写入成功。

> 如果只读一段：先看 §4 架构 与 §12 Google Calendar 接入指南。

---

## 1. 项目是什么

1. 用户粘贴邮件正文 / 任意纯文本，或拖入邮件截图、按 `⌘V` 粘贴截图。
2. 截图在本地用 Vision OCR（纯文本模式不经过 OCR）；只把**文字**发给 DeepSeek。
3. DeepSeek 通过 OpenAI-compatible API 抽取候选事件。
4. 用户在卡片上逐条检查、修改、确认。
5. 用户点击「写入 Apple 日历」或「写入 Apple 提醒事项」后才真正写入；默认跳过时间冲突。
6. 可管理由本工具写入的**日历事件**：删除、清空、批量平移。

**不做**：OAuth、后台监听邮箱、云端存储、自动写入未经确认的日历事件。

---

## 2. 版本、名称与产物

### 2.1 显示名称

用户可见名称是 `More calendar`，同时设置：

- `CFBundleDisplayName = More calendar`
- `CFBundleName = More calendar`

源码模板：`02_Developer_Source/Support/Info.plist`

bundle 文件名也是用户可见名：`build/More calendar.app`（历史名为 `SchoolEventInbox.app`，已按用户要求改名）。

**不要动的三件事：**

- **可执行文件名仍是 `SchoolEventInbox`**（`Contents/MacOS/SchoolEventInbox`，`CFBundleExecutable = SchoolEventInbox`）。只改了 `.app` 目录名，SwiftPM product 名未动，所以 Activity Monitor 里进程名是 `SchoolEventInbox`，属预期。
- **`CFBundleIdentifier` 保持 `local.duishangque.SchoolEventInbox`**：它和稳定 ad-hoc 签名一起决定 Keychain 授权，改了已保存的 API Key 会读不出来。
- **bundle id 也决定 UserDefaults 域**，改了会让 §5.5 的记忆项失效。

### 2.2 窗口标题

`SchoolEventInboxApp.swift` 的 `WindowGroup("More calendar")`、`ContentView.swift` 的居中判断 `$0.title == "More calendar"`、`AppDelegate.swift` 的兜底窗口标题，三处必须一致。

### 2.3 当前构建状态

- 版本 **2.0.0 / build 2**（`Info.plist` 已从 1.0.0/1 升级）
- 签名：ad-hoc + 稳定 designated requirement

```bash
codesign --verify --deep --strict --verbose=2 "build/More calendar.app"
# valid on disk
# satisfies its Designated Requirement
```

- 交付包命名：`MoreCalendar_v2.0.0_macOS.zip`（约 3.8 MB），通过 **GitHub Release** 分发
- **zip 被 `.gitignore` 排除**（`MoreCalendar_v*.zip`），不进版本库
- 二进制为 **debug 配置**（`build_app.sh` 的既有约定，用户已知悉并接受）、arm64 only

### 2.4 仓库与发布

```text
remote : https://github.com/zeyuanwu080320-wq/More-calendar.git
main   : 发布分支（v2.0.0 的合并提交 2fae1c0，tag v2.0.0 指向它）
v2.0-dev: 本地开发分支（提交 12424ef "feat: release v2.0.0"）
```

- `gh` CLI **未安装**，GitHub Release 由用户在网页手动创建并上传 zip。
- 推送需要 PAT（HTTPS）；本机 `credential.helper = osxkeychain` 但无缓存凭据，`~/.ssh` 无密钥。

---

## 3. 目录结构

```text
SchoolEventInbox_V2.0/
├── HANDOFF.md                          ← 本文件
├── README.md                           ← 产品说明（中英双语）
├── RELEASE_NOTES_v2.0.0.md             ← GitHub Release 文案
├── LICENSE
├── MoreCalendar_v1.0.0_macOS.zip       ← 历史交付包（v1）
├── 02_Developer_Source/
│   ├── Package.swift                   ← SwiftPM；macOS 15+，两个 target + SelfTest
│   ├── Support/Info.plist              ← 版本、权限用途声明
│   ├── Sources/
│   │   ├── SchoolEventInbox/           ← macOS App / SwiftUI 层
│   │   │   ├── AppModel.swift          ← 唯一的 UI 状态中枢
│   │   │   ├── LanguageManager.swift   ← L10n.t + L10n.dynamic 翻译表
│   │   │   ├── PromptLoader.swift      ← 读取 system_prompt.txt
│   │   │   ├── ImageSupport.swift
│   │   │   ├── AppDelegate.swift
│   │   │   ├── SchoolEventInboxApp.swift
│   │   │   ├── Resources/system_prompt.txt   ← 解析规则（**不要改**）
│   │   │   └── Views/                  ← ContentView / InputPane / EventCard / ...
│   │   └── SchoolEventInboxCore/       ← 模型、解析、Provider、日志、Keychain
│   │       ├── Models/
│   │       │   ├── ParsedEvent.swift
│   │       │   ├── EventDraft.swift
│   │       │   ├── EventType.swift
│   │       │   ├── ManagedEvent.swift   ← 托管事件值类型 + CalendarAccessState
│   │       │   └── InputSource.swift    ← InputSource + InputComposer
│   │       ├── Providers/               ← V2.0 新增目录
│   │       │   ├── TargetProvider.swift
│   │       │   ├── ManagedEventMetadata.swift
│   │       │   ├── AppleCalendarProvider.swift
│   │       │   └── AppleRemindersProvider.swift
│   │       ├── Services/
│   │       │   ├── DeepSeekService.swift
│   │       │   ├── OCRService.swift
│   │       │   ├── KeychainService.swift
│   │       │   └── LogService.swift
│   │       └── Utilities/
│   │           ├── FlexibleDateParser.swift
│   │           └── EnglishBirthdayListParser.swift
│   ├── Tests/SelfTest/SelfTest.swift    ← 129 项自测（无 XCTest，纯可执行）
│   ├── Scripts/
│   │   ├── build_app.sh                ← 构建 + 打包 .app + 签名
│   │   ├── run_selftest.sh             ← 自测
│   │   ├── generate_xcodeproj.py       ← 生成 .xcodeproj（**改文件清单时要同步**）
│   │   └── make_icon.swift
│   ├── SchoolEventInbox.xcodeproj/     ← 生成物；本机没有 xcodebuild
│   ├── AppIcon.icns / AppIcon.iconset/ / icon.png / icon_adjusted.png
│   ├── README.md / TEST_REPORT.md / TODO.md
│   ├── 使用说明.txt / User_Guide.txt        ← 随 Release zip 分发的用户手册
│   └── build/                          ← 自测日志
├── 03_Backup_Archives/
│   ├── MoreCalendar_v1.0_Source_Backup.zip
│   └── SchoolEventInbox_pre_incremental_20261101_1113.zip
└── build/
    └── More calendar.app
```

### 3.1 当前没有的东西

- 没有完整 Xcode（只有 Command Line Tools），**不能用 `xcodebuild`**
- 没有 `01_User_Delivery/`（已在 `chore: remove delivery folder` 中删除，不要再假设它存在）
- 没有后台守护进程或服务器

**注意**：仓库根目录**不应该**出现解压出来的 `More calendar.app`。唯一受跟踪的 App bundle 是 `build/More calendar.app`（且被 gitignore）。若根目录出现 `.app`，那是解压 zip 的残留，不要 `git add`。

---

## 4. 架构：多 Provider（V2.0 核心）

### 4.1 为什么有协议

V1.0 把所有 EventKit 逻辑塞进一个 `CalendarService`，AppModel 直接依赖它。要接提醒事项 / Google Calendar 时，这种写法会迫使每个调用点做 `if 平台 == ...`。

V2.0 的做法：调用方只知道协议，不知道具体平台。**加新平台 = 新增一个文件 + 在 AppModel 注册**，解析链路、卡片、窗口一律不动。

### 4.2 两层协议

`Sources/SchoolEventInboxCore/Providers/TargetProvider.swift`：

```swift
@MainActor
public protocol TargetProvider: AnyObject {
    var providerID: TargetProviderID { get }
    var displayName: String { get }
    var authorizationState: CalendarAccessState { get }
    var targetName: String? { get }              // 默认日历名 / 默认列表名
    var titleLanguage: ManagedCalendarLanguage { get set }
    var routingNotice: String? { get }
    func resetRoutingNotice()
    @discardableResult func requestAccess() async throws -> Bool
    func findConflicts(for draft: EventDraft) throws -> [CalendarConflict]
    func saveEvents(_ drafts: [EventDraft]) throws
    @discardableResult func syncLocalizedTitles(to language: ManagedCalendarLanguage) -> Int
}

@MainActor
public protocol ManagedEventProvider: TargetProvider {
    func fetchManagedEvents() throws -> [ManagedEvent]
    @discardableResult func deleteManagedEvent(id: String) throws -> Int
    func deleteManagedEvents(ids: [String]) throws -> ManagedDeleteResult
    @discardableResult func deleteAllManagedEvents() throws -> Int
    func shiftManagedEvents(ids: [String], by interval: TimeInterval) throws -> ManagedShiftResult
}
```

**为什么拆两层**：写入是共同能力；而「枚举 / 删除 / 批量平移自己写的东西」是**时间轴类目标**才有的能力。提醒事项没有时间区间，做不了平移，所以它**只**遵守 `TargetProvider`，绝不写空实现。UI 据此把「管理事件」置灰。

协议是 `@MainActor` 的，因为 V1.0 就是同步调用 EventKit；保持这个形态才能保证行为不变。需要切队列的 Provider 自己内部处理。

### 4.3 谁遵守什么

| 类型 | 文件 | 遵守 |
|---|---|---|
| `AppleCalendarProvider` | `Providers/AppleCalendarProvider.swift` | `ManagedEventProvider` |
| `AppleRemindersProvider` | `Providers/AppleRemindersProvider.swift` | `TargetProvider`（**仅此**） |
| `GoogleCalendarProvider` | `Providers/Google/GoogleCalendarProvider.swift` | `ManagedEventProvider` |
| `ManagedEventMetadata` | `Providers/ManagedEventMetadata.swift` | 不遵守协议，纯命名/标签工具 |
| 未来的 `GoogleCalendarProvider` | — | 见 §12 |

`AppModel` 持有 `any TargetProvider`，并通过 `target as? any ManagedEventProvider` 取得管理能力：

```swift
var managedEventProvider: (any ManagedEventProvider)? {
    target as? any ManagedEventProvider
}
```

> 这个向下的类型转换失败会导致「管理事件」静默打开一个空面板，所以自测里有专门断言守住它（§10.1）。

### 4.4 `ManagedEventMetadata` 是唯一命名来源

托管标签与按类型命名全部集中在这里，**任何 Provider 都不得自己拼字符串**：

```swift
managedTag        = "[SchoolEventInbox-Managed]"
compatibilityTag  = "[Managed by SchoolEventInbox]"
typeTagPrefix     = "[SchoolEventInbox-Type:"
managedCalendarPrefix = "More Calendar - "
```

提供：`isManagedNotes` / `managedNotes(original:type:)` / `eventType(fromNotes:)` /
`managedCalendarTitle(for:language:)` / `knownCalendarTitles(for:)` /
`managedCalendarBucket(forTitle:)` / `managedCalendarColorToken(for:)`。

它是纯逻辑（无 EventKit / 无 AppKit），因此可在沙箱里单测。

### 4.5 数据流

```text
InputPane ──► AppModel ──► InputComposer.compose() ──► DeepSeekService
                                                          │
                                                          ▼
                                          ParsedEvent ──► DraftFactory ──► EventCard（人工确认）
                                                                              │
                                                                              ▼
                                              AppModel.writeToCalendar()
                                                                              │
                                                          target: any TargetProvider
                                                                              │
                                   ┌──────────────────────────────────────────┴───────────┐
                                   ▼                                                      ▼
                        AppleCalendarProvider                                  AppleRemindersProvider
                        EKEvent / EKCalendar                                    EKReminder / EKCalendar(.reminder)
```

### 4.6 新增一个 Provider 的清单

1. 新建 `Providers/XxxProvider.swift`，遵守 `TargetProvider`（有时间轴才加 `ManagedEventProvider`）。
2. 复用 `ManagedEventMetadata` 的标签与命名，不要自造。
3. 错误只抛 `TargetProviderError`（目标中立文案）。
4. 在 `AppModel` 里加一个实例 + 扩展 `WriteTarget`（含 `providerID`）。
5. 在 `generate_xcodeproj.py` 的 `CORE_PROVIDERS` 列表加文件名（**否则 Xcode 工程缺文件**）。
6. 在 `Tests/SelfTest` 加：协议遵守、纯映射断言。
7. 若需要新的系统权限，同步 `Support/Info.plist` 的用途声明。

---

## 5. 输入源（V2.0 新增）

### 5.1 两种来源

`InputSource`（`Models/InputSource.swift`）：`.email`（邮件 + 截图 OCR）与 `.text`（纯文本）。

| | `.email` | `.text` |
|---|---|---|
| 文本框 | `emailText` | `plainText` |
| 截图区 | 显示 | **隐藏** |
| OCR | 有图就跑 | **永不** |
| 载荷前缀 | `【邮件正文】` + `【图片 N 本地 OCR：…】` | `【纯文本】` |

两个缓冲区互相独立，切换来源不丢内容。

### 5.2 `InputComposer` 是唯一组装点

```swift
compose(source:emailBody:plainText:ocrSections:)  // 返回发给 DeepSeek 的文本
hasInput(source:emailBody:plainText:imageCount:)  // Parse 按钮可用性
logInputType(source:emailBody:imageCount:)        // 日志 inputType
```

**不要**在 `AppModel` 里另写一套字符串拼接。`【…】` 段头是与 `system_prompt.txt` 的隐式契约。

### 5.3 为什么纯文本模式"结构性"跳过 OCR

`compose` 的 `.text` 分支**根本不读** `ocrSections` 参数；`performParse()` 也只在 `inputSource == .email` 时进入 OCR 循环。这是两重保证——不是靠 `if images.isEmpty`，那样后人一次改动就会把 OCR 带回来。

### 5.4 快照与「输入已修改」

解析成功时记录 `parsedInputSnapshot`，内容是 `"<来源>|<该来源文本>"`（**不是**裸 `emailText`）。否则切换来源后会被误判为"未修改"，把旧卡片当成新结果写进日历。

### 5.5 跨启动记忆

```swift
@AppStorage("SchoolEventInbox.writeTarget") private var storedWriteTarget: String
@AppStorage("SchoolEventInbox.inputSource") private var storedInputSource: String
@Published private(set) var writeTarget: WriteTarget
@Published private(set) var inputSource: InputSource
```

- wrapper 负责读写 `UserDefaults`；`@Published` 镜像驱动 SwiftUI（`@AppStorage` 在 `ObservableObject` 里**不会**自动发 `objectWillChange`）。
- `init` 中**先恢复选择，再读权限状态**，否则启动瞬间页脚显示错的目标。
- 与 `LanguageManager` 用同一套模式，不要改成两套。

---

## 6. UI 布局结构

### 6.1 顶层窗口

```text
WindowGroup("More calendar")
└── ContentView
    └── VStack(spacing: 0)
        ├── HStack: InputPane（min 430 / ideal 450 / max 520）│ Divider │ EventListPane（min 580）
        ├── Divider
        └── FooterBar
```

`.defaultSize(width: 1220, height: 820)`，`.frame(minWidth: 1080, minHeight: 700)`。

### 6.2 顶部工具栏（`Views/ContentView.swift`）

1. API Key（`key` / `key.fill`）
2. 刷新日历权限（`calendar.badge.clock`）
3. 管理事件（`L10n.t`，**切到提醒事项时置灰**）
4. 中 / EN 切换（同时把按类型日历/列表改成对应语言）

### 6.3 左侧输入面板（`Views/InputPane.swift`）

```text
输入                                      [空闲 / OCR 中 / 解析中]
[ 邮件 / 截图 ] [ 纯文本 ]        ← 分段控件（InputSource）
说明文字（随来源变化）
┌ 邮件正文 / 纯文本  TextEditor  字数 ┐
└──────────────────────────────┘
图片截图（仅 .email 模式可见）
[Keychain 状态]                        [解析 ⌘↩]
```

- 切换来源时 TextEditor 带 `.id(inputSource)` 强制重建，避免残留上一来源的内容与撤销栈。
- `⌘↩` 是 Parse 按钮上的 `.keyboardShortcut`，窗口级生效，与焦点无关。

### 6.4 右侧待确认列表

`Views/EventListPane.swift` + `Views/EventCard.swift`。卡片自上而下：类型菜单 → 标题 → 起止时间 → 全天开关 → 地点 → 原文依据 → 歧义说明 → 置信度 → 冲突提示 → 确认勾选 → 生日提示条。

详情见 §7.1（全天）与 §8.3（冲突）。

### 6.5 底部状态栏（`Views/FooterBar.swift`）

- 左：写入结果 / 下一步提示 + 默认日历或列表名 + 近 14 天统计
- 右：清空日志 · 导出最近 30 条 · **写入目标分段选择器（日历 / 提醒事项）** · **写入按钮**

写入按钮的标题、图标、提示、权限文案全部随 `writeTarget` 变化：

| 目标 | 按钮 | 提示 |
|---|---|---|
| 日历 | 写入 Apple 日历 | 按类型写入独立日历，失败回退默认日历 |
| 提醒事项 | 写入 Apple 提醒事项 | 按类型写入独立列表，到期时间取开始时间 |

### 6.6 管理事件面板（`Views/ManagedEventsView.swift`）

固定 `760 × 620`。入口两个：工具栏「管理事件」、菜单 `School Event` → `⌘⇧M`。

面板依赖 `any ManagedEventProvider`。**切到提醒事项时两个入口都禁用**，因为提醒事项不满足该协议。

---

## 7. 解析链路

```text
InputPane（邮件 / 截图 / 纯文本）
  ↓
AppModel.parse()  → inputSource 快照（workStatus 起点）
  ↓
OCRService（**仅 .email 且有图**）
  ↓
InputComposer.compose()
  ↓
DeepSeekService
  ├── PromptLoader 读取 system_prompt.txt
  ├── OpenAI-compatible API
  ├── JSON 解码
  ├── EnglishBirthdayListParser（英文名单确定性兜底）
  └── ParsedEventSanitizer
  ↓
ParsedEvent → DraftFactory.makeDraft(s)（FlexibleDateParser + 全天归一化 + 校验）
  ↓
EventCard（人工确认）
  ↓
AppModel.writeToCalendar()
  ├── target.findConflicts(for:)  → 冲突卡片
  └── target.saveEvents([draft])  → Apple 日历 / 提醒事项
```

### 7.1 全天的三层保证

1. **UI**：`EventCard.swift` 的 `.date` 分支
2. **Draft**：`EventDraft.calendarInterval` 全天用 `startOfDay`，结束为次日 00:00
3. **写入**：`AppleCalendarProvider.save` 的 `event.isAllDay = isBirthday ? true : draft.allDay`

生日额外：`startDate` 归零到当天、`endDate` = 次日、`recurrenceRules` 每年一次。

**提醒事项不同**：没有全天概念，只写 `dueDateComponents` 的 `[.year,.month,.day]`，不带时分。

### 7.2 7 条英文生日名单

已能解析且已验证。输入形如：

```text
December 8 - Hayeon
January 22 - Olena
```

真实调用日志 `eventCount=7`，types 全为 `birthday`。约束：

- fallback **只在 DeepSeek HTTP 成功返回后**触发；API 失败仍报解析错误，不会静默生成本地事件。
- 只匹配"整段输入都是 `Month Day - Name`"；混合邮件仍靠 prompt + 模型。
- 缺年份默认今年，`notes` 写「缺年份，默认今年」。

### 7.3 日志

`LogRecord.inputType` 取值：`email` / `image` / `text`。

- 混合（正文+截图）仍记 `email`，`imageCount` 记录图片数。
- **schema 不要随意加字段**；V2.0 只新增了 `text` 这个取值。
- 导出前有二次脱敏；日志含本机路径，不要提交。

---

## 8. 两个 Provider 的实现细节

### 8.1 `AppleCalendarProvider`

**按类型分日历**（`calendarForWriting(_:)`）：

| 类型 | 日历标题 | 颜色 |
|---|---|---|
| deadline | `More Calendar - 截止` | orange |
| appointment | `More Calendar - 预约` | blue |
| exam | `More Calendar - 考试` | red |
| birthday | `More Calendar - 生日` | purple |
| activity / other | `More Calendar - 活动` | green |

要点（都是踩过的坑）：

- **EventKit 没有 `EKCalendarColor`**。只有 `EKCalendar.color: NSColor` 与 `.CGColor`，所以映射做成 `ManagedCalendarColorToken` + `nsColor`。别再找 `EKCalendarColor`。
- **activity 与 other 合并一个桶**（`EventType.managedCalendarBucket`），否则两个同色日历反而更乱。
- **`More Calendar - ` 前缀是唯一识别标记**：`EKCalendar` 没有 notes 字段，只能靠标题前缀跨启动匹配。
- 创建源优先：默认日历所在账户 → 本地账户 → CalDAV；`.subscribed` / `.birthdays` 永不使用。
- 创建失败**不报错**，回退 `defaultCalendarForNewEvents`，通过 `routingNotice` 在底部提示「已回退到默认日历」。
- 同批次连续写同类型时用 `routedCalendarIDs` 缓存 identifier，避免 `calendars(for:)` 未刷新导致重复建日历。
- 切换语言时 `syncLocalizedTitles` 会改名；需要完整访问，没权限则静默跳过。

### 8.2 `AppleRemindersProvider`

- 用 `EKEventStore` 的 `.reminder` 实体：`calendars(for: .reminder)`、`defaultCalendarForNewReminders()`、`saveCalendar`。
- 列表命名/颜色/标签与日历**完全相同**（复用 `ManagedEventMetadata`），所以 `More Calendar - 考试` 可能同时存在于日历与提醒事项中——两者命名空间独立，是预期行为。
- 写入 `EKReminder`：`title`、`notes`（含托管标签）、`dueDateComponents`、`isCompleted = false`。
- **到期时间取 `EventDraft.calendarInterval().start`**：全天/生日只写 `[.year,.month,.day]`（否则会 00:00 触发）；生日加每年重复的 `EKRecurrenceRule`。
- **`findConflicts` 返回 `[]`**：提醒事项不占时间槽，没有冲突可查。返回空数组而不是抛错，是为了让 `AppModel` 的写循环保持目标无关。
- **不实现 `ManagedEventProvider`**，因此没有删除/平移入口。
- 权限实体是 `.reminder`，`Info.plist` 必须同时有：
  - `NSRemindersFullAccessUsageDescription`
  - `NSRemindersUsageDescription`

### 8.3 冲突检测与写入循环

- `findConflicts` 用 `predicateForEvents` 取区间内所有日历的事件，按 `ConflictDetector.overlaps` 判重叠，排除已取消。
- **写循环留在 `AppModel`**，逐条调用 `saveEvents([draft])`。这样"冲突跳过 / 失败原因 / isWritten 标记"的计数与文案保持逐卡片粒度。
  - `saveEvents` 收数组是给未来批量目标（如 Google）留的扩展点，**不要**为了"更彻底"把循环搬进 Provider——那会改变 UI 输出的时序。

### 8.4 管理面板语义（仅日历）

托管标签（写入时两个都写）：

```text
[SchoolEventInbox-Managed]
[Managed by SchoolEventInbox]
[SchoolEventInbox-Type:birthday]
```

- 过滤条件：备注包含任一托管标签。旧版本写过但无标签的事件**不会**出现（保守设计，不要放宽）。
- 时间范围：过去 1 个月 ~ 未来 1 年。
- 删除三入口，语义不同，别混淆：

| 入口 | 范围 | 二次确认 |
|---|---|---|
| 行内垃圾桶 | 单条 | 循环事件才确认 |
| 底部「删除选中」 | **仅勾选** | 是，文案含数量 |
| 底部「清空所有」 | 全部带标签事件 | 是（已弱化为次要文字按钮） |

- 循环事件删除用 `.futureEvents`；单条保存用 `.thisEvent`。
- 批量平移：保持原时长；全天按整天平移；循环事件拒绝；冲突跳过并汇总。
- **冲突要能说出"谁撞了谁"**：`ManagedShiftResult.conflictDetails` 带 `shiftedTitle` / `blockingTitle` / 两侧时间，视图弹出详情 sheet。不要退回"只返回计数"的实现——静默失败是修过的显式缺陷。

---

## 9. 编译、测试、打包

### 9.1 环境

- macOS（Apple Silicon）、Command Line Tools，**没有完整 Xcode**
- Swift 6.4；**必须显式指定 SDK `MacOSX26.5.sdk`**，否则默认 SDK 27.0 与编译器版本不匹配会失败
- 没有 `timeout` 命令（macOS 自带）；脚本里不要用

### 9.2 构建 App

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox_V2.0/02_Developer_Source"
./Scripts/build_app.sh
```

输出 `../build/More calendar.app`。脚本会：选 SDK → `swift build --disable-sandbox` → 复制可执行文件/Info.plist/资源 bundle/en.lproj → 若有 `AppIcon.icns` 则带上 → ad-hoc 稳定签名。

### 9.3 直接 SwiftPM

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox_V2.0/02_Developer_Source"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
CLANG_MODULE_CACHE_PATH="$PWD/.build/clangcache" \
swift build --disable-sandbox --sdk "$SDK" \
  --cache-path "$PWD/.build/cache" \
  --scratch-path "$PWD/.build/scratch" \
  --manifest-cache local
```

> 目录改名后若报 `module cache path ... but the path is currently ...`，是 `.build` 里残留了旧路径的缓存：`rm -rf .build` 后重跑即可。

### 9.4 自测

```bash
./Scripts/run_selftest.sh
# RESULT: 200 passed, 0 failed
```

- 测试是**无依赖可执行程序**（本机无 XCTest），不是 XCTest。
- Keychain 用例在命令沙箱里会 SKIP（`OSStatus 100001`），属预期。
- 自测会写 `02_Developer_Source/build/selftest.log`（gitignore）。

### 9.5 Xcode 工程

```bash
python3 Scripts/generate_xcodeproj.py
plutil -lint SchoolEventInbox.xcodeproj/project.pbxproj
```

**新增/删除源文件时必须同步脚本里的文件清单**（`CORE_MODELS` / `CORE_PROVIDERS` / …），否则工程缺文件。本机无 `xcodebuild`，**不要声称 Xcode 构建通过**。

### 9.6 打包交付 zip

```bash
cd "/Users/duishangque/Desktop/编程/SchoolEventInbox_V2.0"
rm -f "MoreCalendar_v2.0.0_macOS.zip"
ditto -c -k --norsrc --noextattr --keepParent \
  "build/More calendar.app" \
  "MoreCalendar_v2.0.0_macOS.zip"
```

### 9.7 发布前验证

```bash
APP="build/More calendar.app"
unzip -t "MoreCalendar_v2.0.0_macOS.zip"
unzip -l "MoreCalendar_v2.0.0_macOS.zip" | head -6     # 顶层必须是 "More calendar.app/"
codesign --verify --deep --strict --verbose=2 "$APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"   # 2.0.0
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"              # 2
/usr/libexec/PlistBuddy -c 'Print :NSRemindersFullAccessUsageDescription' "$APP/Contents/Info.plist"
```

冒烟：把 zip 解压到 **`/tmp` 下的新目录**再启动（不要在仓库里解压）。

### 9.8 发布前清理

```bash
rm -rf 02_Developer_Source/.build 02_Developer_Source/build
find . -name '.DS_Store' -delete
find 02_Developer_Source -name 'xcuserdata' -type d -prune -exec rm -rf {} +
```

---

## 10. 已验证 / 未验证

### 10.1 已验证

- 干净构建 0 warning；129 项自测通过
- `@AppStorage` 记忆：写入 `text` / `reminders` 两个 key 后重启，UI 正确恢复且页脚显示**提醒事项专属**权限提示
- 纯文本模式不产生 OCR 段（`InputComposer` 断言 + 实机截图：图片区隐藏）
- 协议边界：`AppleCalendarProvider` 可取得 `ManagedEventProvider`；`AppleRemindersProvider` **不可**
- v2.0.0 zip：完整性、签名、版本、解压即启动
- **用户本人在真实 Mac 上完成端到端验收**：
  - 提醒事项写入（含列表创建与到期时间）
  - 写入目标切换与「管理事件」自动置灰
  - v1.0 的写入 / 删除 / 批量平移 / 全天 / 双语

### 10.2 未验证 / 需要留意

1. **`⌘↩` 在文本框内触发**：本机辅助功能权限被拒（`System Events` privilege violation），无法注入按键，只能确认"机制未变"（按钮级 `.keyboardShortcut`）。
2. **Xcode 工程**：仅通过 `plutil -lint`，没有 `xcodebuild` 编译。
3. **release 优化构建**：交付包是 debug 配置（用户已接受）。
4. **Keychain**：CLI 沙箱不可测，只在 App 内验证。
5. **提醒事项的结束时间**：不写入（平台无此概念），只保留开始时间作为到期。
6. **英文生日 fallback 边界**：见 §7.2。
7. **时区**：prompt 对纯日期要求 `+08:00`；非中国时区 / 跨日边界需额外验证。

---

## 11. 安全与不可破坏的约束

1. **不要重写整个项目**，也不要在重构中顺手改解析规则。
2. **不要改 DeepSeek 请求结构、模型名、JSON 核心字段、`system_prompt.txt`**，除非用户明确要求。
3. **不要删除或重命名托管标签**（`[SchoolEventInbox-Managed]` / `[Managed by SchoolEventInbox]`）。真实事件里写的就是这两个字符串；改名等于丢掉所有历史事件。
4. **不要改 `More Calendar - ` 前缀**（日历/提醒事项靠它跨启动识别）。
5. **不要把 `import EventKit` 扩散到 `Providers/` 之外**。V1.0 的教训就是 EventKit 渗透进调用方。
6. **不要给 `AppleRemindersProvider` 补 `ManagedEventProvider` 的空实现**。协议的拆分就是为了拒绝这种"看起来完整"的假能力。
7. **不要读取 / 打印用户 API Key**；不要 `git add` 任何密钥。
8. **不要未经用户确认写入或删除真实日历 / 提醒事项事件**；自动化测试不得建真实日历。
9. **不要改 bundle id 与稳定签名**（Keychain 与 UserDefaults 都绑在它上面）。
10. **不要用 `rm -rf` 清理未确认的路径**；先 `realpath` 检查。
11. **图标必须满铺 1024**：macOS 26 会把未铺满的图标判为旧式并垫灰底板。处理脚本 `Scripts/make_icon.swift`；旧图标备份在 `03_Backup_Archives/`。
12. **`AppIcon_canvas.png` / `processed_icon.png` 已被用户删除，不要恢复。**
13. **日志 schema 只加不改**；新增字段要考虑旧日志解析（`decodeIfPresent`）。

---

## 12. Google Calendar 接入（已实现）

> 以下是最终落地的形态。与最初计划的差异：协议已改为 async、采用「单日历 + colorId」、
> 用系统浏览器而非 ASWebAuthenticationSession；原因都写在对应小节里。

### 12.1 必须先解决的外部问题

| 问题 | 说明 |
|---|---|
| **OAuth 2.0** | Google 需要用户授权。建议 **installed app + PKCE + loopback**（`ASWebAuthenticationSession` 或本地 `127.0.0.1` 回调）。这是本项目第一次引入 OAuth——文档开头"不做 OAuth"的说明需要同步更新。 |
| **凭证存储** | `client_id` / `refresh_token` 走 Keychain（复用 `KeychainService` 的模式，**不要**复用同一个 key，另开条目）。 |
| **网络层** | 新写 `GoogleCalendarService`（或在 Provider 内），**不要**改 `DeepSeekService`。需要一个可注入的 `URLSession` 以便自测打桩（参考 `SelfTest` 里 DeepSeek 的网络桩）。 |
| **失败语义** | 所有网络/限流/授权过期都转成 `TargetProviderError`（`.accessDenied` / `.saveFailed`），不要新造错误类型让 UI 分支扩散。 |

### 12.2 模型映射

| 本项目 | Google Calendar `events` 字段 |
|---|---|
| `draft.title` | `summary` |
| `draft.notes` + 托管标签 | `description`（Google 没有独立 notes；**标签必须写进 description**，管理过滤才有依据） |
| `draft.location` | `location` |
| 定时事件 | `start.dateTime` / `end.dateTime` + `timeZone` |
| 全天事件 | `start.date` / `end.date`（`date` 是**排他**的次日，注意与 `EventDraft.calendarInterval` 的语义对齐） |
| 生日 | `recurrence: ["RRULE:FREQ=YEARLY"]` |
| 按类型分日历 | 先 `calendars.insert` 建 secondary calendar，`summary` 复用 `ManagedEventMetadata.managedCalendarTitle`（前缀 `More Calendar - `），再按类型路由 |
| 托管事件 ID | Google `event.id` 不透明，`ManagedEvent.id` 建议存 `calendarId + "/" + eventId` |
| 冲突检测 | `freebusy` 或 `events.list`（`timeMin`/`timeMax`），换算成 `CalendarConflict` |

### 12.3 协议适配决策

- `TargetProvider`：**必须**实现（`saveEvents` → `events.insert`）。
- `findConflicts`：**可以实现**（Google 能查时间），实现后冲突卡片对 Google 也生效。
- `ManagedEventProvider`：**可以实现**（`events.list` 按 `description` 标签过滤 / `events.delete` / `patch` 平移）。若暂不做，就不要加空实现，UI 会自动置灰——这与提醒事项的处理保持一致。
- `syncLocalizedTitles`：Google 日历也能改名，按需实现；未授权时返回 0。
- `titleLanguage`：Google 侧同样需要，才能在创建 secondary calendar 时用对语言。

### 12.4 UI 需要的最小改动

1. `WriteTarget` 加 `.googleCalendar` + `providerID`。
2. 底部选择器从 2 项变 3 项（`ForEach(WriteTarget.allCases)` 已就绪，**布局需要重新看宽度**）。
3. `calendarPermissionPrompt` 加 Google 的未授权分支（"需要连接 Google 账户"），并提供一个入口调用 `requestAccess()`。
4. 页脚提示文案加第三分支。

**不要**新增独立的设置窗口或账号管理页，除非用户明确要求。

### 12.5 建议落地顺序

1. `KeychainService` 增加 Google token 条目 + `GoogleOAuthClient`（含 PKCE、刷新）。
2. `GoogleCalendarProvider: TargetProvider`，先只做 `saveEvents`（单条写入、默认 calendar）。
3. `findConflicts` + `CalendarConflict` 映射。
4. 按类型建/找 secondary calendar（复用 `ManagedEventMetadata`，注意 Google 的 `summary` 唯一性）。
5. 视情况实现 `ManagedEventProvider`。
6. 自测：协议遵守 + 纯映射（标题/颜色/载荷）+ 网络桩（4xx/5xx/限流）。
7. 真机验收由用户完成（会真的写进他的 Google 账户）。

### 12.6 不能破坏的东西

- 已有的两个 Provider 行为与文案。
- `ManagedEventMetadata` 的标签格式（Google 的 description 里也要写同样的字符串）。
- `InputComposer` / 解析链路：Google 只影响写入侧。
- 自测数量只增不减；`generate_xcodeproj.py` 的文件清单要同步。

### 12.7 已实现的形态与已知限制

**已实现**（用户真机验收通过：写入成功、颜色正确、落在选定日历）：

- `GoogleOAuthManager`：PKCE(S256) + loopback 随机端口 + 系统浏览器；refresh_token 存 Keychain
- `GoogleAPIClient`：401 自动刷新一次、限流不静默重试、分页
- `GoogleCalendarProvider`：单日历 + colorId 分色；托管标记双写 description 与 extendedProperties
- 循环事件删除按系列（先 GET 查 `recurringEventId`，再删父事件）

**踩过的坑，不要重犯**：

1. **路径不能二次编码**。`appendingPathComponent` 会把 `%40` 变成 `%2540`，
   日历 id 形如 `name@gmail.com` 时必然 404。必须用 `percentEncodedPath` 精确编码一次。
2. **redirect_uri 不要加路径**。注册值是 `http://localhost`，官方 loopback 示例也不带路径。
3. **「未连接」不等于「系统权限被拒」**。Google 的 401/notAuthorized 必须映射成
   `authorizationRequired`，否则会把用户引去改系统设置。
4. **冲突预检不得阻断写入**。它是提示性能力，失败时按「无冲突」继续。
5. **时区是日历时区问题**。载荷发的是 `14:00+08:00`，网页按日历时区渲染；
   若用户日历时区是美东，会显示 01:00——不是数据错误。

**尚未做的**：

- Google 侧批量平移不做冲突预检（`conflicts` 恒为 0）
- 只支持单个 Google 账号
- Google 的 `deleteManagedEvents` 会逐条 GET 解析系列，条目多时较慢

---

## 13. 新工程师建议阅读顺序

1. `README.md` — 产品与能力边界
2. 本文件 §0、§4、§5
3. `Providers/TargetProvider.swift` — 协议契约（最重要）
4. `Providers/ManagedEventMetadata.swift` — 命名与标签的唯一来源
5. `Providers/AppleCalendarProvider.swift` — 完整参考实现
6. `Providers/AppleRemindersProvider.swift` — 第二个目标的取舍示例
7. `Models/InputSource.swift` — 输入组装
8. `AppModel.swift` — UI 状态与写循环
9. `Views/InputPane.swift` / `Views/FooterBar.swift` — 两个选择器
10. `Services/DeepSeekService.swift` — 解析入口（**只读，不要改**）

---

## 14. 产物一览

```text
App:
  /Users/duishangque/Desktop/编程/SchoolEventInbox_V2.0/build/More calendar.app

源码:
  /Users/duishangque/Desktop/编程/SchoolEventInbox_V2.0/02_Developer_Source

发布包（构建产物，不入库）:
  MoreCalendar_v2.0.0_macOS.zip  → 通过 GitHub Release 分发

Release 文案:
  RELEASE_NOTES_v2.0.0.md

源码备份:
  03_Backup_Archives/MoreCalendar_v1.0_Source_Backup.zip（v1 时期）
```

---

**一句话交接：**

> 版本 **2.0.0**。写入侧已抽象为 `TargetProvider`（管理能力另拆 `ManagedEventProvider`），现有三个实现：`AppleCalendarProvider`、`AppleRemindersProvider`、`GoogleCalendarProvider`；EventKit 不得离开 `Providers/`，网络只在 `Providers/Google/`。输入侧新增纯文本来源，组装逻辑集中在 `InputComposer`，纯文本模式结构性跳过 OCR。托管标签与 `More Calendar - ` 前缀是历史数据的唯一锚点，任何情况下都不要改。129 项自测全绿，用户已完成真机端到端验收。下一个目标是 Google Calendar：照着 §12 的映射与顺序做，不要碰解析链路。
