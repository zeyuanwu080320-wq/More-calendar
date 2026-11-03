# 自测与验收报告

日期：2026-10-31  
设备：Apple M5 / macOS 26.6.2 (25G83)  
构建：Command Line Tools + Swift 6.4，SDK `MacOSX26.5.sdk`，ad-hoc 稳定签名  
测试命令：`./Scripts/run_selftest.sh`  
最终结果：**99 passed, 0 failed, 1 skipped**（Keychain CLI 被命令沙箱拒绝）

## 模块逐项报告

### 1. 工程骨架 / 空窗口

| 项 | 内容 |
|---|---|
| 输入 | `Scripts/build_app.sh` |
| 预期 | 生成 `.app`，启动一个 SwiftUI 空窗口 |
| 实际 | 编译通过并启动；窗口截图 `build/artifacts/empty_window.png` |
| 失败原因 | 本机无 Xcode，`xcodebuild` 不可用；改用 SwiftPM + CLT |
| 下一步 | 有 Xcode 时打开 `.xcodeproj` 再 Build 一次 |

### 2. 输入面板

| 项 | 内容 |
|---|---|
| 输入 | 邮件文本粘贴；系统剪贴板图片 + `⌘V`；图片文件拖拽 |
| 预期 | 文本进入 TextEditor；图片进入缩略图区；不落盘 |
| 实际 | 文本 `⌘V` 成功；图片 `⌘V` 成功显示“剪贴板截图”缩略图（`build/artifacts/after_global_paste2.png`）；拖拽代码已实现但未做 UI 自动化 |
| 失败原因 | 无 |
| 下一步 | 用 Finder 手动拖一张 `.jpg` 验证 |

### 3. Vision OCRService

| 项 | 内容 |
|---|---|
| 输入 | 3 张合成但真实形态的截图：预约确认、活动海报、无日期海报 |
| 预期 | 本地识别，按阅读顺序换行；无日期不编造 |
| 实际 | 预约：`校医院体检预约确认 / 姓名：李同学 / 预约时间：2026年3月12日 09:30 / 地点：校医院三楼 305 / ...`；海报：`春季社团招新 / 3月20日 18:30 / 大学生活动中心B201 / 欢迎参加`；无日期：识别到投稿文本，事件 start 为 null |
| 失败原因 | 无 |
| 下一步 | 真实截图抽查断行/多列 |

### 4. DeepSeekService

| 项 | 内容 |
|---|---|
| 输入 | 本地 OCR/邮件文本；system_prompt 从 Resources 读取 |
| 预期 | `model=deepseek-chat`、`response_format=json_object`、只发文本、错误短、不写日历 |
| 实际 | 网络桩验证全部请求契约；401→“API Key 无效或未授权”；非法 JSON→“模型返回内容无法解析”；缺 Key 不发请求。真实调用由用户在 16:27:42 完成：`durationMs=1908, eventCount=2, eventTypes=[deadline, activity]` |
| 失败原因 | 程序化真实调用未跑（避免消耗你的额度 / Keychain 授权弹窗）；已用你的成功日志佐证 |
| 下一步 | 在 App 内点一次解析，确认 Keychain 授权 |

### 5. ParsedEvent / 待确认卡片

| 项 | 内容 |
|---|---|
| 输入 | “报名截止 3月5日；活动 3月8日 14:00；地点 A101” |
| 预期 | 2 条：deadline + activity；地点 A101；evidence 可见；关键类型强制确认 |
| 实际 | 2 条，deadline 3/5 全天、activity 3/8 14:00、A101；所有事件 `needsConfirmation=true`；关键类型复选框锁定；`build/artifacts/final_cards2.png` |
| 失败原因 | 无 |
| 下一步 | 无 |

### 6. CalendarService / 冲突

| 项 | 内容 |
|---|---|
| 输入 | 已确认卡片；同时间段已有事件 |
| 预期 | `requestFullAccessToEvents`；冲突提示；不静默覆盖；权限拒绝时禁用写入 |
| 实际 | 代码编译通过；纯逻辑重叠测试通过；Demo 卡片显示冲突条数与“冲突仍写入”；测试时 App 权限为 **writeOnly**，底部正确提示“仅有写入权限，无法检查冲突”，写入按钮禁用 |
| 失败原因 | 未授权完整日历；未自动写入真实日历（不应替用户写测试事件） |
| 下一步 | 点“升级为完整访问”，做一次真实写入 + 冲突验收 |

