# 31: 從 macOS 通知直接回應

**What to build:** Needs you 的通知加上動作按鈕，人在別的 app 時不用切到動態島：permission 給 Allow／Deny，question 與一般等待給 Reply（文字輸入）。目前點通知只會打開面板（ticket 14）。

**Blocked by:** 30

**Status:** ready-for-agent

**隱私規則的例外（已確認）：** 通知內容目前只有「工具 · 專案名」（spec 隱私規則、ticket 14、ticket 27 都明確不放預覽）。在看不到指令的地方按 Allow 等於盲目核准，所以做法是：新增設定「Show waiting reason in notifications」，預設關閉；**關閉時通知只提供 Deny 與 Reply，不提供 Allow**；打開時通知 body 放 `WaitingPreview` 的 title（例如 `Bash: rm -rf dist`），才提供 Allow。實作時一併更新 spec 隱私段落與 README。

- [ ] `Notifier` 註冊 `UNNotificationCategory`：permission（Allow／Deny）、permission-no-preview（Deny）、reply（`UNTextInputNotificationAction`）。Allow／Deny 的按鍵沿用 ticket 30 從畫面推出的對應；推不出來的 permission 只給 Reply 與預設的點擊打開面板
- [ ] 按下動作時再確認狀態：agent 還在同一個 Needs you episode（通知 `userInfo` 帶 `waitingSince`）才送；已經離開或換了 episode 就不送，改發一則「No longer waiting · 工具 · 專案」或直接打開面板（擇一，實作時決定並記錄）
- [ ] Reply 走 `AgentStore.send`，與面板送出同一個狀態機；不自動重送
- [ ] 送出結果回饋：成功不另外通知（動態島照常更新）；失敗發一則「Reply failed · 工具 · 專案」，點擊打開面板，輸入的文字預填回輸入框
- [ ] Deny 與 Allow 都不需要把 app 帶到前景（`UNNotificationActionOptions` 不含 `.foreground`），Reply 也一樣
- [ ] 等待過久的再提醒通知（ticket 22）使用同樣的 category
- [ ] category 選擇（依 blocked kind、預覽有無、設定）放在 AtollCore 的 `NotificationRules`，fake client 測試：permission 有／無預覽、question、auth（不給動作）、episode 已換時不送

**Out of scope:** Error／Done 通知的動作、通知裡顯示終端輸出、iOS／Apple Watch 轉發。

## Comments
