# 54: 提問的選項直接選

**What to build:** Claude Code 用 `AskUserQuestion` 提問時，選項目前只出現在畫面輸出裡，要回答得在面板輸入數字。30 當時把「question 的選項直接選」列為 out of scope，理由是選項數量不固定。現在把它補上：在面板（以及清單列、hover card，沿用 Allow／Deny 出現的位置）把擷取到的選項顯示成按鈕，按下後送出該選項的按鍵。只支援「單一問題、單選」，其他版面維持現狀，在面板輸入回答。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 事前驗證：用真的 Claude Code 觸發以下版面，存成 fixture，並記下選項的按鍵（數字鍵是否直接選定，還是只移動游標、要再按 Enter）：單一問題單選、多個問題（有分頁）、`multiSelect`、選項帶說明行（如「湯麵、乾麵…」）
- [ ] 選項擷取放在 AtollCore（擴充 `PermissionChoices` 或另立 `QuestionChoices`），從 `WaitingPreview.claudeQuestion` 認得的版面取得編號選項與按鍵；排除 `Type something.`、`Chat about this`。多個問題、`multiSelect`、選項編號不連續、或擷取不到時回傳 nil，不顯示按鈕
- [ ] 按鈕顯示選項標題，說明行放 tooltip；選項多時不撐破版面（例如最多顯示 4 個，其餘進面板）
- [ ] 送出前確認畫面上仍是同一個提問，跟 30 的 permission episode 檢查一樣，已換題或已回答就不送
- [ ] 來源不限：herdr CLI、herdr-core、cmux 的 Claude Code 都適用；按鍵送出走各 adapter 既有的 key／send 路徑（cmux 的數字以 `send` 打字）
- [ ] AtollCore 測試：單選擷取、說明行、排除兩個特殊選項，以及多題、multiSelect、擷取不到時不提供；AgentStore 測試：episode 已換時不送

**Out of scope:** 多個問題、`multiSelect` 的勾選與確認、「Type something.」的自由輸入（維持用面板輸入）、Codex 的提問。

## Comments

- 2026-11-13（agent）：由 21 的 cmux `AskUserQuestion` 實測引出。目前 `WaitingPreview.claudeQuestion` 已會解析 `☐` 標題、問題與編號選項，但只拿來當清單列預覽（`detail` 以「 · 」串接）；`PermissionChoices.extract` 對 question 直接回傳 nil。
