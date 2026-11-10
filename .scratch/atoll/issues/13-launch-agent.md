# 13: 啟動 agent

**What to build:** 從動態島打開啟動表單（同樣是動態島往下展開的面板）：選擇工具（內建 Claude Code、Codex，加上自動讀取的 core templates）、從最近目錄或 Finder 挑工作目錄、輸入初始任務與可選顯示名稱、選 space（預設值可在設定修改）。送出前固定顯示「工具 · 目錄 · 初始任務前 60 字」摘要。送出經 `herdr-app do tab.new` 建立，狀態顯示 `Starting…` → `Launched`，或 `Created · task start unconfirmed`（附 Open in Herdr），或 `Launch failed`。Herdr app 沒開時啟動功能停用。

**Blocked by:** 09

**Status:** resolved

- [x] 工具選單包含 `claude`、`codex --no-daemon` 與 templates 目錄中的每個 template
- [x] 最近目錄清單在本機保存；可用 Finder 選新目錄
- [x] 確認摘要在送出前一直可見
- [x] 啟動狀態機：拿到 terminal 且 30 秒內收到 working → Launched；逾時 → unconfirmed；指令失敗 → failed（依 04 的結果調整判定），全部有 fake client 測試
- [x] 新 agent 出現在 Herdr GUI 指定的 space，並出現在動態島
- [x] Herdr app 未執行時按鈕停用並顯示 `Herdr app isn't running`

## Comments

- 2026-11-10（agent）：啟動表單（內建 Claude Code／Codex＋templates、最近目錄＋Finder、任務、名稱、space、常駐摘要），`herdr-app do tab.new` 回傳 terminal 後等 30 秒內 working。內建工具以 `$SHELL -lic "exec …"` 啟動（core PATH 無 nvm，見 spec 事實 1）。已端到端驗證 Launched。
- 2026-11-10（agent，更正）：內建工具改回直接 argv（`claude`／`codex --no-daemon`）。tab.new 自己會用 login shell 包裝並把 task 當最後一個參數傳入，先前加的 shell 包裝會吃掉 task。已用真實 Claude Code 驗證：3 秒內 Launched，且收到任務並回覆。core 目前沒有任何 template，template 選項未實測。