### 7. LogService

| 项 | 内容 |
|---|---|
| 输入 | 36 条混合日志（parse/write/missed_feedback） |
| 预期 | JSONL；最近 30 条导出；0600；不含原文/地点；统计可用 |
| 实际 | 导出 30/36 行；权限 `0600`；无原文/地点；stats：usage=28、modRate=57%、missing feedback=1 |
| 失败原因 | 无 |
| 下一步 | 用 2 周真实数据看统计口径 |

### 8. Keychain

| 项 | 内容 |
|---|---|
| 输入 | 保存/读取/删除临时测试 Key |
| 预期 | 只进 macOS Keychain；启动不弹框；不硬编码 |
| 实际 | 自测的 SecItemAdd 被 DSH 命令沙箱拒绝（OSStatus 100001），已 SKIP；App 的 Keychain 条目确实存在（service/account 已确认）；用户真实解析成功；UI 不回显；启动不读取 |
| 失败原因 | 命令沙箱限制 + 重新构建导致旧 ACL 需一次授权 |
| 下一步 | 系统弹 Keychain 时点 Always Allow，或重新保存一次 Key |

## 5 个样本

| # | 样本 | 类型 | 结果 |
|---|---|---|---|
| 1 | `email_01.txt`：截止 3/5、活动 3/8 14:00、A101 | Outlook 邮件文本 | PASS：拆 2 条，deadline + activity，地点正确 |
| 2 | `email_02.txt`：申请截止 4/10 17:00、面试 4/15 10:00-10:30、行政楼 208 | 多事件邮件 | PASS：deadline + appointment |
| 3 | `appointment_01.png` | 预约确认截图 | PASS：OCR 出 2026、09:30、校医院三楼 305 |
| 4 | `poster_01.png`：3月20日 18:30、B201（无年份） | 活动海报截图 | OCR PASS；解析保持 start=null，notes 提示人工补充，不编造 |
| 5 | `no_date_01.png` | 无日期海报 | OCR PASS；空事件 + 短 error |

> 说明：本轮没有拿到你的真实学校邮件/截图，5 个样本是真实形态的合成样本（文本 + 中文字体渲染 PNG），用于覆盖 OCR、拆分和歧义规则；建议用你自己的真实样本再抽查一次。发布整理已按交付要求删除 `Tests/Fixtures`、`Tests/XcodeTests` 与测试截图；上表为整理前的测试记录。

## 验收标准对照

| # | 标准 | 状态 |
|---|---|---|
| 1 | 至少 3 类真实输入 | PASS（邮件文本、预约截图、海报截图；样本为合成） |
| 2 | 写入前可见 evidence | PASS（卡片显示 + 测试断言） |
| 3 | deadline/appointment/exam 100% 用户确认 | PASS（sanitizer 强制 + UI 锁定 + 测试） |
| 4 | 最近 30 条日志导出 | PASS（30/36，JSONL，0600） |
| 5 | 单条解析+确认 ≤30 秒 | PASS（OCR 0.50s；真实 DeepSeek 1.908s；不含用户编辑） |
| 6 | 2 周统计使用次数/修改率/漏检反馈 | 已实现并测试统计逻辑；实际 2 周数据未积累 |
| 7 | “截止 3/5 + 活动 3/8 14:00 + A101”拆 2 条 | PASS |
| 8 | 写入后日历可见；冲突提示不静默覆盖 | 代码与冲突逻辑完成；**真实写入待完整日历权限后手动验收** |

## 真实成功调用记录（来自本机 App 日志）

```text
timestamp=2026-10-31T08:27:42Z
durationMs=1908
eventCount=2
eventTypes=["deadline","activity"]
kind=parse
```

日志不含邮件原文/标题/地点。

## 失败与限制

