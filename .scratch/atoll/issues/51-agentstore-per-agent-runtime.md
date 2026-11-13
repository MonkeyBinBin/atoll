# 51: AgentStore 的每個 agent 狀態收進單一結構

**What to build:** `AgentStore.swift`（約 1950 行）用約 30 個以 address 為 key 的 dictionary 存每個 agent 的狀態（`previews`、`choices`、`finalMessages`、`finalReads`、`finalTimers`、`reminderTimers`、`reminderEpisodes`、`openTurns`、`changeSummaries`、`toplevels`、`summaryGeneration`、`responseTimers`、`previewTimers`、`interruptTimers`、`feedbackTimers`、`endedTimers`…）。agent 消失時的清理散在 `rebuild()`、`dropFinalMessage`、`reconcile*` 等多處，新增欄位很容易漏清，殘留資料或 timer。把它們收進一個 per-agent 的 runtime 結構，移除時一處清掉；再視情況把 waiting preview／final message、reminder、change summary 拆成獨立的小 coordinator。

**Status:** needs-triage

- [ ] 每個 agent 的暫存狀態與 timer 集中在一個結構，agent 移除時統一取消／丟棄
- [ ] 對外 API（`AgentStore` 的 public 介面與 callback）不變，既有測試不改即通過
- [ ] 加一個測試：agent 消失後，store 內沒有它的殘留狀態或排程中的 timer

**Out of scope:** 改變任何行為或 tunable；adapter 層。
