# 18: 一般終端機啟動的 agent 也出現在動態島（方案 A）

**What to build:** 在 Ghostty、cmux、iTerm、Terminal 等一般終端機輸入 `claude`／`codex` 時，改由 `hc run` 在 herdr-core 裡執行（像 ssh 一樣附著在原終端機），讓動態島能顯示、傳訊息、按鍵、中斷與讀取輸出。不在 Herdr 視窗內的 terminal，`Open in Herdr` 先幫它開一個 tab；面板另提供切回原終端機 app。

**Blocked by:** 09, 13

**Status:** resolved

- [x] `scripts/shell/herdr-island.zsh` 提供 `claude`／`codex` 包裝函式；已在 hc terminal（`HC_TERMINAL_ID`）內時照原樣執行，不重複包裝
- [x] 以 label `island.origin` 記錄來源 app：`HERDR_ISLAND_ORIGIN` > `__CFBundleIdentifier` > `TERM_PROGRAM`
- [x] `Open in Herdr`：不在 `herdr-app ls` 中的 terminal 先 `terminal.keep {place: tab}` 再 `agent.focus`
- [x] 面板 `Switch to <App>`（app 已安裝時才顯示）；清單卡片與 hover 資訊卡標示 `in <App>`
- [x] 來源 label 對映與 `herdr-app ls` 解析有測試

## Comments

- 2026-11-10（agent）：以 pty（`script`）模擬一般終端機驗證：`hc run` 附著在前景、`parent: null`、正常回報狀態、帶 `island.origin`；`Open in Herdr` 實際為外部 terminal 開出 tab 並 focus。已知限制：`Switch to <App>` 只把該 app 帶到前景，無法跳到特定分頁或 workspace；在 cmux 內實際帶出的 `__CFBundleIdentifier` 未實測，偵測不到時可設 `HERDR_ISLAND_ORIGIN=com.cmuxterm.app`。Claude Desktop、ChatGPT desktop 不在本 ticket 範圍。
- 2026-11-10（agent）：改為選用。cmux 與 herdr CLI 已由 ticket 20、21 直接整合，不需要這個包裝函式；它只用於沒有自己 agent 整合的終端機（Ghostty、Terminal 等），在 `CMUX_SURFACE_ID`／`HERDR_PANE_ID`／`HC_TERMINAL_ID` 存在時一律照原樣執行。
