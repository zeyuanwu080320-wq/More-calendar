# More calendar

**本地优先的 macOS 学校日程收件箱 · A local-first school schedule inbox for macOS**

[中文](#中文) · [English](#english)

> 把邮件正文或截图丢进来，本机 OCR + DeepSeek 抽取成结构化事件，逐条核对后再写入 Apple 日历。
> Paste an email or a screenshot; local OCR + DeepSeek turn it into structured events that you review before anything touches Apple Calendar.

<!-- 截图占位：请替换为实际截图 / Screenshot placeholders -->
<!-- ![主界面 / Main window](docs/screenshots/main-window.png) -->
<!-- ![事件卡片 / Event cards](docs/screenshots/event-cards.png) -->
<!-- ![管理面板 / Managed events](docs/screenshots/managed-events.png) -->

---

## 中文

### 这是什么

每天从学校邮件、通知截图里抄日程，再手动敲进日历，是一件又慢又容易漏的事。**More calendar** 把这个流程压缩成三步：

1. **粘贴** —— 邮件正文或任意纯文本直接粘贴，截图/海报也可以拖进来、`⌘V` 贴进来。
2. **核对** —— 本机 OCR 出文字，DeepSeek 抽出候选事件，你在卡片上逐条改类型、时间、地点、全天。
3. **写入** —— 你点了"写入 Apple 日历"或"写入 Apple 提醒事项"，事件才会落地。**不会自动写入，不会后台监听邮箱。**

图片永远不出本机：OCR 走 macOS 自带的 Vision 框架，只有**文字**会发给 DeepSeek。纯文本模式完全不经过 OCR。

### 核心功能

| 能力 | 说明 |
|---|---|
| **本地 OCR** | 截图在内存里用 Vision 识别，图片不上传、不落盘 |
| **智能抽取** | DeepSeek 按固定 JSON 结构抽出标题、类型、起止时间、地点、原文依据 |
| **纯文本输入** | 「纯文本」模式跳过 OCR，直接把文字发给 DeepSeek |
| **标签分类** | 事件类型：截止 / 预约 / 考试 / 生日 / 活动 / 其他 |
| **按类型分日历** | 每种类型写入独立的 Apple 日历，**颜色一眼可辨**：考试=红、生日=紫、截止=橙、预约=蓝、活动=绿 |
| **按类型分提醒事项** | 同为每种类型建独立列表；到期时间取开始时间，全天/生日只写日期并每年重复 |
| **两种落点** | 一键在 Apple 日历与 Apple 提醒事项之间切换写入目标 |
| **冲突检测** | 写入前检查时间重叠，默认跳过；也可在卡片上勾选"冲突仍写入" |
| **全天与生日** | 全天事件只显示日期；生日强制全天并设为**每年重复** |
| **批量平移** | 勾选多条统一 `+1 小时 / -1 小时 / +1 天 / -1 天 / +1 周` 或自定义分钟数，冲突会逐条告诉你**是谁撞了谁** |
| **批量删除** | 「删除选中」只删勾选的；「清空所有」才是全删，且已降级为次要按钮 |
| **双语界面** | 中 / EN 一键切换，连 Apple 日历的分类名也跟着改 |
| **记住选择** | 输入来源与写入目标跨启动保留 |
| **托管标识** | 写入的事件带专属标签，管理面板只显示本工具创建的事件，不碰你的私人日程 |
| **密钥安全** | API Key 只存 macOS Keychain，不写代码、不写日志、界面不回显 |
| **日志脱敏** | 只记计数与类型；导出前再做一次脱敏，不含正文、标题、地点、邮箱、学号 |

### 环境要求

- **Apple Silicon（arm64）** Mac —— 交付的二进制只编译了 arm64
- **macOS 15 (Sequoia) 或更高**
- 一个 **DeepSeek API Key**（自备，按量计费）
- **完整日历访问权限**（不是"仅写入"——本工具需要在写入前读取同时间段的事件来判断冲突）
- 选择写入提醒事项时，还需要 **完整提醒事项访问权限**
- 编译需要 **Command Line Tools**（Swift 6.x）；**不需要完整 Xcode**

### 准备工作（两步，缺一不可）

**1. 配置 API Key**

1. 打开 App，点右上角的钥匙图标
2. 粘贴你的 DeepSeek API Key（不是学校账号密码）
3. 点"保存到 Keychain"
4. 若系统弹出授权提示，选 **Always Allow / 始终允许**；读不到就重新保存一次

**2. 授予完整日历权限**

1. 第一次点"写入 Apple 日历"时，macOS 会请求日历权限
2. 必须选 **完整访问权限**，不能选"仅写入"
3. 选错了：到 `系统设置 → 隐私与安全性 → 日历` 改为完整访问，或点 App 底部"升级为完整访问"

### 编译

```bash
cd 02_Developer_Source
./Scripts/build_app.sh          # 构建 + 稳定 ad-hoc 签名
```

产物：`build/More calendar.app`

脚本会自动选择本机 SDK（优先 `MacOSX26.5.sdk`，找不到则用 `xcrun --sdk macosx`），
用固定 identifier `local.duishangque.SchoolEventInbox` 做 ad-hoc 签名——
这样重建后 Keychain 里的 API Key 依然可读。

跑自测（105 项，纯命令行，不写真实日历）：

```bash
cd 02_Developer_Source
./Scripts/run_selftest.sh       # 期望：105 passed, 0 failed
```

直接运行：

```bash
./Scripts/build_app.sh --run
```

### 目录结构

```text
.
├── 01_User_Delivery/          # 交付物：App 压缩包 + 中英文说明书
├── 02_Developer_Source/       # 源码（SwiftPM）
│   ├── Sources/SchoolEventInbox/       # UI 层（SwiftUI）
│   ├── Sources/SchoolEventInboxCore/   # 模型 / 解析 / 日历 / 日志 / Keychain
│   ├── Tests/SelfTest/                 # 105 项自测
│   └── Scripts/                        # 构建、自测、图标、Xcode 工程生成
├── 03_Backup_Archives/        # 本地备份（已在 .gitignore 中忽略）
├── build/                     # 构建产物（已忽略）
├── LICENSE
└── README.md
```

### 隐私与边界

- 只把**邮件正文和 OCR 文本**发给 DeepSeek；图片二进制不发
- 不后台监听邮箱、不云同步、无账号体系；Google Calendar 接入使用 OAuth，其凭据的**运行时真实路径**是 `~/Library/Application Support/More calendar/google_client_secret.json`——仓库里 `02_Developer_Source/Support/` 的那份**仅作版本备份**，不会被 `build_app.sh` 打进 `.app`
- 不是官方工具，不保证"绝不漏事件"——请逐条核对后再写入
- `Clear all` 只删带托管标签的事件；删除日历分类需在 Apple 日历里手动操作

### 许可

[MIT](LICENSE) © 2026 zeyuanwu080320-wq

---

## English

### What it is

Copying school schedules out of emails and screenshots into a calendar is slow and error-prone.
**More calendar** compresses it into three steps:

1. **Paste** — paste an email body or any plain text, or drop / `⌘V` a screenshot.
2. **Review** — local Vision OCR extracts the text, DeepSeek proposes structured events, and you fix type, time, place and all-day flag on each card.
3. **Write** — nothing lands until you press *Write to Apple Calendar* or *Write to Apple Reminders*. No auto-write, no background mailbox polling.

Images never leave the machine: OCR runs on Apple's Vision framework, and only **text** is sent to DeepSeek. Plain Text mode skips OCR entirely.

### Highlights

| Capability | Detail |
|---|---|
| **Local OCR** | Screenshots are OCR'd in memory; nothing is uploaded or persisted |
| **Structured extraction** | DeepSeek returns a fixed JSON schema: title, type, start/end, location, evidence |
| **Plain-text input** | Plain Text mode skips OCR and sends the text straight to DeepSeek |
| **Typed events** | deadline / appointment / exam / birthday / activity / other |
| **Per-type calendars** | Each type lands in its own Apple Calendar, **colour-coded**: exam = red, birthday = purple, deadline = orange, appointment = blue, activity = green |
| **Per-type reminder lists** | The same split for Apple Reminders; the due date is the start time, all-day/birthdays use a date-only due date and repeat yearly |
| **Two destinations** | Switch the write target between Apple Calendar and Apple Reminders in one click |
| **Conflict detection** | Checks overlaps before writing; skipped by default, with an opt-in "write anyway" per card |
| **All-day & birthdays** | All-day events show date-only pickers; birthdays are all-day and repeat yearly |
| **Batch shift** | Move several events by ±1h / ±1d / +1w or a custom offset, and see **exactly which event collided with which** |
| **Batch delete** | *Delete Selected* removes only checked events; *Clear all* (the blunt instrument) is demoted to a secondary action |
| **Bilingual UI** | One-click 中 / EN toggle — even the Apple Calendar category names follow the language |
| **Remembered choices** | Input source and write destination persist across launches |
| **Managed tags** | Written events carry an ownership tag, so the panel only ever shows events this app created |
| **Keychain only** | The API key lives in the macOS Keychain; never in code, logs, or the UI |
| **Redacted logs** | Counts and types only; a second redaction pass runs on export |

### Requirements

- **Apple Silicon (arm64)** Mac — the shipped binary is arm64-only
- **macOS 15 (Sequoia)** or newer
- A **DeepSeek API key** (bring your own, pay-per-use)
- **Full Calendar access** (not "Write Only" — conflicts can only be detected by reading existing events)
- **Full Reminders access** when writing to Apple Reminders
- **Command Line Tools** with Swift 6.x to build; full Xcode is **not** required

### Setup (both steps required)

**1. API key**

1. Click the key icon in the top-right
2. Paste your DeepSeek API key
3. Click *Save to Keychain*
4. Choose **Always Allow** if macOS prompts; if it still cannot read the key, save it again

**2. Full Calendar access**

1. The first time you press *Write to Apple Calendar*, macOS asks for permission
2. Choose **Full Access**, never "Write Only"
3. Picked the wrong one? Go to `System Settings → Privacy & Security → Calendars`, or use the app's *Upgrade to Full Access* button

### Build

```bash
cd 02_Developer_Source
./Scripts/build_app.sh          # build + stable ad-hoc signature
```

Output: `build/More calendar.app`

The script picks an available SDK (prefers `MacOSX26.5.sdk`, falls back to `xcrun --sdk macosx`)
and signs with the fixed identifier `local.duishangque.SchoolEventInbox`, so the
Keychain-stored API key survives rebuilds.

Run the self-test suite (105 checks, CLI-only, never touches a real calendar):

```bash
cd 02_Developer_Source
./Scripts/run_selftest.sh       # expect: 105 passed, 0 failed
```

Build and launch:

```bash
./Scripts/build_app.sh --run
```

### Layout

```text
.
├── 01_User_Delivery/          # App archive + Chinese/English guides
├── 02_Developer_Source/       # Source (SwiftPM)
│   ├── Sources/SchoolEventInbox/       # SwiftUI layer
│   ├── Sources/SchoolEventInboxCore/   # models / parsing / calendar / logs / Keychain
│   ├── Tests/SelfTest/                 # 105 self-tests
│   └── Scripts/                        # build, self-test, icon, Xcode project generator
├── 03_Backup_Archives/        # local backups (git-ignored)
├── build/                     # build output (git-ignored)
├── LICENSE
└── README.md
```

### Privacy and scope

- Only the **email body and OCR text** are sent to DeepSeek; image bytes never are
- No mailbox monitoring, no cloud sync, no accounts; the Google Calendar integration uses OAuth, and its credential is read at runtime from `~/Library/Application Support/More calendar/google_client_secret.json` — the copy under `02_Developer_Source/Support/` is a **version backup only** and is never bundled into the `.app`
- Not an official tool and no guarantee that nothing is missed — review each card
- *Clear all* only removes tagged events; deleting calendar categories is manual, in Apple Calendar

### License

[MIT](LICENSE) © 2026 zeyuanwu080320-wq
