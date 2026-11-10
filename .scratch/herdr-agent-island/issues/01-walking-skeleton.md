# 01: Walking skeleton：動態島顯示 agent 與文字狀態

**What to build:** 啟動 menu bar app 後，它連上本機 herdr-core socket 並訂閱事件；螢幕頂部出現一個基本的浮動膠囊（`NSPanel`），每個 agent terminal 顯示一個圓點與原始狀態文字，狀態變化即時更新。這張建立 `HerdrClient` 介面、`CoreRPCAdapter` 實作、最小的 `AgentStore`，以及第一個以 fake `HerdrClient` 驅動的 Swift Testing 測試，作為後續所有 ticket 的骨架。UI 文字使用英文。

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Swift + SwiftUI 專案建立，最低 macOS 15，以 menu bar app（無 Dock icon）形式執行
- [x] `CoreRPCAdapter` 透過 Unix socket 以 JSON-RPC 連上 core，訂閱事件串流並處理 snapshot 與 status 事件
- [x] `AgentStore` 只依 `HerdrClient` 介面運作，不直接接觸 socket
- [x] 浮動膠囊不搶焦點、位於螢幕頂部中央、層級高於一般視窗
- [x] 本機有 agent 在跑時，每個 terminal 顯示一個圓點與英文狀態文字，狀態改變時更新
- [x] 至少一個 fake `HerdrClient` 注入事件序列、驗證 `AgentStore` 輸出的測試通過

## Comments

- 2026-11-10（agent）：SwiftPM 專案（`IslandCore` 函式庫＋`HerdrIsland` app＋`IslandCoreTests`），`scripts/build-app.sh` 打包成 LSUIElement 的 `build/Herdr Island.app`。`CoreRPCAdapter` 走 Unix socket JSON-RPC，訂閱專用連線＋每個指令一條短連線。圓點已在 06 換成像素角色。
