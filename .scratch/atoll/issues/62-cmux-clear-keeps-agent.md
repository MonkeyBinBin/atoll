# 62: cmux 裡 `/clear` 時 agent 不要短暫消失、panel 不要被關掉

**What to build:** 在 cmux 裡對 Claude Code 執行 `/clear`，agent 會從動態島短暫消失；如果剛好開著它的 panel，panel 會被關回列表。ticket 61 實機測試時發現（見 61 的 Comments，2026-11-18），當時判定與 61 無關，沒有修。

原因：`/clear` 會在同一個 Claude 程序裡開新 session，cmux 先送舊 session 的 `agent.hook.SessionEnd`，新 session 的 `SessionStart` 稍後才到。
- `CmuxSessions.applyHook` 收到 `SessionEnd` 就把 `session.ended` 設為 true。
- `CmuxSessions.terminals()` 用 `agentKey`（pid）合併同一程序的 session，讓 `/clear` 後保留同一個角色、顏色與 panel，但會先濾掉 `ended` 的 session。兩個事件之間，這個 pid 沒有 live session，agent 就從 `terminals()` 消失。
- `IslandModel.validate()` 發現 panel 的 agent 不存在，呼叫 `store.closePanel()` 並切回 `.list`。

做法方向：同一程序的 session 結束後，先保留一小段寬限時間（或保留到程序真的結束），期間這個 pid 出現新 session 就直接接手；寬限時間過了程序還在、也沒有新 session，才移除。`CmuxSessions` 目前是 pure、deterministic，時間判斷要能在測試中注入（例如用 frame 的 `occurred_at`，或由 adapter 的 ticker 驅動）。正常 `/exit`、關掉 surface 時 agent 仍要照常消失，延遲不超過寬限時間。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 先在 cmux 重現：開 panel → `/clear` → panel 被關回列表。記下實際的事件順序與 `SessionEnd`、`SessionStart` 之間的間隔，作為寬限時間的依據，寫進 Comments
- [ ] `/clear` 前後 agent 的 address 不變、不從 `terminals()` 消失；開著的 panel 不會被關，並接著顯示新 session（transcript 依 61 的規則換到新的 session）
- [ ] `/exit` 或關掉 surface：agent 在寬限時間內消失，不會變成殘留的 Unknown agent
- [ ] `session.pid` 不明時（`agentKey` 退回 session id），行為維持原狀並在 Comments 說明
- [ ] AtollCore 測試：用實測的事件序列驗證 `/clear` 期間 agent 一直存在、`/exit` 後在寬限時間後移除、寬限期間 pid 出現新 session 時接手
- [ ] `make check` 通過；實機確認 cmux 的 Claude Code `/clear` 時 panel 維持開啟

**Out of scope:**
- cmux 恢復的 session 不回報狀態、session id 為 `cmux-…` 的問題（61 已讓 panel 改用輪詢避開）
- herdr CLI、herdr-core 的 `/clear` 行為
- Codex（沒有 `/clear` 換 session 的情境）

## Comments

- 2026-11-19（agent）：由 61 的實機測試留言開出。原因是看程式碼推導的（`CmuxSessions.applyHook`、`CmuxSessions.terminals()`、`IslandModel.validate()`），尚未重新重現。
