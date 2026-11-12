# 37: 最近啟動與啟動範本

**What to build:** 啟動表單記住最近幾次的「工具＋目錄＋任務（＋名稱、space、是否 New worktree）」組合，一鍵帶回或直接重新啟動；也能把常用組合存成範本（例如「在 X 專案跑 review」）。目前表單只記最近目錄（`recentFolders`），每次都要重選工具、重打任務。這裡的「範本」是 Atoll 自己的表單預設，與 herdr-core 的 template（`templates.list`，會出現在工具選單）是兩回事，UI 用詞要分開（例如叫「Presets」）。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 最近啟動：每次成功送出（狀態到 Launched 或 unconfirmed，不含 failed）記一筆：工具 option id、使用者選的目錄（不是 worktree 路徑）、任務全文、名稱、space、New worktree 開關；最多 10 筆，相同組合（工具＋目錄＋任務）只留最新一筆
- [ ] 表單頂端多一個「Recent」選單：每筆顯示「工具 · 目錄名 · 任務前 40 字」；選了只填入表單，不直接啟動。另提供「Launch again」（`⌘R`，針對最近一筆）直接用同樣的組合送出，送出前一樣顯示確認摘要（表單填好、聚焦在 Launch 按鈕，不跳過確認）
- [ ] 帶回時的檢查：目錄不存在就不填目錄並提示；工具是已不存在的 herdr template 就改回預設工具並提示；New worktree 只在目錄仍是 repo 時開啟，branch 一律重新產生（不沿用舊 branch，避免撞名）
- [ ] Presets：表單上「Save as preset…」把目前的組合存成具名 preset（名稱必填，最多 20 個）；表單頂端的選單列出 presets，選了填入表單。Settings 新增 Presets 區塊可改名、刪除、調整順序
- [ ] 儲存：最近啟動與 presets 都存在 `UserDefaults`（同 `recentFolders`），任務文字會被寫入磁碟，所以 Settings 提供「Clear recent launches」，並在 README 隱私段落註明「啟動表單的最近紀錄與 presets 會存在本機 UserDefaults」
- [ ] 選單內容只來自本機紀錄，不讀 agent 的畫面或輸出
- [ ] 紀錄的增刪、去重、上限與帶回時的檢查放在 AtollCore（或 App 層可測試的 model），單元測試：去重、上限、failed 不記、目錄消失、template 消失、worktree 開關的處理

**Out of scope:** 跨機器同步、匯入／匯出 presets、一次啟動多個 agent、排程啟動。

## Comments
