# 26: 快速回覆

**What to build:** 互動面板的輸入框下方顯示一排快速回覆按鈕，點一下就把那段文字送給 agent。預設三個：`continue`、`yes, go ahead`、`run the tests`，可在設定中新增、刪除、改文字與排序，最多 5 個。`⌘⇧1`–`⌘⇧5` 對應第 1–5 個。⌥-點擊不直接送出，而是把文字放進輸入框讓你修改。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 只在可以打字回覆時顯示（reply mode 為 `.text` 或 `.textAndKeys`）；permission（只有按鍵）、Sign-in required、Exited 不顯示
- [ ] 送出走與輸入框相同的 `AgentStore.send`：送出狀態一樣顯示 Delivered／Agent started／Sent · unconfirmed／Failed，永不自動重送；對 Needs you 的 agent 送出時，一樣會觸發自動跳轉（ticket 23）
- [ ] 送出進行中時按鈕停用；輸入框裡的草稿不受影響，快速回覆只送按鈕自己的文字
- [ ] ⌥-點擊：把文字放進輸入框並聚焦，不送出；輸入框原本有字時取代掉
- [ ] 快捷鍵用 keyCode 比對（按住 Shift 時字元會變成 `!` 等符號，且要不受鍵盤配置影響）；不影響既有的 `⌘1`–`⌘9`（跳 agent）與 `⌘]`
- [ ] 按鈕上顯示文字（過長時截斷）與對應的快捷鍵；help 顯示完整文字
- [ ] 設定：Settings 新增「Quick replies」區塊，可編輯清單；存入 `UserDefaults`，空白項目與重複項目在儲存時剔除；清空後面板不顯示這一排
- [ ] 清單的整理規則（trim、剔除空白與重複、最多 5 個、沒存過時給預設值）放在 AtollCore，並有測試

**Out of scope:** 依 agent／專案／工具設定不同清單、含變數的範本、從歷史訊息自動產生。
