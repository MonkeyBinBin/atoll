# 04: Adapter 契約測試＋驗證 4 項事實

**What to build:** 一組可手動執行的契約測試，讓 `CoreRPCAdapter` 對本機真實 herdr-core 驗證 schema、事件順序與錯誤格式；並用它確認 spec「開工前要先驗證的事實」4 項，把結果寫回 spec，讓後續 ticket 知道該走確認或無法確認的路徑。

**Blocked by:** 01

**Status:** resolved

- [x] 契約測試預設不跑，以明確方式手動觸發；core 未執行時清楚跳過
- [x] 只做唯讀操作，或只操作測試自己建立、自己清除的 terminal
- [x] 驗證 terminal list／get、事件串流（snapshot、status、heartbeat）、read、send、keys、interrupt 的回傳結構符合 adapter 的解碼
- [x] 確認並記錄：Codex（`codex --no-daemon`）是否回報 OSC 7501 狀態
- [x] 確認並記錄：`herdr-app do agent.focus` 是否把 Herdr 視窗帶到前景
- [x] 確認並記錄：`herdr-app do tab.new --task` 是否回報初始任務已送出
- [x] 確認並記錄：是否有 RPC 能把「已看過」寫回 Herdr
- [x] 結果更新到 spec 的「開工前要先驗證的事實」段落

## Comments

- 2026-11-10（agent）：契約測試 `Tests/AtollCoreTests/ContractTests.swift`，`HERDR_CONTRACT=1 swift test --filter Contract` 手動觸發；core 未執行時整組 skip；只操作自建（no_parent/no_notify）並自行清除的 probe terminal。4 項事實結果已寫回 spec。
