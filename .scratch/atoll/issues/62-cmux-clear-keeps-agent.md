# 62: cmux 裡 `/clear` 時 agent 不要短暫消失、panel 不要被關掉

**What to build:** 在 cmux 裡對 Claude Code 執行 `/clear`，agent 會從動態島短暫消失；如果剛好開著它的 panel，panel 會被關回列表。ticket 61 實機測試時發現（見 61 的 Comments，2026-11-18），當時判定與 61 無關，沒有修。

原因：`/clear` 會在同一個 Claude 程序裡開新 session，cmux 先送舊 session 的 `agent.hook.SessionEnd`，新 session 的 `SessionStart` 稍後才到。
- `CmuxSessions.applyHook` 收到 `SessionEnd` 就把 `session.ended` 設為 true。
- `CmuxSessions.terminals()` 用 `agentKey`（pid）合併同一程序的 session，讓 `/clear` 後保留同一個角色、顏色與 panel，但會先濾掉 `ended` 的 session。兩個事件之間，這個 pid 沒有 live session，agent 就從 `terminals()` 消失。
- `IslandModel.validate()` 發現 panel 的 agent 不存在，呼叫 `store.closePanel()` 並切回 `.list`。

做法方向：同一程序的 session 結束後，先保留一小段寬限時間（或保留到程序真的結束），期間這個 pid 出現新 session 就直接接手；寬限時間過了程序還在、也沒有新 session，才移除。`CmuxSessions` 目前是 pure、deterministic，時間判斷要能在測試中注入（例如用 frame 的 `occurred_at`，或由 adapter 的 ticker 驅動）。正常 `/exit`、關掉 surface 時 agent 仍要照常消失，延遲不超過寬限時間。

**Blocked by:** —

**Status:** resolved

- [x] 先在 cmux 重現：開 panel → `/clear` → panel 被關回列表。記下實際的事件順序與 `SessionEnd`、`SessionStart` 之間的間隔，作為寬限時間的依據，寫進 Comments
- [x] `/clear` 前後 agent 的 address 不變、不從 `terminals()` 消失；開著的 panel 不會被關，並接著顯示新 session（transcript 依 61 的規則換到新的 session）
- [x] `/exit` 或關掉 surface：agent 在寬限時間內消失，不會變成殘留的 Unknown agent
- [x] `session.pid` 不明時（`agentKey` 退回 session id），行為維持原狀並在 Comments 說明
- [x] AtollCore 測試：用實測的事件序列驗證 `/clear` 期間 agent 一直存在、`/exit` 後在寬限時間後移除、寬限期間 pid 出現新 session 時接手
- [x] `make check` 通過；實機確認 cmux 的 Claude Code `/clear` 時 panel 維持開啟

**Out of scope:**
- cmux 恢復的 session 不回報狀態、session id 為 `cmux-…` 的問題（61 已讓 panel 改用輪詢避開）
- herdr CLI、herdr-core 的 `/clear` 行為
- Codex（沒有 `/clear` 換 session 的情境）

## Comments

- 2026-11-19（agent）：由 61 的實機測試留言開出。原因是看程式碼推導的（`CmuxSessions.applyHook`、`CmuxSessions.terminals()`、`IslandModel.validate()`），尚未重新重現。
- 2026-11-19（agent）：**重現與量測**：cmux 保留的事件歷史裡，同一個 `_ppid` 從舊 session 的 `SessionEnd` 到新 session 的 `SessionStart` 共 6 次（`/clear` 與 `/resume`），間隔 37–370 ms。每個 hook 都會送兩次，時間相差不到 1 ms。adapter 每收到一個事件就 publish，所以舊 session 的 `SessionEnd` 一到，agent 就從 `terminals()` 消失，`IslandModel.validate()` 接著關掉 panel。
- 2026-11-19（agent）：**實作**：
  - `CmuxSessions.endGrace` 設為 2 秒。pid 已知的 session 結束後，寬限期內仍然顯示（狀態維持結束前的狀態）。同一個 pid 的 live session 永遠優先於正在結束的 session，因為重複的舊 `SessionEnd` 可能晚於新的 `SessionStart` 才到。
  - 結束時間取第一個 `SessionEnd` 的 `occurred_at`，沒有的話用收到的時間。重複的 `SessionEnd` 不會重新起算。
  - pid 不明時，`agentKey` 退回 session id，新 session 本來就是另一個 agent，所以不給寬限期，行為維持原狀。
  - `CmuxAdapter` 收到 `SessionEnd` 後，寬限期滿再 publish 一次，`/exit` 不用等下一個 3 秒 tick。關掉 surface 或程序結束時，`include` 照舊濾掉已結束的 pid。
  - history replay 的 `occurred_at` 都在過去，寬限期直接視為已過。
  - review 後把 `publishSnapshot`／`publishChanges` 用 `publishing` mutex 序列化，避免舊 snapshot 晚一步 diff，誤送 `.removed` 又把 panel 關掉。
- 2026-11-19（agent）：**測試**：`CmuxTests` 新增 `clearGap`、`exitAfterGrace`、`clearDuplicates`、`noPidNoGrace`。`make check` 584 個通過。
- 2026-11-19（agent）：**限制**：frame 晚到超過 2 秒時（app 卡住、stream 積壓），收到時寬限期已經過了，panel 仍會被關掉。
- 2026-11-19（使用者）：安裝後在 cmux 實測 `/clear`，panel 保持開著。同一段錄到的事件：`/clear` 間隔 103 ms（02:21:09.635 → .738）；02:21:37 的 `/exit` 之後程序在幾秒內結束。
- 2026-11-19（agent，`/code-review medium` 後修正）：
  - **replay 結尾的寬限期**：原本只在收到 `SessionEnd` 時排重新檢查，replay 最後 2 秒內結束的 session 最久會留到下一個 tick（約 5 秒）。改成由 `CmuxSessions.graceDeadline(now:)` 回報最早到期的寬限期，adapter 在每次 publish（含 replay 結束時的 snapshot）後依此排程，到期後再排下一個。adapter 也不必再認 `SessionEnd` 事件名。
  - **stream 已重啟**：重新檢查觸發時，除了 generation 以外，也確認排程它的 `cmux events` 子程序仍是目前的 `child`，避免在 `.disconnected` 之後，或下一個 stream 的 replay 中途 publish。
  - **舊 session 復活**：已結束的 session 只接受 `SessionStart`（`/resume`），其他晚到的重複 hook 都略過，不會蓋過接手的新 session。從沒看過的 session 送來的 `SessionEnd` 也略過。
  - **記憶體**：已結束的 session 寬限期一過，就在下一個 hook 時從 `sessions` 移除。
  - 限制：被移除後才到的同一 session 非 `SessionStart` hook（晚到超過 2 秒）會被當成新的 live session。
  - 時鐘基準不一致（結束時間用 wall clock、計時器用單調時鐘）未處理，只有系統時鐘往回調整時才會讓 agent 多留一下。
  - 測試新增 `endedStaysEnded`、`pruneEnded`、`graceDeadline`。用到 `occurred_at` 的測試，`apply` 都傳入同一個 `now`。`make check` 587 個通過。

