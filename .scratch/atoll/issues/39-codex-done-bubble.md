# 39: Done 很快轉 Idle 時泡泡不要被收掉

**What to build:** Codex 回合結束時，狀態常是 Done 一閃就轉 Idle（ticket 35 實測）。目前泡泡在 agent 離開它宣告的狀態時就被收掉（`AgentBubble.stillApplies` 比對 `state.label`），而 Done → Idle 在 `BubbleRules` 裡又不另外冒泡泡，所以這類回合的泡泡幾乎看不到，ticket 35 的最後一句話與 ticket 28 的變更量也跟著看不到。Done → Idle（以及 Done／Idle → Exited）只是同一個回合在收尾，泡泡應該照常顯示完。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] `stillApplies`：Done 泡泡在 agent 轉成 Idle 或 Exited 時仍然算成立；Idle 泡泡轉 Exited 時也算。轉成 Working／Starting／Needs you／Error（新回合或需要處理）時照舊收掉
- [ ] 泡泡的標題維持它宣告時的狀態（「Done」），不跟著改成 Idle；第二行的最後一句話與變更量照常即時更新（讀取或 git 晚到時補上）
- [ ] `BubbleRules` 的去重不變：同一個回合 Done → Idle 不會再冒第二個泡泡
- [ ] 其他會讀泡泡是否仍成立的地方（排隊、hover 時讓位）行為不變
- [ ] 測試放在 AtollCore（`BubbleTests`）：Done → Idle 仍成立、Done → Exited 仍成立、Done → Working 收掉、Done → Needs you 收掉、Idle → Exited 仍成立、Done → Idle 不冒第二個
- [ ] 實作後用真的 Codex 跑一個回合確認泡泡完整顯示 5 秒，且第二行出現最後一句話

**Out of scope:** 調整泡泡顯示時間、改變哪些轉換會冒泡泡、通知的規則。

## Comments
