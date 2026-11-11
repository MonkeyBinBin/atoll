# 22: 等待過久的再次提醒

**What to build:** agent 連續停在 Needs you 超過設定時間仍沒有人處理時，再發一次 macOS 通知，並在動態島上重新冒出該角色的泡泡。每段等待只提醒一次；agent 離開 Needs you 後重新計算。設定裡有「Remind after」：Off／2／5／10 分鐘，預設 5 分鐘。

**Blocked by:** —

**Status:** resolved

- [x] 計時以 `waitingSince` 為準：同一段等待中，Needs you 的 kind 改變（例如 Question → Permission）不重新計時；離開 Needs you 再回來則是新的一段
- [x] 每段等待最多一則提醒；不會週期性重複
- [x] 到期時若該 agent 的面板正開著，這段等待就不再提醒（使用者已經看到）
- [x] 通知內容沿用隱私規則：標題「工具 · 專案名」，內文只有 `Still needs you · 5m` 這類狀態字與時間，不含輸出或問題內容；點擊打開該 agent 的面板
- [x] 泡泡沿用既有規則：遵守 Speech bubbles 開關、Needs you／Error 優先、一次一個；去重 key 跟原本轉換的泡泡分開，所以會再冒一次
- [x] 遵守通知總開關；來源離線或狀態為 Unknown 時不提醒；重播 snapshot 時不會因為歷史上的 `waitingSince` 早就超過門檻而立刻補發，而是從 snapshot 當下開始算
- [x] 判斷邏輯放在 AtollCore，透過 `Scheduler` 計時，用 fake scheduler 測試：到期提醒、只提醒一次、中途離開取消、面板開著時跳過、Off 不提醒、離線不提醒

**Out of scope:** 新的角色動畫、menu bar badge 變色（紅色已經代表 Error）、可自訂重複頻率。

## Comments

- 2026-11-11（agent）：計時放在 `AgentStore`：`reminderDelay`（nil = Off）＋`onReminder(agent, waited)`，每次 `rebuild()` 後對帳，每個 Live 的 Needs you 段落（以 `waitingSince` 識別）一個 `Scheduler` 計時器，延遲從這裡第一次看到該段落時起算，所以 snapshot 帶來的舊 `waitingSince` 不會立刻觸發；回報的等待時間則是從 `waitingSince` 算起的真實時間。已提醒（或因面板開著而略過）的段落記在 `remindedEpisodes`，斷線重連後同一段落不再提醒。`NotificationRules.reminder` 產生 `Still needs you · Nm` 通知；泡泡由 `SpeechBubbleController.remind` 以獨立 key 重新排入。設定 `reminderMinutes`（Off／2／5／10，預設 5）。`ReminderTests` 11 個測試，全套 132 個通過。尚未在實際 App 中用真實 agent 試跑。

