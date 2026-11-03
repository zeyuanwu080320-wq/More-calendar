# More calendar v2.0.0

发布日期：2026-11-03 · 构建号 `3` · macOS 15+ (arm64)

V1.0 只面向 Apple 日历，所有 EventKit 逻辑都绑在一个 `CalendarService` 里。V2.0 把写入侧
抽象成 `TargetProvider` 协议，并在这个地基上完成了三件事：**Apple 提醒事项**、**纯文本输入**、
**Google 日历**。

## 亮点

- **三种写入目标**：底部一键在「Apple 日历 / Apple 提醒事项 / Google 日历」之间切换，选择跨启动记忆。
- **Apple 提醒事项**：与日历同样按事件类型分列表，沿用同一套托管标签；到期时间取开始时间，
  全天与生日只写日期，生日保留每年重复。
- **Google 日历**：OAuth 2.0（PKCE + loopback）授权，写入你选定的那个日历，
  事件颜色仍按类型区分（红/紫/橙/蓝/绿）。
- **纯文本输入**：左侧新增「邮件 / 截图 ↔ 纯文本」切换。纯文本模式从结构上不经过 OCR，
  也不会读取已缓存的截图。
- **架构**：新增 `TargetProvider` / `ManagedEventProvider` 两层协议，并改为 async；
  EventKit 仅存在于两个 Apple Provider 内，Google 的网络代码全部收敛在 `Providers/Google/`。

## 变更明细

| 类别 | 内容 |
|---|---|
| 新增 | `Providers/TargetProvider.swift`（协议 + `TargetProviderID` + `TargetProviderError`） |
| 新增 | `Providers/ManagedEventMetadata.swift`（托管标签与按类型命名，纯逻辑） |
| 新增 | `Providers/AppleCalendarProvider.swift`（V1 全部 EventKit 逻辑迁移至此） |
| 新增 | `Providers/AppleRemindersProvider.swift`（提醒事项目标） |
| 新增 | `Providers/Google/*`（OAuth 客户端加载、PKCE、loopback、令牌管理、REST 客户端、映射、Provider） |
| 新增 | `Models/ManagedEvent.swift`、`Models/InputSource.swift`（`InputComposer` 载荷组装） |
| 删除 | `Services/CalendarService.swift`、`User_Guide_EN.txt`（由 `User_Guide.txt` 取代） |
| 修改 | `AppModel` 依赖协议；新增 `writeTarget` / `inputSource` / `plainText`，均跨启动记忆 |
| 修改 | `InputPane` 输入源分段切换；`FooterBar` 三目标选择器与 Google 日历菜单 |
| 修改 | `Support/Info.plist`：版本 2.0.0 / 3，新增提醒事项权限声明 |

## Google 日历需要自备凭据（重要）

安装包**不包含** OAuth 凭据。使用 Google 日历前必须：

1. 在 Google Cloud 创建 **桌面应用** 类型的 OAuth 客户端，启用 Google Calendar API，
   同意屏幕添加 `calendar.events` 与 `calendar.readonly`。
2. 把下载的 JSON 重命名为 `google_client_secret.json`，放到
   `~/Library/Application Support/More calendar/google_client_secret.json`。
3. 重启 App → 切到 Google → 点「连接 Google」。

**分享给朋友时**：把朋友的 Gmail 地址加入同一项目的「OAuth 同意屏幕 → 测试用户」，
否则对方会收到 `access_denied`。详细步骤见包内 `使用说明.txt` / `User_Guide.txt`。

## 兼容性

- 已有事件**无需迁移**：托管标签与类型标记格式完全不变，V1.0 写入的事件仍可识别、删除、平移。
- 按类型日历名不变，继续复用，不会重复创建。
- 日志 schema 不变；仅新增 `inputType = "text"` 取值，以及内部诊断类别 `google_diag` / `google_auth`。

## 已知限制

- 提醒事项不支持冲突检测与批量平移（没有时间区间概念），切到提醒事项时「管理事件」会置灰。
- 提醒事项的到期时间只取开始时间。
- Google 侧批量平移不做冲突预检；仅支持单个 Google 账号。
- Google 网页按**日历自身时区**显示事件：若日历时区是美东，14:00(HKT) 会显示为 01:00，
  是同一时刻的两种显示，不是数据错误。
- 交付二进制为 debug 配置构建（沿用 V1.0 的打包脚本），arm64 only，ad-hoc 签名，未经 Apple 公证。

## 包内文件

```
MoreCalendar_v2.0.0_macOS.zip
├── More calendar.app
├── 使用说明.txt      （中文）
└── User_Guide.txt    （英文）
```

## 验证情况

- `swift build`：0 error
- 自测：**200 passed, 0 failed**
- PKCE 与 RFC 7636 官方测试向量逐字节一致
- 真实 OAuth 授权、写入、颜色分类、按日历落位：由用户在其真实 Google 账号下验收通过
- Release zip：`unzip -t` 通过、顶层为 `More calendar.app/` + 两份说明书、
  `codesign --verify --deep --strict` 通过、解压到全新目录可直接启动

---

## English summary

**v2.0.0** introduces a multi-target write architecture (`TargetProvider`, now async) and ships
three new capabilities: **Apple Reminders** (per-type lists, due date = start time),
**Google Calendar** (OAuth 2.0 with PKCE + loopback, single calendar of your choice,
events colour-coded by type), and a **Plain Text** input mode that structurally skips OCR.
Input source and write destination are remembered across launches. Existing events need no
migration and all V1.0 calendar behaviour is preserved.

Google Calendar requires your own OAuth credential at
`~/Library/Application Support/More calendar/google_client_secret.json`; to share it with a friend,
add their Gmail address to the OAuth consent screen's test users.

Verified with **200 passing self-tests**; the shipped zip is arm64, ad-hoc signed, contains both
user guides, and launches when extracted to a clean directory.
