# TODO / 未完成项

## 本次增量已完成（2026-11-01）

- [x] 快捷键：`⌘↩` 解析、`⌘⇧↩` 写入；写入菜单重复快捷键已移除，避免双触发
- [x] Cmd+V 焦点修正：文本框聚焦时文本优先；图片区/非文本焦点时粘贴截图
- [x] 日志摘要字段、入库/导出双重脱敏、最近 30 条导出、确认后清空日志
- [x] 图标：`icon.png` → `processed_icon.png`（1024 透明画布，824 居中）；因 macOS 26 自动给透明画布垫灰底，最终用同色系 `AppIcon_canvas.png` 生成 `AppIcon.iconset` + `AppIcon.icns`；**没有占位图**；Finder/Dock 已实测无灰圈
- [x] `Scripts/build_app.sh` 构建到 `../build`，自动复制图标、设置 `CFBundleIconFile`，再执行既有稳定签名
- [x] 增量自测：`62 passed, 0 failed`（样本/OCR 项因发布清理跳过，Keychain CLI 项跳过）
- [x] 使用说明中英双版：`01_User_Delivery/使用说明.txt` 与 `使用说明_EN.txt`

## 仍需注意

- [ ] 本次没有在 App 内实际触发一次 DeepSeek 解析来观察摘要落盘（会调用真实 Keychain/API）；摘要字段由 SelfTest 和代码路径验证。
- [ ] 清空日志按钮已实现确认弹窗，删除逻辑已由 SelfTest 验证；未在真实 App 里删除你的现有日志。

## 需要本机用户操作

- [ ] **升级完整日历权限**：底部“升级为完整访问” → 系统设置允许。当前 App 状态为“仅有写入权限”，无法检查冲突，写入按钮按设计禁用。
- [ ] **首次解析若弹出 Keychain 密码**：选择 Always Allow；或打开“API Key”重新保存一次。你的 Key 仍在 Keychain，只是旧构建签名变了。
- [ ] **做一次真实日历写入验收**：创建 1 条无害事件（例如“测试-More calendar”），确认出现在默认日历；再验证与已有事件重叠时底部提示、默认跳过。
- [ ] **测试一次真实冲突**：在默认日历建一个重叠事件，确认卡片出现“冲突仍写入”，底部显示跳过数。

## 环境限制

- [ ] 本机没有完整 Xcode，`xcodebuild` 不可执行；`.xcodeproj` 只做了 plist 语法和文件路径校验，需要在有 Xcode 的机器上 Build/Run 一次。
- [ ] 自测里的 Keychain 保存/读取因 DSH 命令沙箱返回 OSStatus 100001 被跳过；已在 .app 内看到 Keychain 条目，并有一次用户真实解析成功。
- [ ] Keychain README 中的“稳定签名”仅在 `Scripts/build_app.sh` 生效；用 Xcode 直接签名时默认仍是 ad-hoc cdhash，重建后可能需要重新授权。

## 样本真实性

- [ ] 本轮没有拿到你真实的学校邮件/预约截图/海报，5 个样本是**真实形态的合成样本**（邮件文本 + 用中文字体渲染的预约/海报/无日期截图）。验收覆盖了格式、OCR、拆分规则；不能代替对你真实邮件的抽查。
- [ ] 建议用你自己的 3 封 Outlook 邮件 + 2 张真实截图再跑一遍，观察 OCR 断行和 DeepSeek 日期判断。

## 功能边界（明确未做）

- [ ] 重复事件规则编辑器（“每周二”只提示、不生成 RRULE）
- [ ] 多列海报的复杂阅读顺序（当前按 Vision 文本行 y 倒序、x 正序拼接）
- [ ] 结束时间缺失时的真实时长推断（当前 UI 明示“开始 +1 小时占位”）
- [ ] Outlook OAuth / Graph / 后台监听
- [ ] 分发、上架、账号、云同步

## 质量改进（非第一版必须）

- [ ] 用真实 2 周数据验证“使用次数/修改率/漏检反馈”统计口径
- [ ] 冲突检查排除全天背景事件的可配置项（当前所有日历事件都参与重叠判断）
- [ ] 日志导出 Choose Folder 的自动化测试
- [ ] 图片拖拽文件路径的 UI 自动化测试（本次只实际验证了 `⌘V` 图片粘贴、缩略图显示、OCR）
- [ ] 增加“重新检查冲突”显式按钮，避免用户改时间后看到旧冲突提示
- [ ] 为 DeepSeek 增加一次“验证 Key”按钮（会消耗少量额度）


## 本轮增量（2026-11-02）

