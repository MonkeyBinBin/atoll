# 23: 處理完自動跳到下一個等待中的 agent

**What to build:** 在互動面板回應某個 Needs you 的 agent（傳送訊息、回答 question、按 permission 鍵、中斷）後，等來源回報該 agent 已離開 Needs you，如果還有其他 agent 在等，面板就自動切到等最久的那一個，讓你連續處理到佇列清空。佇列清空時面板留在原 agent，標題列短暫顯示 `All clear`。設定裡有「Auto-advance to next waiting agent」開關，預設開。

**Blocked by:** —

**Status:** resolved

- [x] 只在「使用者從面板對一個 Needs you 的 agent 動作，而且之後來源回報它離開 Needs you」時觸發。agent 自己離開 Needs you（例如在終端機裡回覆）、或使用者沒有在面板動作，都不會跳
- [x] 以來源回報的狀態轉換為準，不看送出狀態。Sent · unconfirmed／Failed 不會觸發跳轉
- [x] 寬限期約 1.5 秒：如果 agent 在寬限期內又回到 Needs you（例如連續兩個 permission prompt），就留在原面板不跳
- [x] 下一個的選擇跟 `earliestWaitingAgent` 一致（`waitingSince` 最早），並排除剛處理的那個
- [x] 面板輸入框還有未送出的文字時不跳，避免打到一半被切走
- [x] 面板標題列顯示還有幾個在等（例如 `2 more waiting`）；`⌘]` 手動跳到下一個在等的 agent，沒有其他在等的 agent 時不動作
- [x] 跳轉沿用一般的切換面板流程：舊面板的輸出丟棄、新面板讀取輸出並標記 acknowledged；`Esc` 照常回到清單
- [x] 「下一個是誰」和寬限期判斷放在 AtollCore（例如 `AgentStore` 提供下一個等待中 agent 的查詢、以 `Scheduler` 處理寬限期），並有測試：有下一個時跳、沒有時不跳、寬限期內回到 Needs you 時不跳、非面板動作不觸發、Off 不跳

**Out of scope:** 跳轉動畫、跨 agent 批次核准 permission。

## Comments

- 2026-11-11（agent）：判斷放在 `AgentStore`：面板開著時對 Needs you 的 agent `send`／`pressKey`／確認中斷，就記下「已準備跳轉」（`armAdvance`）。來源回報它離開 Needs you（不含轉為 Unknown）後啟動 `Timing.autoAdvanceGrace`（1.5 秒）；期滿時它仍不在 Needs you、面板仍是它，就呼叫 `onAutoAdvance(next)`，下一個由 `nextWaitingAgent(excluding:)` 決定（`waitingSince` 最早），沒有下一個則呼叫 `onAllClear`。送出或按鍵失敗、關閉或切換面板、關掉設定都會取消。Sent · unconfirmed 不會取消，仍以來源回報的轉換為準。草稿檢查在 App 層：`AgentPanelView` 把輸入框是否有字同步到 `IslandModel.panelHasDraft`，`autoAdvance(to:)` 有草稿時不跳。標題列顯示 `N more waiting`（可點，`⌘]` 同效），清空時顯示 2.5 秒 `All clear`。設定 `autoAdvance`（預設開）。`AutoAdvanceTests` 10 個測試，全套 142 個通過。尚未在實際 App 中試跑。

