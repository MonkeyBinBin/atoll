# 27: 清單直接預覽等待原因

**What to build:** 清單裡 Needs you 的列，在狀態字下方多一行等待原因的預覽：Question 顯示 agent 問的問題，Permission 顯示要執行的工具與指令（例如 `Bash: rm -rf dist`）。看預覽就能決定怎麼回的情況，搭配快速回覆（ticket 26）不用打開面板。目前清單只顯示 herdr-core 的 `status.msg`（`Agent.statusMessage`），herdr CLI 與 cmux 來源沒有這個欄位，而且 Claude Code／Codex 通常不會在裡面填問題內容。

**Blocked by:** —

**Status:** ready-for-agent

**隱私規則的例外（已確認）：** 預覽內容來自終端畫面，是 spec 隱私第 65 條「近期輸出只在面板開著時存在記憶體中、關閉即丟棄」的例外：只對 Needs you 的 agent 保留一段擷取過的預覽（最多 2 行、每行截斷），離開 Needs you 立刻丟棄，不寫入磁碟。整段近期輸出維持原規則。實作時一併更新 spec 第 65 條與 README 的隱私段落。

- [ ] 來源優先順序：有 `statusMessage` 就用它；沒有的話，在轉為 Needs you 時用 `read(terminal:lines:)` 讀一次畫面，再從畫面擷取預覽
- [ ] 擷取只用來顯示，不影響狀態判斷（跟 `OutputFilter` 同樣的原則）。Claude Code 的 permission prompt 擷取「Do you want to…」上方的工具名與指令，question 擷取 prompt box 上方最後一段訊息；版面不認得的工具或擷取不到內容時不顯示預覽，不亂猜
- [ ] 一個 Needs you 期間只讀一次（同一個 `waitingSince`），不輪詢；讀取失敗就不顯示預覽，也不重試
- [ ] 顯示：清單列最多 2 行，超出截斷，help 顯示完整擷取內容；hover card 也顯示。動態島收合態不顯示
- [ ] 隱私：預覽只存在記憶體，agent 離開 Needs you、被移除或 Atoll 結束就丟棄（依上方的隱私規則例外）。通知內容維持只有「工具 · 專案名」，不放預覽
- [ ] 擷取規則放在 AtollCore（擴充 `OutputFilter` 或新增 `WaitingPreview`），並用 Claude Code、Codex 的 permission 與 question 畫面 fixture 測試；另外測試擷取不到時回傳 nil

**Out of scope:** 在清單上直接按 permission 鍵（仍然要進面板）、依預覽內容自動核准、herdr CLI 或 cmux 新增結構化的等待原因欄位。

## Comments
