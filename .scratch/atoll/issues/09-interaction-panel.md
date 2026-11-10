# 09: 互動面板：近期輸出＋切回 Herdr＋已確認

**What to build:** 點收合態的角色（或在清單按 `Enter`），動態島往下展開成約 480pt 寬的互動面板，頂部固定顯示目標（`Send to Codex · project-x`）。面板讀取該 agent 近 200 行輸出，顯示 `Fetched at`，收到該 agent 的 status／turn 事件自動刷新，也可 Refresh；Herdr 只回傳畫面時標示 `Screen only`。`Open in Herdr` 聚焦到對應 pane；Herdr app 沒開時停用並顯示 `Herdr app isn't running`。打開面板會在本機把 Done 的 agent 標為已確認（角色轉為待機），不寫回 Herdr。一次只開一個 agent 的面板。

**Blocked by:** 05

**Status:** resolved

- [x] 點角色直接開面板；切換 agent 時替換內容，不疊多個面板
- [x] 輸出讀取、自動刷新、手動刷新、擷取時間、`Screen only` 標示都正確
- [x] 輸出只存在記憶體，面板關閉即丟棄
- [x] `Open in Herdr` 呼叫 `agent.focus`（依 04 的結果決定是否另外帶 Herdr 到前景）
- [x] 已確認只改本機狀態，不發出任何寫回 Herdr 的指令（有 fake client 測試）
- [x] `Esc` 從面板回到上一層

## Comments

- 2026-11-10（agent）：面板讀 200 行、`Fetched at`、`Screen only`、status／turn 事件自動刷新、Refresh；輸出只在 `PanelState` 記憶體中，關閉即丟棄。`Open in Herdr` = `agent.focus` ＋ activate Herdr（依 04 結果）。已確認只存本機。
