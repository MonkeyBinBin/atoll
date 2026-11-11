# 27: 清單直接預覽等待原因

**What to build:** 清單裡 Needs you 的列，在狀態字下方多一行等待原因的預覽：Question 顯示 agent 問的問題，Permission 顯示要執行的工具與指令（例如 `Bash: rm -rf dist`）。看預覽就能決定怎麼回的情況，搭配快速回覆（ticket 26）不用打開面板。目前清單只顯示 herdr-core 的 `status.msg`（`Agent.statusMessage`），herdr CLI 與 cmux 來源沒有這個欄位，而且 Claude Code／Codex 通常不會在裡面填問題內容。

**Blocked by:** —

**Status:** resolved

**隱私規則的例外（已確認）：** 預覽內容來自終端畫面，是 spec 隱私第 65 條「近期輸出只在面板開著時存在記憶體中、關閉即丟棄」的例外：只對 Needs you 的 agent 保留一段擷取過的預覽（最多 2 行、每行截斷），離開 Needs you 立刻丟棄，不寫入磁碟。整段近期輸出維持原規則。實作時一併更新 spec 第 65 條與 README 的隱私段落。

- [x] 來源優先順序：有 `statusMessage` 就用它；沒有的話，在轉為 Needs you 時用 `read(terminal:lines:)` 讀一次畫面，再從畫面擷取預覽
- [x] 擷取只用來顯示，不影響狀態判斷（跟 `OutputFilter` 同樣的原則）。Claude Code 的 permission prompt 擷取「Do you want to…」上方的工具名與指令，question 擷取 prompt box 上方最後一段訊息；版面不認得的工具或擷取不到內容時不顯示預覽，不亂猜
- [x] 一個 Needs you 期間只讀一次（同一個 `waitingSince`），不輪詢；讀取失敗就不顯示預覽，也不重試
- [x] 顯示：清單列最多 2 行，超出截斷，help 顯示完整擷取內容；hover card 也顯示。動態島收合態不顯示
- [x] 隱私：預覽只存在記憶體，agent 離開 Needs you、被移除或 Atoll 結束就丟棄（依上方的隱私規則例外）。通知內容維持只有「工具 · 專案名」，不放預覽
- [x] 擷取規則放在 AtollCore（擴充 `OutputFilter` 或新增 `WaitingPreview`），並用 Claude Code、Codex 的 permission 與 question 畫面 fixture 測試；另外測試擷取不到時回傳 nil

**Out of scope:** 在清單上直接按 permission 鍵（仍然要進面板）、依預覽內容自動核准、herdr CLI 或 cmux 新增結構化的等待原因欄位。

## Comments

- 2026-11-11（agent）：先用真的 Claude Code 2.1.322（`--permission-mode default`）與 Codex 0.167.0（`-a on-request -s read-only`）觸發對話框、用 `hc read` 抓畫面當 fixture，發現 ticket 的前提要修正：herdr-core 對 Claude Code 的 `status.msg` 有填等待原因（permission：`approve Bash: touch hello.txt`；question：`answer: Which color …? (Red · Blue)`），清單原本就會顯示。實際要從畫面擷取的是：Claude Code 走 herdr CLI 或 cmux（這兩個 adapter 都不填 `msg`），以及 Codex（herdr-core 也沒有 `msg`）。
- 2026-11-11（agent）：AtollCore 新增 `WaitingPreview`（`title`＋`detail`，每行最多 200 字元）。Claude Code permission：`Do you want to…` 上方最後一條 `─` 線之後的第一行是工具名（去掉「 command」），兩條 `╌` 虛線之間是指令，描述當 detail，`Tip:` 行略過；question：`☐` 標題之後的第一行是問題，編號選項（去掉 `Type something.`、`Chat about this`）當 detail；Codex：`Would you like to …?` 之後的 `$ ` 行為 `Run: 指令`，`Reason:` 當 detail。`.unspecified`（herdr CLI、cmux）兩種 Claude Code 版面都試。Codex 的 question、Claude Code 的多題分頁、`.auth`、generic 工具一律 nil。`AgentStore.reconcilePreviews` 以 `waitingSince` 為一個 episode：沒有 `statusMessage` 時排程 `previewDelay`（0.6 秒，等對話框畫完）後讀 `previewLines`（80）行一次；讀取失敗或擷取不到就沒有預覽，不重試；離開 Needs you、新 episode 或 agent 被移除就丟棄。清單列與 hover card 顯示（標題等寬字、detail 次要色，各一行，help 顯示全文），收合態與通知不顯示。spec 第 65 條與 README 隱私段落已更新。
- 2026-11-11（agent）：測試：`WaitingPreviewExtractionTests`（3 個實際畫面 fixture、`.unspecified`、捲動歷史中的舊對話框、6 種擷取不到、截斷）與 `WaitingPreviewStoreTests` 6 個（延遲後只讀一次、離開就丟棄與下個 episode 重讀、延遲內離開不讀、有 status msg 不讀、失敗不重試、移除），全套 208 個通過。dev-run 實測：Codex 停在 permission（herdr-core，沒有 `msg`），清單列與 hover card 顯示「Run: touch hello3.txt」與 Codex 的理由。herdr CLI 與 cmux 來源沒有實測，只有 fixture 測試。

