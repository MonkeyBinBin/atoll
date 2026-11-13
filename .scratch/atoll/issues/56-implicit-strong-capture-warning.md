# 56: 消除 `ImplicitStrongCapture` 編譯警告

**What to build:** release build 目前唯一的警告來自 `AgentStore.refreshSpaces()`：外層 `Task { [client] in … }` 隱式強捕捉 `self`，內層排程 `spaceTimer` 的 closure 卻寫 `[weak self]`，Swift 6 提示兩層的 ownership 不一致（`ImplicitStrongCapture`）。釐清這段該用哪一種捕捉，改成一致的寫法讓警告消失，行為不變。

**Blocked by:** —

**Status:** resolved

- [x] 決定外層 `Task` 與內層 timer closure 的捕捉方式並寫一致：外層在 `client.spaces()` 回來前持有 store 是否可接受（store 與 app 同生命週期），內層 timer 是否需要 weak 以免週期性重新排程讓 store 無法釋放；結論寫在程式碼註解或本 issue Comments
- [x] `swift build -c release` 沒有任何警告
- [x] 空間的定期重新讀取行為不變（讀取失敗保留上次結果、`spaceRefreshAgain` 的補讀、`spaceGeneration` 過期丟棄）；既有 space 相關測試全數通過

**Out of scope:** 其他 closure 的捕捉方式稽核、調整空間重新讀取的間隔或流程。

## Comments

- 2026-11-13（agent）：以 `touch` 全部原始碼後的 `swift build -c release` 確認，整個專案只有這一個警告（`AgentStore.swift` 的 `spaceTimer` closure）。
- 2026-11-13（agent）：外層 `Task` 改為明確的 `[weak self, client]`，讀取回來後 `guard let self`（與 `spaceGeneration` 檢查合併）；內層 timer 維持 `[weak self]`。理由：`AgentStore` 裡 scheduler 排程的 closure 一律 `[weak self]`（8 處），讓外層跟著用 weak 最一致；store 跟 app 同生命週期，實際上不會在讀取途中釋放，store 若已釋放則丟棄結果，不影響行為。註解寫在該 `Task` 上。`swift build -c release` 零警告，全套 511 個通過。
- 2026-11-13（使用者）：安裝後實測 space 顯示與更新正常。
