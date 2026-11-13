# 54: 提問的選項直接選

**What to build:** Claude Code 用 `AskUserQuestion` 提問時，選項目前只出現在畫面輸出裡，要回答得在面板輸入數字。30 當時把「question 的選項直接選」列為 out of scope，理由是選項數量不固定。現在把它補上：在面板（以及清單列、hover card，沿用 Allow／Deny 出現的位置）把擷取到的選項顯示成按鈕，按下後送出該選項的按鍵。只支援「單一問題、單選」，其他版面維持現狀，在面板輸入回答。

**Blocked by:** —

**Status:** resolved

- [x] 事前驗證：用真的 Claude Code 觸發以下版面，存成 fixture，並記下選項的按鍵（數字鍵是否直接選定，還是只移動游標、要再按 Enter）：單一問題單選、多個問題（有分頁）、`multiSelect`、選項帶說明行（如「湯麵、乾麵…」）
- [x] 選項擷取放在 AtollCore（擴充 `PermissionChoices` 或另立 `QuestionChoices`），從 `WaitingPreview.claudeQuestion` 認得的版面取得編號選項與按鍵；排除 `Type something.`、`Chat about this`。多個問題、`multiSelect`、選項編號不連續、或擷取不到時回傳 nil，不顯示按鈕
- [x] 按鈕顯示選項標題，說明行放 tooltip；選項多時不撐破版面（例如最多顯示 4 個，其餘進面板）
- [x] 送出前確認畫面上仍是同一個提問，跟 30 的 permission episode 檢查一樣，已換題或已回答就不送
- [x] 來源不限：herdr CLI、herdr-core、cmux 的 Claude Code 都適用；按鍵送出走各 adapter 既有的 key／send 路徑（cmux 的數字以 `send` 打字）
- [x] AtollCore 測試：單選擷取、說明行、排除兩個特殊選項，以及多題、multiSelect、擷取不到時不提供；AgentStore 測試：episode 已換時不送

**Out of scope:** 多個問題、`multiSelect` 的勾選與確認、「Type something.」的自由輸入（維持用面板輸入）、Codex 的提問。

## Comments

- 2026-11-13（agent）：由 21 的 cmux `AskUserQuestion` 實測引出。目前 `WaitingPreview.claudeQuestion` 已會解析 `☐` 標題、問題與編號選項，但只拿來當清單列預覽（`detail` 以「 · 」串接）；`PermissionChoices.extract` 對 question 直接回傳 nil。
- 2026-11-13（agent）：**事前驗證**（Claude Code 2.1.323，在 cmux 自建的測試 workspace，事後已關閉）：單題單選的標題列是 ` ☐ 午餐`；`multiSelect` 是 `←  ☐ 飲料  ✔ Submit  →`，選項前有 `[ ]`；多題是 `←  ☐ 午餐  ☐ 飲料  ✔ Submit  →`。單題單選時按數字鍵會直接選定並送出（不需要 Enter），回答紀錄為「午餐要吃什麼？ → 飯」。cmux 的 `send-key` 在有提問時會拒絕送出（要 `--force`，adapter 已經會加）；單一數字以 `send` 打字，不受影響。
- 2026-11-13（agent）：**實作**：AtollCore 新增 `QuestionChoices`（選項的 label、說明行 detail、按鍵＝編號），只認 ` ☐` 開頭的標題，因此 `←…→` 版面（多題、multiSelect）不提供，`Type something`／`Chat about this` 排除。`PermissionChoice` 新增 `.option(QuestionChoices.Option)`，直接沿用 `AgentStore.respond` 的 episode 檢查、送出狀態與 auto-advance；只有選項仍在本 episode 擷取到的 `questionChoices` 裡才送出。按鈕放在清單列與面板（輸入框下方、快速回覆上方），說明行放 tooltip；hover card 只有提示文字，因為卡片不能點擊。AskUserQuestion 每題最多 4 個選項，所以不另外截斷數量，label 太長時以 chip 規則截短。測試：`QuestionChoicesTests` 4 個（單選擷取、多題／multiSelect 不提供、從清單送出、episode 已換時不送），全套 503 個通過。
- 2026-11-13（agent）：實測時面板出現方框加上 `¯ ' "` 的亂碼：那是 Kitty 圖像協定的 Unicode placeholder（`U+10EEEE` 加上表示列／欄的組合附加符號），狀態列 mod 用它畫像素圖，cmux 的 `read-screen` 會原樣回傳。`OutputFilter.lines` 改成丟掉 placeholder 及其附加符號，因此開頭是圖像的 spinner 行（「✳ Loosing arrows…」）也能被 Messages only 濾掉。新增測試，全套 504 個通過。
- 2026-11-13（agent）：實測發現 cmux 回傳的每一行後面都接著右側面板（狀態列 mod 的 SPELL BOOK），導致選項標籤拖著面板文字被截短成「麵 …」，分隔線也認不出來，`Type something.`／`Chat about this` 因此混進按鈕。新增 `OutputFilter.dialogLines`（清理後切掉右側面板），`WaitingPreview`、`PermissionChoices`、`QuestionChoices` 都改用它；`stripSidePanel` 在兩欄 `│` 同分時改取最左邊那欄（面板自己的右框也會每行出現）。fixture 加上帶右側面板的版本，並用實際讀到的畫面驗證只擷取到「麵」「飯」。按鈕改成膠囊樣式，數字在前，以 Needs you 的顏色區分。全套 505 個通過。
- 2026-11-13（使用者）：cmux 實測按鈕出現、點選回答正常，樣式確認 OK，結案。herdr CLI／herdr-core 的 Claude 沒有另外實測，它們走同一個 `AgentStore.respond` 與各自 adapter 既有的 keys 路徑。
