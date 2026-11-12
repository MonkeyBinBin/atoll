# 35: 回合結束時顯示 agent 最後一句話

**What to build:** agent 跑完一個回合時，在泡泡、清單列與 hover card 顯示它最後說的 1–2 行（例如「已完成，測試全過」或「需要你確認 X」），不打開面板就能判斷要不要回。herdr-core 對 Claude Code 會在 Done 的 `status.msg` 填一句摘要（清單與 hover card 已經顯示，例如 `a.txt beta→BETA; notes.md created`），但 Codex、herdr CLI 與 cmux 來源都沒有；泡泡目前只顯示 git 變更量。

**Blocked by:** —

**Status:** resolved

**隱私規則的例外（需要一併更新 spec 第 65 條與 README）：** 比照等待原因預覽（ticket 27）：只保留擷取出來的最多 2 行（每行截斷），下一個回合開始、agent 被移除或 Atoll 結束就丟棄，不寫入磁碟；通知內容不放。

- [x] 來源優先順序：有 `statusMessage` 就用它；沒有的話，在回合結束（判斷規則同 ticket 24）時用 `read(terminal:lines:)` 讀一次畫面，用 `OutputFilter.messages` 的規則取出 agent 最後一段回覆的最後 1–2 行
- [x] 擷取規則依工具：Claude Code 取最後一個 `⏺` 區塊、Codex 取對應的回覆區塊；去掉工具呼叫列、狀態列、輸入框與 spinner。認不得版面或取不到就不顯示，不亂猜
- [x] 一個回合只讀一次，不輪詢；讀取失敗不重試。延遲一小段時間（例如 0.6 秒，同 `previewDelay`）再讀，等畫面畫完
- [x] 顯示：泡泡在 git 變更量之外多一行（變更量仍在，兩者都沒有就照舊）；清單列與 hover card 沿用 `statusMessage` 的位置與樣式，help 顯示全文；收合態不顯示
- [x] 實作前先用真的 Codex（以及 herdr CLI 或 cmux 下的 Claude Code）跑一個回合抓畫面當 fixture，確認回覆區塊的實際版面
- [x] 擷取放在 AtollCore（新增 `TurnFinalMessage` 或擴充 `OutputFilter`），fixture 測試：Claude Code、Codex 各一般回覆、回覆很長（只取最後 2 行）、最後是工具呼叫沒有文字、認不得的畫面；AgentStore 測試：只讀一次、下個回合清掉、有 status msg 不讀、失敗不重試

**Out of scope:** 用模型摘要回覆內容、顯示完整回覆、通知裡放這句話、Error 狀態的錯誤訊息擷取。

## Comments

- 2026-11-12（agent）：fixture 用 `hc` 跑真的 Claude Code 2.1.322（haiku）與 Codex 0.167.0 各抓一般回覆、長回覆，Codex 另抓以工具區塊（`• Explored` / `└ List ls`）結束的回合，以及實測時才出現的「回覆下方多一行 `└ Tip: …`」版面；Claude Code 以工具呼叫結束的畫面請它照做時它仍會寫結語，改依真實的 `⏺ Bash(…)` / `⎿` 列組成。herdr CLI 與 cmux 下跑的是同一個 Claude Code TUI，沒有另外抓。herdr-core 對 Codex 也不給 `status.msg`，Codex 回合結束時狀態有時是 Done 很快轉 Idle、有時直接 Idle。
- 2026-11-12（agent）：AtollCore 新增 `TurnFinalMessage`（最多 2 行，每行用 `WaitingPreview.cut` 截到 200 字）：兩種工具都要先在畫面底部找到輸入框（`OutputFilter.claudeMessagesAboveInput`／`codexMessagesAboveInput`，從原本的 `claudeMessages`／`codexMessages` 拆出、找不到時回 nil），找不到就不顯示，避免把狀態列當成回覆。Claude Code 去掉輸入框與 footer 後，取最後一個 `⏺`（若最後的標記是 `❯` 就是沒有回覆）；標頭像 `Tool(` 或區塊內有 `⎿` 視為工具呼叫，不顯示。Codex 切掉輸入列後，去掉 `└ Tip:` 列與尾端的 `Worked for …`，取最後一個 `•`；標頭是工具動詞（Explored、Edited…、Updated Plan）或標頭下一行是 `└`／`│` 視為工具區塊。`AgentStore` 在 live transition 判定回合結束（與「這次跑完時通知我」共用 `turnEnded`）且沒有 `statusMessage`、不是 generic 工具時，等 `previewDelay` 讀一次畫面；每次讀取拿一個全域遞增的 token，下一個回合（Working／Starting／Needs you）或 agent 移除時清掉，晚到的結果（包括 agent 移除後同一個 address 又被建立）就作廢；計時到期時 agent 已不在 Done／Idle／Exited（例如轉 Error）就不讀；讀取失敗不重試。Done／Idle → Exited 視為同一個回合收尾，保留訊息、不重讀（同 `trackTurn` 的規則）。`Agent.finalMessage` 放結果，`Agent.lastWords`（`statusMessage ?? finalMessage`）是清單、hover card、泡泡共用的顯示規則。行截斷抽成 `OutputFilter.cut`，`WaitingPreview` 與泡泡共用。
- 2026-11-12（agent）：UI：清單列原本 `statusMessage` 的位置改顯示 `lastWords`（最多 2 行，help 全文），hover card 同樣；泡泡在 Done／Idle／Exited 時加第二行（`lastWords` 的最後一行，超過 60 字截斷）。收合的動態島本身不顯示文字。
- 2026-11-12（agent）：測試：擷取 10 個（Claude 一般／長回覆／工具結尾、Codex 一般／長回覆／Tip 列／工具結尾、認不得的畫面與 generic、沒有輸入框、截斷），store 11 個（只讀一次、Idle 也算、下個回合清掉、有 status msg 不讀、失敗不重試、新回合開始後晚到的結果不採用、Done → Exited 保留不重讀、計時到期前轉 Error 不讀、讀取中被移除又建立不採用舊結果、`lastWords` 優先順序、移除後清掉），全套 330 個通過。dev-run 實測：Codex 回合結束後清單顯示最後兩行；強制冒泡確認第二行版面（Claude 用 status msg、Codex 用擷取結果）。已知限制：Codex 回合結束時常是 Done 一閃即轉 Idle，既有的泡泡規則會在 Done 消失時收掉泡泡、Done → Idle 也不另冒泡，所以這種情況下泡泡來不及顯示這一行（清單與 hover card 不受影響）。
