# 21: cmux 後端

**What to build:** 讀取 cmux 裡由 cmux 自己整合的 Claude Code／Codex session：以 `cmux events` 的 `agent.hook.*` 事件推得每個 surface 的狀態（啟動時重播保留的事件、摺疊成一份 snapshot），讀畫面、傳送、按鍵、聚焦到確切的 surface。cmux 原本的側欄狀態、通知、session 還原都不受影響。cmux 沒開時這個來源離線，且任何呼叫都不會把 cmux 啟動起來。

**Blocked by:** 19

**Status:** resolved

- [x] 事前驗證：真正的權限 prompt 會產生哪些事件（實測為 `agent.hook.PermissionRequest`，帶 session_id）、`send`／`send-key` 被拒絕時的 exit code 與訊息（`Error: <code>: <message>`，exit 1）
- [ ] CLI 是否會在 cmux 沒開時把它啟動：未實測（需關閉 cmux）；以 cmux 是否執行中做為所有呼叫的前提，不會在 cmux 關閉時呼叫
- [ ] `AskUserQuestion` 提問：依 `PreToolUse` 的 tool_name 判斷，尚未用真實提問驗證
- [x] 只用 `agent.hook.*`（不用重複的 `feed.item.*`）；`SubagentStop` 不把主 agent 標成 Done；跨 `boot_id` 的歷史不沿用；以 hook 的 `_ppid` 判斷程序是否仍在（改以 pid 而非 `surface.list` 過濾）
- [x] 重播的歷史摺疊成 snapshot，不觸發通知或特效
- [x] 讀畫面 `read-screen --scrollback`、傳送 `send --paste` ＋ Enter、按鍵 `send-key`、聚焦 `surface.focus`；不使用 `--cursor-file`，結束時關閉 `cmux events` 子程序
- [x] 確認 cmux surface 與 herdr CLI／herdr-core 的 agent 不會重複出現（以 pid 等鍵去重）
- [x] 解碼、重建規則有測試；只操作自己建立、`--focus false` 的 surface

## Comments

- 2026-11-10（agent）：`CmuxAdapter`＋`CmuxSessions`：`cmux events --snapshot` 取得保留範圍，子程序 `cmux events --after … --reconnect` 重播歷史後發一份 snapshot（不觸發通知），之後比對成事件；cmux 關閉時終止子程序、來源離線，且不呼叫任何 cmux 指令。實測發現 herdr server 從 cmux surface 啟動，herdr 的 Claude 也會以同一個 surface 回報 hook，所以改以 `session_id` 識別，並用 sysctl 讀取 `_ppid` 程序環境，排除屬於 herdr／herdr-core 的 session。`Notification` 只在 workspace 側欄為 Waiting 時才算 Needs you，否則視為閒置提醒（cmux 遮掉了 notification 類型，真正的權限 prompt 尚未實際觀察到）。按鍵：`send-key` 不認得數字，單一字元改用 `send` 打字。已對你 cmux 裡的 dotfiles Claude 實測顯示與讀輸出；聚焦、送字、按鍵在自建的測試 workspace 驗證後已刪除。
- 2026-11-10（agent，更正）：權限判斷改為 `PermissionRequest` → Needs you · Permission，`Notification` 維持原狀態，不再參考 workspace 側欄（同一 workspace 會有 herdr 的 session 共用，會誤判）。在自建的 cmux workspace 以 manual mode 的真實 Claude 驗證：app 傳送 → 權限 prompt → 顯示 Needs you · Permission → 面板按「1」→ 指令執行、轉為 Done。agent 改以程序 pid 識別，`/clear` 後仍是同一個角色。Claude Code 在 cmux 的畫面（右側面板、statusline 圖形、context 統計、快捷鍵列、回合摘要、橫幅）由 Messages only 過濾。cmux 裡的 Codex 尚未實際觀察。
