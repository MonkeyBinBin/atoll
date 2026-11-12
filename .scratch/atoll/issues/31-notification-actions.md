# 31: 從 macOS 通知直接回應

**What to build:** Needs you 的通知加上動作按鈕，人在別的 app 時不用切到動態島：permission 給 Allow／Deny，question 與一般等待給 Reply（文字輸入）。目前點通知只會打開面板（ticket 14）。

**Blocked by:** 30

**Status:** resolved

**隱私規則的例外（已確認）：** 通知內容目前只有「工具 · 專案名」（spec 隱私規則、ticket 14、ticket 27 都明確不放預覽）。在看不到指令的地方按 Allow 等於盲目核准，所以做法是：新增設定「Show waiting reason in notifications」，預設關閉；**關閉時通知只提供 Deny 與 Reply，不提供 Allow**；打開時通知 body 放 `WaitingPreview` 的 title（例如 `Bash: rm -rf dist`），才提供 Allow。實作時一併更新 spec 隱私段落與 README。

- [x] `Notifier` 註冊 `UNNotificationCategory`：permission（Allow／Deny）、permission-no-preview（Deny）、reply（`UNTextInputNotificationAction`）。Allow／Deny 的按鍵沿用 ticket 30 從畫面推出的對應；推不出來的 permission 只給 Reply 與預設的點擊打開面板
- [x] 按下動作時再確認狀態：agent 還在同一個 Needs you episode（通知 `userInfo` 帶 `waitingSince`）才送；已經離開或換了 episode 就不送，改發一則「No longer waiting · 工具 · 專案」或直接打開面板（擇一，實作時決定並記錄）
- [x] Reply 走 `AgentStore.send`，與面板送出同一個狀態機；不自動重送
- [x] 送出結果回饋：成功不另外通知（動態島照常更新）；失敗發一則「Reply failed · 工具 · 專案」，點擊打開面板，輸入的文字預填回輸入框
- [x] Deny 與 Allow 都不需要把 app 帶到前景（`UNNotificationActionOptions` 不含 `.foreground`），Reply 也一樣
- [x] 等待過久的再提醒通知（ticket 22）使用同樣的 category
- [x] category 選擇（依 blocked kind、預覽有無、設定）放在 AtollCore 的 `NotificationRules`，fake client 測試：permission 有／無預覽、question、auth（不給動作）、episode 已換時不送

**Out of scope:** Error／Done 通知的動作、通知裡顯示終端輸出、iOS／Apple Watch 轉發。

## Comments

- 2026-11-12（agent）：AtollCore：`NotificationSettings.showWaitingReason`（預設 false）；`AgentNotification` 加 `actions`（`NotificationActions` OptionSet：allow／deny／reply，7 種組合各有固定的 category id，如 `atoll.actions.allow-deny`）與 `episode`；`NotificationRules.decorate(_:with:settings:)` 依 agent 當下狀態決定：有 `permissionChoices` 才給 Deny，再加上通知顯示得出原因（`waitingPreview.title` 或 `statusMessage`）才給 Allow；replyMode 是 `.text(force: true)` 或 `.textAndKeys` 給 Reply；auth 與非 Needs you 不動。episode 存進 userInfo 用 `timeIntervalSinceReferenceDate`（`encodeEpisode`／`decodeEpisode`）。
- 2026-11-12（agent）：時序：Needs you 的通知要等畫面讀完才知道有沒有按鍵，所以 `AgentStore` 新增 `isReadingWaitingScreen(_:)` 與 `onWaitingDetails`（讀完就呼叫，不論有沒有找到），`Notifier` 讀取中會先扣住通知，讀完或最多 2 秒後依當下的 agent 送出；扣住期間 agent 已經離開該 episode 就不送了。再提醒通知（ticket 22）走同一條路。`respond` 加 completion；`send` 加 completion 並回傳是否送出；新增 `reply(_:to:episode:completion:)`，不在同一個 episode 回 nil。
- 2026-11-12（agent）：跟 ticket 不同／實作時決定：(1) 推不出按鍵的 permission 不給 Reply：permission 的 replyMode 是 `.keys`，文字送不進對話框，所以只剩點擊打開面板。(2) 按下動作時已經離開 episode：發「No longer waiting · nothing was sent」通知，不直接打開面板（保持不搶前景）；Reply 的情況通知帶著輸入文字，點擊打開面板並預填（`IslandModel.draftPrefill`）。(3) 送出失敗：Allow／Deny 發「Allow failed · 原因」；Reply 發「Reply failed · 原因」，同樣點擊預填。所有動作都不帶 `.foreground`。
- 2026-11-12（agent）：dev-run 實測抓到兩個 bug 並修正、補回歸測試：(1) 讀完畫面後先發 `onWaitingDetails` 才 rebuild，通知拿到的 agent 還沒有按鍵，category 是空的；改成先 rebuild。(2) episode 用 `timeIntervalSince1970` 存，讀回來差一個捨入誤差，Deny 一律變成「No longer waiting」；改用 reference date。
- 2026-11-12（agent）：測試：`NotificationDecorateTests` 10 個、`NotificationActionStoreTests` 7 個，全套 260 個通過。dev-run 實測（真的 Claude Code，herdr-core）：設定關閉時 permission 通知 body 只有「Needs you」、category `atoll.actions.deny`，Deny → 被拒、檔案沒有建立；設定打開時 body 為「Needs you · approve Bash: touch n5.txt」、category `atoll.actions.allow-deny`，Allow → 檔案建立，對同一則通知再按 Allow → 「No longer waiting」；question 通知 category `atoll.actions.reply`，Reply「Blue」→ agent 收到；episode 已過的 Reply → 通知帶 draft，點擊後面板輸入框預填。限制：macOS 通知橫幅上的按鈕無法用腳本點，實測是透過 DebugHook 的 `notify <t> allow|deny|reply|open`，讀取已送出通知的 userInfo 後走與 `didReceive` 相同的 `respond`／`reply`／`onOpen`；真正從橫幅點按鈕、`UNTextInputNotificationAction` 的輸入框，以及 category 在 macOS 上的註冊與顯示沒有實測。Codex、herdr CLI、cmux 只有單元測試。
