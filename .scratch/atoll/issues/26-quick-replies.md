# 26: 快速回覆

**What to build:** 互動面板的輸入框下方顯示一排快速回覆按鈕，點一下就把那段文字送給 agent。預設三個：`continue`、`yes, go ahead`、`run the tests`，可在設定中新增、刪除、改文字與排序，最多 5 個。`⌘⇧1`–`⌘⇧5` 對應第 1–5 個。⌥-點擊不直接送出，而是把文字放進輸入框讓你修改。

**Blocked by:** —

**Status:** resolved

- [x] 只在可以打字回覆時顯示（reply mode 為 `.text` 或 `.textAndKeys`）；permission（只有按鍵）、Sign-in required、Exited 不顯示
- [x] 送出走與輸入框相同的 `AgentStore.send`：送出狀態一樣顯示 Delivered／Agent started／Sent · unconfirmed／Failed，永不自動重送；對 Needs you 的 agent 送出時，一樣會觸發自動跳轉（ticket 23）
- [x] 送出進行中時按鈕停用；輸入框裡的草稿不受影響，快速回覆只送按鈕自己的文字
- [x] ⌥-點擊：把文字放進輸入框並聚焦，不送出；輸入框原本有字時取代掉
- [x] 快捷鍵用 keyCode 比對（按住 Shift 時字元會變成 `!` 等符號，且要不受鍵盤配置影響）；不影響既有的 `⌘1`–`⌘9`（跳 agent）與 `⌘]`
- [x] 按鈕上顯示文字（過長時截斷）與對應的快捷鍵；help 顯示完整文字
- [x] 設定：Settings 新增「Quick replies」區塊，可編輯清單；存入 `UserDefaults`，空白項目與重複項目在儲存時剔除；清空後面板不顯示這一排
- [x] 清單的整理規則（trim、剔除空白與重複、最多 5 個、沒存過時給預設值）放在 AtollCore，並有測試

**Out of scope:** 依 agent／專案／工具設定不同清單、含變數的範本、從歷史訊息自動產生。

## Comments

- 2026-11-11（agent）：清單規則放在 AtollCore 的 `QuickReplies`（`normalize`：trim、剔除空白與重複、最多 5 個；`resolve`：沒存過時用預設值，存了空清單就維持空白），`AppSettings.quickReplies` 存整理後的結果。面板在輸入框下方顯示按鈕：點擊走 `sendQuickReply`，跟輸入框共用 `AgentStore.send` 與 `lastSent`（失敗時 Resend 可用），不動草稿；⌥-點擊把文字放進輸入框並聚焦。`⌘⇧1–5` 在 `IslandController` 以 keyCode（18、19、20、21、23）比對，經 `IslandModel.requestQuickReply` 交給面板，走同一條送出路徑。按鈕依文字寬度排列，超過 28 字截斷，help 顯示完整文字。設定的「Quick replies」區塊以有穩定 id 的列編輯（新增空白列時不會被立刻剔除，刪除或排序時 binding 也不會失效），每次變更存入整理後的清單。DebugHook 的 `post` 可加 `shift`。`QuickRepliesTests` 3 個測試，全套 160 個通過。
- 2026-11-11（agent）：dev-run 實測（測試 agent 停在 Needs you · Question）：預設三顆按鈕與快捷鍵標示正確；長文字截斷為「run the tests and fix any f…」，但送出的是完整內容；`⌘⇧2`、`⌘⇧3`、點擊各送出一次，terminal 都收到；送出進行中按鈕停用；有草稿時用 `⌘⇧1` 送出，草稿保留。⌥-點擊（合成事件無法帶出 `NSEvent.modifierFlags` 的 Option 狀態）與設定畫面的編輯操作（區塊在視窗下方，debug hook 截不到）改由使用者對假的 Question agent 手動實測，未回報問題。
- 2026-11-11（agent）：依使用者要求，預設值改為中文：`繼續`、`照你的建議做`、`跑測試，失敗就修到通過`（原為 `continue`、`yes, go ahead`、`run the tests`）。
