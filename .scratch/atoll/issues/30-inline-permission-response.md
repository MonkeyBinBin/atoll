# 30: 清單與 hover card 直接回應 permission

**What to build:** 清單裡 Needs you 的 permission 列，在等待原因預覽（ticket 27）旁邊提供「Allow」「Deny」，按快捷鍵或點按鈕就送出對應按鍵，不用打開面板。目前看完預覽還是要 `Enter` 進面板、再點按鍵排（ticket 11），三步才能回一個 permission。

**Blocked by:** —

**Status:** resolved

- [x] 按鍵對應從畫面上的選項推出，不寫死：擷取 permission 對話框的編號選項（Claude Code 的 `1. Yes`／`2. Yes, and don't ask again…`／`3. No…`，Codex 的對應版面），Allow 對應第一個「Yes」選項的按鍵，Deny 對應「No」選項的按鍵（例如 `esc`）。實作前先用真的 Claude Code、Codex 觸發對話框並更新 fixture，確認目前版本實際的選項與按鍵
- [x] 只有 `WaitingPreview` 認得版面、也擷取到選項時才顯示 Allow／Deny；herdr-core `status.msg` 有原因但沒讀過畫面時，在轉為 Needs you 時照 ticket 27 的規則讀一次畫面來取得選項。認不得就不顯示，維持進面板
- [x] 「Yes, and don't ask again」不提供捷徑，要用的話進面板
- [x] 快捷鍵：清單選取列 `⌘Y` = Allow、`⌘N` = Deny；hover card 顯示兩個按鈕。按下前列上一直看得到完整的預覽（工具＋指令），不能在看不到指令的地方核准
- [x] 送出前再確認一次狀態：agent 已經不是 Needs you，或 `waitingSince` 已經換成新的 episode，就不送，並顯示「No longer waiting」，避免按鍵送進下一個對話框
- [x] 送出結果沿用 `pressKey` 的回饋（成功／錯誤 kind），顯示在列上，不自動重送。成功後照常交給 ticket 23 的自動切換規則
- [x] 選項擷取與 Allow／Deny → 按鍵的對應放在 AtollCore（擴充 `WaitingPreview` 或新增 `PermissionChoices`），用 Claude Code、Codex 的 fixture 測試：一般 permission、只有兩個選項、擷取不到選項、question（不提供）、`.auth`（不提供）；AgentStore 測試 episode 已換時不送

**Out of scope:** question 的選項直接選（選項數不固定，維持用快速回覆或面板）、批次核准多個 agent、依規則自動核准、「don't ask again」。

## Comments

- 2026-11-12（agent）：本機 Claude Code 2.1.322、Codex 0.167.0 與 ticket 27 的 fixture 版本相同，沿用既有畫面 fixture，另外在 dev-run 用真的 Claude Code 重新觸發確認版面一致。AtollCore 新增 `PermissionChoices.swift`：`PermissionChoices`（`allowKey`／`denyKey`）、`PermissionChoice`、`PermissionResponseState`。只在 `WaitingPreview` 認得版面時，從「Do you want to…」／「Would you like to…?」之後擷取連號的選項；選項結尾有 `(y)`／`(esc)` 這類單鍵就用它，否則用編號。Allow 只對應去掉快捷鍵後恰好是「Yes」或「Yes, proceed」的選項（「Yes, and always allow…」「allow all edits during this session」都不算），Deny 對應「No」開頭的選項；找不到其中一個就是 nil。結果：Claude Code `1`／`4`，Codex `y`／`esc`。
- 2026-11-12（agent）：`AgentStore`：有 `statusMessage` 時，permission／unspecified 的 Claude Code、Codex 也讀一次畫面，但只拿按鍵，不設 `waitingPreview`（清單照舊顯示 msg）；question 有 msg 時照舊不讀。`respond(_:to:episode:)` 先比對 `waitingSince`，不在同一個 episode 就不送並顯示「No longer waiting」（4 秒後消失）；送出後的結果只在同一個 episode 內顯示，離開 Needs you 就清掉；不重送。
- 2026-11-12（agent）：跟 ticket 不同：hover card 是點擊穿透的視窗（`ignoresMouseEvents`），滑鼠離開角色就消失，按鈕按不到，所以 hover card 只顯示「Allow / Deny from the list: ⌘Y / ⌘N」提示，可點的按鈕放在清單列上。清單列有按鍵時預覽 title 放寬到 2 行，完整內容在 help。
- 2026-11-12（agent）：測試：`PermissionChoicesExtractionTests`（Claude Code、Codex、unspecified、兩個選項、edit session、捲動歷史、10 種不提供）與 `PermissionResponseTests` 8 個；`WaitingPreviewStoreTests.statusMessageWins` 改用 question（permission 有 msg 現在會讀畫面）。全套 243 個通過。dev-run 實測（herdr-core、真的 Claude Code，`--permission-mode default`）：清單列顯示 Allow／Deny、按鍵 `1`／`4`；Allow → `touch` 執行；Deny → 被拒、檔案沒有建立；真的 `⌘Y` 鍵盤事件 → 執行。Codex 與 herdr CLI／cmux 來源只有 fixture 測試。
