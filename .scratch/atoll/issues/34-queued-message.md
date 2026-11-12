# 34: 排隊訊息：等 agent 跑完再送

**What to build:** agent 還在 Working 時，面板可以先把下一步排進佇列（例如「做完跑測試，失敗就修」），偵測到這個回合結束才送出。現在只能等它停下來、收到通知或泡泡後再回頭打字；同時跑多個 agent 時，這一步最容易忘或拖很久。

**Blocked by:** —

**Status:** resolved

- [x] 面板在 Working（含 Starting）時，輸入框旁多一個「Queue」動作（例如 `⌥↩`，按鈕上標示），把目前的文字存成這個 agent 的排隊訊息並清空輸入框；每個 agent 最多一則，再排一次會取代舊的（先確認）。非 Working 狀態照舊直接送出
- [x] 送出時機：回合結束，判斷規則與「這次跑完時通知我」相同（ticket 24：Done／Exited，或從 Working／Starting 轉 Idle）。Needs you 不算結束：排隊訊息不會被拿去回答 question 或 permission，繼續等
- [x] 不送出並保留：Error（顯示「Queued message held · agent errored」，讓使用者決定送出或取消）、Unknown／來源斷線（等恢復後依當下狀態判斷，不補送已錯過的時機）
- [x] Exited 或 agent 被移除：丟棄排隊訊息，若面板開著顯示一次「Queued message dropped」
- [x] 送出走 `AgentStore.send`，與面板送出同一個狀態機（Delivered／Agent started／Sent · unconfirmed／Failed），只送一次，失敗不重送；失敗時把文字放回該 agent 的輸入框（沿用 ticket 31 的 `draftPrefill`）並保留在面板顯示
- [x] 顯示：面板輸入框上方顯示排隊中的內容（一行，可展開）與「Cancel」「Edit」（Edit 放回輸入框並取消排隊）；清單列與 hover card 顯示「Queued」標記；送出後泡泡顯示「Queued message sent」
- [x] 與既有功能的互動：送出後照常觸發 ticket 23 的自動切換規則（只有面板開著該 agent 時）；與「這次跑完時通知我」同時開著時，兩者都生效，通知在送出前發
- [x] 排隊訊息只存在記憶體，Atoll 結束即丟棄，不寫入磁碟
- [x] 規則放在 AtollCore（`AgentStore` 的排隊狀態與觸發），fake client 測試：Working → Done 送出一次、→ Idle 送出、Needs you 不送且之後 Done 才送、Error 保留不送、Exited 丟棄、取代與取消、送出失敗保留文字、斷線恢復不補送

**Out of scope:** 多則訊息的佇列、定時送出、跨 agent 的串接（A 跑完後送給 B）、Atoll 重啟後保留。

## Comments

- 2026-11-12（agent）：AtollCore 新增 `QueuedMessage`（text、status：waiting／held／sending）；`AgentStore` 加 `queuedMessages`、`canQueue`、`queue(_:for:)`（只在 Working／Starting 接受，去掉結尾空白）、`cancelQueued`、`editQueued`（取出文字並取消排隊）、`canSendQueuedNow`／`sendQueuedNow`（held 時由使用者送出；agent 在 Needs you 時不送，以免被當成回答）、`queueNotices`（`.dropped`：面板開著時因 Exited 丟棄；`.notSent`：另一則還在送；關面板或換 agent 清除）、`onQueuedSent`、`onQueuedFailed`。送出只在 live transition 觸發，排在 `notifyIfFinished` 之後（通知先發）：Done，或從 Working／Starting 轉 Idle；走 `send`，失敗或另一則還在送（`send` 回 false，此時面板顯示 `.notSent`）都不重送，文字經 `onQueuedFailed` 放回 `draftPrefill`；放回時輸入框已有文字就接在它上面，不覆蓋。回合結束規則抽成 `turnEnded(_:from:)`，與「這次跑完時通知我」共用。Error 保留、Exited／移除丟棄在每次 rebuild 依狀態處理（已在送出中的不動，等結果回來，避免同時出現 dropped 與 sent），所以斷線恢復後的 snapshot 不會補送，但會依當下狀態保留或丟棄。held 之後就算 agent 又跑完一輪也不自動送，等使用者決定。
- 2026-11-12（agent）：UI：面板在 Working／Starting 時輸入框旁有「Queue ⌥↩」；`⌥↩` 由 key monitor 攔下再交給面板（多行輸入框會先吃掉 ⌥↩ 插入換行，按鈕的 keyboardShortcut 不可靠）。已有排隊訊息時第一次按變成「Replace queued?」，4 秒內再按才取代（計時用 token，舊的計時不會清掉新的確認）。輸入框上方顯示排隊列（一行，點開展開；Edit／Cancel，held 時多「Send now」並顯示「Queued message held · agent errored」），Exited 丟棄時顯示「Queued message dropped · the agent exited」，另一則還在送時顯示「Queued message not sent …」。agent 被移除時面板本來就會關閉，所以只有 Exited 會看到 dropped 提示。清單列與 hover card 有 `Queued`（held 時 `Queued · held`）標記，help 顯示內容。泡泡新增 `queuedSent` 種類「Queued message sent」。自動切換（ticket 23）沿用原規則：只有回答 Needs you 才會 arm，排隊送出時 agent 已是 Done／Idle，所以不會切換。DebugHook 新增 `queue <t> <text>`，`post` 支援 `opt`。
- 2026-11-12（agent）：測試：`QueuedMessageTests` 16 個（Done 送一次、Idle、Needs you 不送之後 Done 才送、只在 Working 可排與去結尾換行、取代／取消／編輯、Error 保留與 Send now、Exited 丟棄含面板提示、移除丟棄、送出回呼、送出失敗放回文字、另一則送出中、斷線恢復不補送、通知先於送出、Needs you 時不能 Send now、送出中 Exited 不另外顯示 dropped、`canQueue`），全套 309 個通過。dev-run 實測：Claude Code（haiku）跑長回合時在面板打字按 `⌥↩`，排隊列與清單的 Queued 標記出現；回合 Done 後自動送出，agent 回了 BANANA；收合狀態下另一輪送出時泡泡顯示「Queued message sent」；code review 後重測 `⌥↩`：不再插入換行，第二次排隊先顯示「Replace queued?」，再按才取代。Error 保留、Exited 丟棄與送出失敗只有 fake client 測試，沒有在真 agent 上重現。
