# 44: 通知只發給動態島目前的 space

**What to build:** ticket 42 讓動態島可以切到單一 Herdr space，但通知仍然對每個 space 都發。專注在一個 space 時，其他 space 的通知會一直打斷。Settings 加一個選項，打開後只對動態島目前選的 space 發通知；其他 space 的 agent 照樣顯示在動態島（Needs you／Error 仍在左翼）、照樣冒泡泡，只是不發 macOS 通知。

**Blocked by:** 42

**Status:** resolved

- [x] Settings › Notifications 加「Only notify for the island's space」，預設關閉，存在 UserDefaults
- [x] 打開且動態島選了 space（或 Other）時，不在該範圍的 agent 不發 Needs you／Error／Done 通知與等待提醒；動態島選 All，或選的 space 已經不存在（`SpaceGrouping.effective` 回到 All）時照常
- [x] 面板鈴鐺「這次跑完時通知我」是手動指定的，不受影響
- [x] 被略過的轉換不補發：之後切到那個 space 不會追發先前的通知；同一個 agent 下一次轉換照常判斷
- [x] 規則放在 AtollCore（`NotificationSettings.space`），`NotificationTests` 涵蓋：範圍外不發（三種通知與提醒）、範圍內照發、All 照發、鈴鐺照發、略過後不影響下一次

**Out of scope:** 泡泡依 space 過濾（已跟著收合列）、依 space 個別設定通知、全域快捷鍵 `⌃⌥⌘A` 的範圍。

## Comments

- 2026-11-12（agent）：`NotificationSettings.space`（預設 `.all`）；`NotificationRules.notification` 與 `reminder` 在 `enabled` 之後檢查 `space.contains(agent)`，範圍外直接回 nil、不寫 `lastSent`，所以不補發也不影響下一次轉換；`finished`（鈴鐺）不檢查。App 端 `AppSettings.notifyIslandSpaceOnly`（UserDefaults，預設關），`Notifier.notificationSettings` 在打開時把 space 設成 `SpaceGrouping.effective(islandSpace, store.spaces)`，所以選 All 或 space 已不存在時等同關閉。Settings › Notifications 加 Toggle 與說明。
- 2026-11-12（agent）：測試：`NotificationTests` 新增 4 個（範圍外三種通知與提醒不發、範圍內照發；Other 與 All；鈴鐺不受影響；略過不記錄、下一次照常）；全套 409 個通過。實機只確認 build 與 app 啟動，沒有觸發跨 space 的 Needs you 來看通知被略過；Settings 的 Notifications 區塊在 debug 截圖範圍外，未目視確認。
- 2026-11-12（agent）：補拍 README 截圖時（demo 模式）確認 Settings › Notifications 的「Only notify for the island's space」與說明文字正常顯示。
