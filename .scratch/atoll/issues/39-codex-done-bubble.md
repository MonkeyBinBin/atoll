# 39: Done 很快轉 Idle 時泡泡不要被收掉

**What to build:** Codex 回合結束時，狀態常是 Done 一閃就轉 Idle（ticket 35 實測）。目前泡泡在 agent 離開它宣告的狀態時就被收掉（`AgentBubble.stillApplies` 比對 `state.label`），而 Done → Idle 在 `BubbleRules` 裡又不另外冒泡泡，所以這類回合的泡泡幾乎看不到，ticket 35 的最後一句話與 ticket 28 的變更量也跟著看不到。Done → Idle（以及 Done／Idle → Exited）只是同一個回合在收尾，泡泡應該照常顯示完。

**Blocked by:** —

**Status:** resolved

- [x] `stillApplies`：Done 泡泡在 agent 轉成 Idle 或 Exited 時仍然算成立；Idle 泡泡轉 Exited 時也算。轉成 Working／Starting／Needs you／Error（新回合或需要處理）時照舊收掉
- [x] 泡泡的標題維持它宣告時的狀態（「Done」），不跟著改成 Idle；第二行的最後一句話與變更量照常即時更新（讀取或 git 晚到時補上）
- [x] `BubbleRules` 的去重不變：同一個回合 Done → Idle 不會再冒第二個泡泡
- [x] 其他會讀泡泡是否仍成立的地方（排隊、hover 時讓位）行為不變
- [x] 測試放在 AtollCore（`BubbleTests`）：Done → Idle 仍成立、Done → Exited 仍成立、Done → Working 收掉、Done → Needs you 收掉、Idle → Exited 仍成立、Done → Idle 不冒第二個
- [x] 實作後用真的 Codex 跑一個回合確認泡泡完整顯示 5 秒，且第二行出現最後一句話

**Out of scope:** 調整泡泡顯示時間、改變哪些轉換會冒泡泡、通知的規則。

## Comments

- 2026-11-12（agent）：`AgentBubble.stillApplies` 的 `.state` 分支加上「同一回合收尾」的例外：Done 泡泡遇到 Idle／Exited、Idle 泡泡遇到 Exited 仍算成立，其他情況照舊比對 `label`（Working／Starting／Needs you／Error／Unknown 都收掉；反方向如 Idle 泡泡遇到 Done 也不算）。排隊（`advance` 的 `isStillTrue`）與 hover 讓位都走同一個 `stillApplies`，行為只在這三種收尾轉換上改變。`BubbleRules` 沒動：Done → Idle 仍不冒第二個；Done／Idle → Exited 本來就會冒 Exited 泡泡並取代同一個 agent 的現有泡泡，這次不改（out of scope）。泡泡標題本來就用宣告時的 `state`，第二行與變更量本來就讀即時的 agent，不用改 UI。
- 2026-11-12（agent）：測試（`BubbleTests` 新增 4 個）：Done → Idle 仍成立且不冒第二個、標題維持 Done；Done → Exited 與 Idle → Exited 仍成立；Done → Working、Done → Needs you 收掉；Idle 泡泡遇 Done、Exited 泡泡遇 Idle、Done 泡泡遇 Error 都不成立。全套 361 個通過。
- 2026-11-12（agent）：實測：dev-run 加 `hc` 跑 Codex 0.167.2，`hc events` 確認回合是 Working → Done → Idle。泡泡在轉 Idle 後仍在，從 Done 起約 5 秒才收（約 0.9 秒間隔截圖，第 4 張還在、第 5 張已收），標題維持「Done」，第二行出現「All done, nothing to change.」。觀察到的現象：第二行大約在 Done 後 2–3 秒才補上，比 `previewDelay`（0.6 秒）晚；讀畫面本身只要幾 ms，原因沒查（屬 ticket 35 的擷取時機，不在這張範圍）。