- [x] 全天切换只显示日期；EventKit 全天 start/end 归零到 00:00
- [x] birthday 类型、SF Symbol/颜色、生日全天 + 年度重复；删除循环使用 `.futureEvents`
- [x] 所有通过本 App 写入的事件同时带 `[SchoolEventInbox-Managed]` 与 `[Managed by SchoolEventInbox]` 标签（两版规格字符串并存）
- [x] 管理面板：过滤、多选、单条删除、清空所有、刷新、批量平移、冲突汇总、循环事件拦截
- [x] 中英切换与英文本地化；源码目录含 `User_Guide_EN.txt`
- [x] 自测 81 项通过（样本/OCR 因发布清理跳过，Keychain CLI 在沙箱跳过）

- [ ] 真实日历写入/删除/批量平移尚未在真实系统日历中执行验收；需要完整权限和用户确认的事件数据。
- [ ] 管理面板里的真实事件列表、删除和批量平移尚未做 UI 自动化。
- [ ] 本轮同时写入两个托管标签是为兼容前文两套规格字符串；若后续确定唯一标签，可移除兼容标签。
- [ ] 之前由旧版本写入且没有标签的事件不会被管理面板识别。


## 编译检查（2026-11-02 22:50）

- [x] `swift build --product SchoolEventInbox`：exit 0
- [x] `swift build --product SchoolEventInboxSelfTest`：exit 0
- 仅有 Swift 6 actor-isolation 与 SDK 搜索路径 warning，当前 Swift 5 language mode 下不阻断构建。

## P3 按类型分配日历（2026-11-02）

- [x] `CalendarService.calendarForWriting(_:)`：按事件类型查找 / 创建独立日历
- [x] 颜色映射：考试红 / 生日紫 / 截止橙 / 预约蓝 / 活动·其他绿（`ManagedCalendarColorToken`）
- [x] activity 与 other 合并为「活动」一个日历
- [x] `More Calendar - ` 标题前缀作为跨启动识别标记
- [x] 创建源优先级：默认日历账户 → 本地 → CalDAV；禁止用 subscribed / birthdays 源
- [x] 创建失败回退默认日历，并在底部状态栏提示
- [x] `routedCalendarIDs` 缓存，避免同批次重复建日历
- [x] 自测新增 16 条纯映射断言（总计 97 passed, 0 failed）
- [ ] **待用户验收**：真实账户下解析「考试 + 生日」并写入，确认落在两个不同颜色的日历里；再确认管理面板可删除
- [ ] 空日历不会自动清理（清空事件后日历仍在），如需可在 Apple 日历手动删

## P3 追加：管理面板批量删除（2026-11-02）

- [x] 底部工具栏新增「删除选中 / Delete Selected」，垃圾桶图标，紧邻「批量平移」
- [x] 无勾选时自动置灰（`.disabled(selected.isEmpty)`）
- [x] 二次确认文案含数量：「确认删除选中的 X 个事件吗？这将同时从 Apple 日历中移除它们。」
- [x] 循环事件走 `.futureEvents`
- [x] 删除后清空勾选 + 刷新列表
- [x] `CalendarService.deleteManagedEvents(ids:)` + `ManagedDeleteResult`
- [x] 「清空所有」降级为纯文字次要操作（`.plain` + 次级色）
- [x] 中英双语文案 + `Localizable.strings` / `L10n.dynamic` 词条
- [ ] **待用户验收**：勾选 2 条 → 删除选中 → 确认 2 条消失、其余保留

## P3 追加补漏（2026-11-02）

- [x] 批量平移冲突详情：`ManagedShiftConflict` + 冲突详情 sheet，逐条写明「谁与谁重叠」
- [x] `hasConflict -> conflictingEvent`，能拿到挡路事件本身
- [x] 管理面板 40 处硬编码中文改为 `L10n.t`（含按钮/空状态/权限页/底部栏/弹窗/help）
- [x] 选择计数 `N 条已选择` 也接入双语
- [x] 日历标题语言化：`ManagedCalendarLanguage` + `managedCalendarLabel(for:)`
- [x] 切换语言时 `syncManagedCalendarTitles` 重命名已有分类，失败静默
- [x] 反向标题解析 `managedCalendarBucket(forTitle:)`，避免中英各建一个日历
- [x] 自测 97 → 105 项（新增 8 条语言/回溯断言）
- [ ] **待用户验收**：制造两个冲突事件批量平移，确认弹窗写明具体事件名
- [ ] **待用户验收**：切 EN 后管理面板全英文；切换后已有分类名变英文
- [ ] 其余视图（InputPane / EventCard / EventListPane / FooterBar / APIKeySheet）仍在用 bundle 查表机制，未统一到 `L10n.t`；若英文模式下这些区域仍是中文，需按同样方式改造
