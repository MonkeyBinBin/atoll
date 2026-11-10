# 03: Menu bar 與設定視窗骨架

**What to build:** menu bar icon 提供 Show/Hide Island、Settings…、Quit；設定視窗顯示 Herdr 連線狀態，可手動 Reconnect，啟動時檢查 `hc`／core 版本並在不相容時提示。之後各 ticket 的開關都加在這個設定視窗。UI 文字使用英文。

**Blocked by:** 01

**Status:** resolved

- [x] menu bar icon 可開關動態島、打開設定、結束程式
- [x] 設定視窗顯示連線狀態（connected／disconnected）與 core 版本
- [x] Reconnect 會重新建立 socket 與事件訂閱
- [x] 版本不相容（以 `rpc.discover`／版本資訊判斷）時顯示明確提示
- [x] `AgentStore` 的連線狀態有 fake client 測試

## Comments

- 2026-11-10（agent）：Menu bar（badge＝等待數、Show/Hide Island、Settings…、Quit）與設定視窗（連線狀態、core 版本、Reconnect、相容性警告）。相容性以 `hello` 的 generation＋必要 methods 判斷（`AgentStore.compatibilityProblem`）。
