# 20: herdr CLI（TUI）後端

**What to build:** 讀取 `herdr`（0.9.x，socket `~/.config/herdr/herdr.sock`）管理的 agent：狀態（idle／working／blocked／done／unknown）、近期輸出、傳送 prompt、按鍵、中斷、在 herdr 內聚焦。herdr 沒在跑時這個來源安靜地離線，不影響其他來源。

**Blocked by:** 19

**Status:** resolved

- [x] 事前驗證：`events.subscribe` 的連線與事件格式、`pane.updated` 是否在狀態變化時觸發、target 是否接受 `terminal_id`、blocked 時如何回答（`agent.prompt` 會以 `agent_blocked` 拒絕）
- [x] 狀態以 `agent.list` 為準（事件觸發即時刷新，另有慢速輪詢當心跳），對映到使用者可見狀態
- [x] 讀輸出 `agent.read`、傳送 `agent.prompt`、按鍵 `agent.send_keys`；中斷送 esc，結果回報 unknown；傳送無法確認是否開始，回報 Sent · unconfirmed
- [x] `Open in Herdr` 對這個來源改為 herdr 的 `agent.focus`，並在 UI 說明只會切換 herdr 內的 pane
- [x] 錯誤 `{code, message}` 對映為 `HerdrError`
- [x] 解碼與狀態對映有測試；只操作自己建立的 pane

## Comments

- 2026-11-10（agent）：`HerdrCLIAdapter`：ping／`agent.list` 輪詢（2 秒）加 pane 事件訂閱即時刷新，前後兩次清單比對成 created／status／turn／removed 事件。實測：`events.subscribe` 連線保持開啟；狀態變化不觸發 `pane.updated`；target 不接受 `terminal_id`，故位址用 terminal_id、指令時對應回 pane_id；`agent.*` 指令會拒絕非真實 agent，讀輸出／按鍵／回答 blocked 改用 `pane.*`，一般傳送用 `agent.prompt`。blocked 沒有 kind，面板同時提供強制文字回覆與按鍵排（新 `ReplyMode.textAndKeys`）。中斷送 esc 並回報 unknown；傳送回報 Sent · unconfirmed。已對你 herdr 裡的 claude／codex 實測顯示與讀輸出，傳送只在自建的測試 workspace 驗證過。
- 2026-11-10（agent，補充）：在自建的 herdr workspace 以 manual mode 的真實 Claude 驗證：app 以 `agent.prompt` 傳送 → 權限 prompt → Needs you（文字＋按鍵面板）→ 按「1」（`pane.send_keys`）→ 指令執行、轉為 Done。沒有時間戳的狀態不再顯示「從 app 啟動起算」的持續時間；`Open in herdr` 下方顯示「只切換 herdr 內的 pane」。