1. 本机无完整 Xcode，`.xcodeproj` 未经 `xcodebuild` 验证；SwiftPM 同源编译通过。
2. 当前日历权限为 writeOnly，冲突检查需要 fullAccess，因此写入按钮禁用；这是符合规格的失败处理，不是“跳过冲突”。
3. 真实 Keychain 读取在重新构建后可能要求一次 Always Allow；Key 未被删除。
4. 拖拽图片、导出保存面板、真实日历写入尚未做自动化 UI 验收。
5. 多列海报阅读顺序、重复事件 RRULE、2 周长周期统计为后续项。


## 2026-11-01 增量修改自测

修改范围：快捷键焦点、日志增强、应用图标。未修改解析规则、JSON schema、DeepSeek 请求或 system_prompt 日期规则。

| 项 | 输入 | 预期 | 实际 |
|---|---|---|---|
| 快捷键 | 空输入按 `⌘↩` | 解析按钮禁用，不触发 | 无动作（按钮 disabled） |
| 文本框 Cmd+V | 剪贴板同时含图片和文字，焦点在邮件文本框 | 粘贴文字 | PASS，文字写入 TextEditor，未添加图片 |
| 图片区 Cmd+V | 剪贴板仅图片，焦点在图片区 | 添加截图缩略图 | PASS，出现截图缩略图 |
| 写入快捷键 | 无已确认事件 | 快捷键不写入 | 按钮 disabled；菜单重复快捷键已移除 |
| 日志摘要 | `LogService` 写入 parse 摘要 | `ts/inputType/eventCount/types/editedFields/error/durationMs` | PASS；`editedFields=[]` |
| 脱敏 | 邮箱、身份证、手机号、长数字 | `[REDACTED]`，导出无残留 | PASS |
| 清空日志 | 确认后 clear | 删除 log.jsonl，不删目录/其他文件 | PASS |
| 旧日志迁移 | `timestamp/eventTypes/modifiedFields` 旧行 | 可读，导出为 `ts/types/editedFields` | PASS |
| 图标 | `icon.png` 1024 PNG RGBA | iconset/icns，Finder/Dock 更新 | PASS，Finder 与 Dock 均显示新图标 |
| 构建脚本 | 重新运行 `build_app.sh` | 图标仍在，签名有效 | PASS |

自测结果：`62 passed, 0 failed`；样本/OCR 项因 `Tests/Fixtures` 已在发布清理中删除而跳过；Keychain CLI 项因命令沙箱 OSStatus 100001 跳过。

图标源校验：`1024x1024`、`PNG`、`RGBA`、`hasAlpha=yes`，未生成占位图。已生成 `processed_icon.png`（1024 透明画布，原图缩放至 824×824 居中，四边各 100px）。验证发现 macOS 26 会对透明图标自动垫灰底板，因此最终 iconset/icns 改由同图派生的不透明 `AppIcon_canvas.png` 生成；Finder/Dock 实测已无灰圈。最终 `codesign --verify --deep --strict` 通过。


## 2026-11-02 增量：全天/生日/管理/中英

自测结果：`73 passed, 0 failed`（样本/OCR 因发布清理跳过，Keychain CLI 沙箱跳过）。

| 项 | 预期 | 实际 |
|---|---|---|
| 全天 UI | 开“全天”只显示日期，结束时间隐藏 | 代码路径和 English 截图确认 |
| 全天 EventKit | start/end 00:00，结束次日 | `calendarInterval` 自测通过 |
| birthday | 类型/图标/粉色/全天/年度重复 | 类型/图标测试通过，写入代码已实现 |
| 托管标签 | 同时含两套规格标签 | `managedNotes` 自测通过 |
| 管理过滤 | 只保留带标签事件 | `isManagedNotes` 自测 + 代码过滤 |
| 管理 UI | 删除/清空/刷新/多选/批量平移 | 已编译并显示空状态截图；真实日历操作待用户授权数据 |
| 中英切换 | 所有主要按钮/提示英文 | English 截图确认；`Localizable.strings` + L10n |
| 构建/图标/签名 | 重新构建后图标和签名有效 | 构建脚本会复制 AppIcon，最终需再跑一次验证 |
