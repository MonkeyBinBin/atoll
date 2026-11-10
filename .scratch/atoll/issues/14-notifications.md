# 14: 通知

**What to build:** agent 轉為 Needs you 或 Error 時發 macOS 通知；Done 通知預設關閉，可在設定依 agent 或專案打開；Working 永不通知。通知內容只有「工具 · 專案名」，不含輸出。點通知直接打開該 agent 的互動面板。設定中有通知總開關。

**Blocked by:** 03, 09

**Status:** resolved

- [x] 通知觸發規則（哪些狀態轉換會通知）有 fake client 測試
- [x] 通知內容不含終端機輸出或任務內容
- [x] 點通知打開對應 agent 的面板，而不是總清單
- [x] 設定中可開關全部通知，以及依 agent／專案開啟 Done 通知
- [x] 同一次狀態轉換不重複通知

## Comments

- 2026-11-10（agent）：`NotificationRules`（Needs you／Error 預設通知、Done 依 agent／專案開啟、master switch、同轉換不重複、離線不通知），`Notifier` 用 UNUserNotificationCenter，點擊打開該 agent 面板；內容只有「工具 · 專案」與狀態字。需從 .app 執行（`swift run` 無 bundle 時只寫 log）。
