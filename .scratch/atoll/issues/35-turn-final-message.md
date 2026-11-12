# 35: 回合結束時顯示 agent 最後一句話

**What to build:** agent 跑完一個回合時，在泡泡、清單列與 hover card 顯示它最後說的 1–2 行（例如「已完成，測試全過」或「需要你確認 X」），不打開面板就能判斷要不要回。herdr-core 對 Claude Code 會在 Done 的 `status.msg` 填一句摘要（清單與 hover card 已經顯示，例如 `a.txt beta→BETA; notes.md created`），但 Codex、herdr CLI 與 cmux 來源都沒有；泡泡目前只顯示 git 變更量。

**Blocked by:** —

**Status:** ready-for-agent

**隱私規則的例外（需要一併更新 spec 第 65 條與 README）：** 比照等待原因預覽（ticket 27）：只保留擷取出來的最多 2 行（每行截斷），下一個回合開始、agent 被移除或 Atoll 結束就丟棄，不寫入磁碟；通知內容不放。

- [ ] 來源優先順序：有 `statusMessage` 就用它；沒有的話，在回合結束（判斷規則同 ticket 24）時用 `read(terminal:lines:)` 讀一次畫面，用 `OutputFilter.messages` 的規則取出 agent 最後一段回覆的最後 1–2 行
- [ ] 擷取規則依工具：Claude Code 取最後一個 `⏺` 區塊、Codex 取對應的回覆區塊；去掉工具呼叫列、狀態列、輸入框與 spinner。認不得版面或取不到就不顯示，不亂猜
- [ ] 一個回合只讀一次，不輪詢；讀取失敗不重試。延遲一小段時間（例如 0.6 秒，同 `previewDelay`）再讀，等畫面畫完
- [ ] 顯示：泡泡在 git 變更量之外多一行（變更量仍在，兩者都沒有就照舊）；清單列與 hover card 沿用 `statusMessage` 的位置與樣式，help 顯示全文；收合態不顯示
- [ ] 實作前先用真的 Codex（以及 herdr CLI 或 cmux 下的 Claude Code）跑一個回合抓畫面當 fixture，確認回覆區塊的實際版面
- [ ] 擷取放在 AtollCore（新增 `TurnFinalMessage` 或擴充 `OutputFilter`），fixture 測試：Claude Code、Codex 各一般回覆、回覆很長（只取最後 2 行）、最後是工具呼叫沒有文字、認不得的畫面；AgentStore 測試：只讀一次、下個回合清掉、有 status msg 不讀、失敗不重試

**Out of scope:** 用模型摘要回覆內容、顯示完整回覆、通知裡放這句話、Error 狀態的錯誤訊息擷取。

## Comments
