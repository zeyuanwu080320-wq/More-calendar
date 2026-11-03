# More calendar v2.0.0

发布日期：2026-11-03 · 构建号 `2` · 平台 macOS 15+ (arm64)

V1.0 只面向 Apple 日历，所有 EventKit 逻辑都绑在一个 `CalendarService` 里。V2.0 把写入侧
抽象成 `TargetProvider` 协议，并在这个地基上新增了两个能力：**写入 Apple 提醒事项** 与
**纯文本输入**。原有 Apple 日历流程的行为、文案与视觉效果保持不变。

## 亮点

- **多目标写入**：底部一键在「Apple 日历」与「Apple 提醒事项」之间切换写入目标。
- **Apple 提醒事项**：与日历同样按事件类型分列表，沿用同一套托管标签；到期时间取开始时间，
  全天与生日只写日期，生日保留每年重复。
- **纯文本输入**：左侧新增「邮件 / 截图 ↔ 纯文本」切换。纯文本模式从结构上不经过 OCR，
  也不会读取已缓存的截图。
- **选择会被记住**：输入来源与写入目标跨启动保留。
- **架构**：新增 `TargetProvider` / `ManagedEventProvider` 两层协议，EventKit 仅存在于
  `AppleCalendarProvider` 与 `AppleRemindersProvider` 两个文件内。

## 变更明细

| 类别 | 内容 |
|---|---|
| 新增 | `Providers/TargetProvider.swift`（协议 + `TargetProviderID` + `TargetProviderError`） |
| 新增 | `Providers/ManagedEventMetadata.swift`（托管标签与按类型命名，纯逻辑、可单测） |
| 新增 | `Providers/AppleCalendarProvider.swift`（V1 全部 EventKit 逻辑迁移至此） |
| 新增 | `Providers/AppleRemindersProvider.swift`（提醒事项目标） |
| 新增 | `Models/ManagedEvent.swift`、`Models/InputSource.swift`（`InputComposer` 载荷组装） |
| 删除 | `Services/CalendarService.swift` |
| 修改 | `AppModel` 改为依赖协议；新增 `writeTarget` / `inputSource` / `plainText` |
| 修改 | `InputPane` 输入源分段切换；`FooterBar` 写入目标选择器 |
| 修改 | `Support/Info.plist`：版本 2.0.0 / 2，新增提醒事项权限声明 |

## 兼容性

- 已有事件**无需迁移**：托管标签 `[SchoolEventInbox-Managed]`、`[Managed by SchoolEventInbox]`
  与类型标记格式完全不变，V1.0 写入的事件在 V2.0 的管理面板里仍可识别、删除、平移。
- 现有按类型日历名称不变，继续复用，不会重复创建。
- 日志 schema 不变；仅新增一个 `inputType` 取值 `"text"`（混合输入仍记为 `"email"`）。
- 权限提示文案改为目标中立（如「写入日历失败」→「写入失败」），以便两种目标共用。

## 已知限制

- 提醒事项不支持冲突检测与批量平移（没有时间区间概念），因此切到提醒事项时「管理事件」会禁用。
- 提醒事项的到期时间只取**开始时间**，结束时间不写入。
- 交付二进制为 debug 配置构建（沿用 V1.0 的打包脚本），arm64 only，ad-hoc 签名。

## 安装

1. 下载并解压 `MoreCalendar_v2.0.0_macOS.zip`。
2. 把 `More calendar.app` 拖进「应用程序」。
3. 首次写入时按提示授予「日历」和/或「提醒事项」的完整访问权限。

## 验证情况

- `swift build`：0 error / 0 warning
- 自测：`129 passed, 0 failed`
- Release zip：`unzip -t` 通过、顶层条目为 `More calendar.app/`、无 `.DS_Store`、
  `codesign --verify --deep --strict` 通过、解压到全新目录后可直接启动
- 端到端人工验收（由用户完成）：提醒事项写入、UI 联动与自动置灰

---

## English summary

**v2.0.0** introduces a multi-target write architecture (`TargetProvider`), adds **Apple
Reminders** as a second destination (per-type reminder lists, due date = start time, date-only
for all-day/birthdays), and adds a **Plain Text** input mode that structurally skips OCR.
Input source and write destination are remembered across launches. All V1.0 calendar behaviour,
managed tags and per-type calendar names are preserved, so existing events need no migration.
Verified with `129 passed, 0 failed`; the shipped zip is arm64, ad-hoc signed and launches
when extracted to a clean directory.
