# 34: 排隊訊息：等 agent 跑完再送

**What to build:** agent 還在 Working 時，面板可以先把下一步排進佇列（例如「做完跑測試，失敗就修」），偵測到這個回合結束才送出。現在只能等它停下來、收到通知或泡泡後再回頭打字；同時跑多個 agent 時，這一步最容易忘或拖很久。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 面板在 Working（含 Starting）時，輸入框旁多一個「Queue」動作（例如 `⌥↩`，按鈕上標示），把目前的文字存成這個 agent 的排隊訊息並清空輸入框；每個 agent 最多一則，再排一次會取代舊的（先確認）。非 Working 狀態照舊直接送出
- [ ] 送出時機：回合結束，判斷規則與「這次跑完時通知我」相同（ticket 24：Done／Exited，或從 Working／Starting 轉 Idle）。Needs you 不算結束：排隊訊息不會被拿去回答 question 或 permission，繼續等
- [ ] 不送出並保留：Error（顯示「Queued message held · agent errored」，讓使用者決定送出或取消）、Unknown／來源斷線（等恢復後依當下狀態判斷，不補送已錯過的時機）
- [ ] Exited 或 agent 被移除：丟棄排隊訊息，若面板開著顯示一次「Queued message dropped」
- [ ] 送出走 `AgentStore.send`，與面板送出同一個狀態機（Delivered／Agent started／Sent · unconfirmed／Failed），只送一次，失敗不重送；失敗時把文字放回該 agent 的輸入框（沿用 ticket 31 的 `draftPrefill`）並保留在面板顯示
- [ ] 顯示：面板輸入框上方顯示排隊中的內容（一行，可展開）與「Cancel」「Edit」（Edit 放回輸入框並取消排隊）；清單列與 hover card 顯示「Queued」標記；送出後泡泡顯示「Queued message sent」
- [ ] 與既有功能的互動：送出後照常觸發 ticket 23 的自動切換規則（只有面板開著該 agent 時）；與「這次跑完時通知我」同時開著時，兩者都生效，通知在送出前發
- [ ] 排隊訊息只存在記憶體，Atoll 結束即丟棄，不寫入磁碟
- [ ] 規則放在 AtollCore（`AgentStore` 的排隊狀態與觸發），fake client 測試：Working → Done 送出一次、→ Idle 送出、Needs you 不送且之後 Done 才送、Error 保留不送、Exited 丟棄、取代與取消、送出失敗保留文字、斷線恢復不補送

**Out of scope:** 多則訊息的佇列、定時送出、跨 agent 的串接（A 跑完後送給 B）、Atoll 重啟後保留。

## Comments
