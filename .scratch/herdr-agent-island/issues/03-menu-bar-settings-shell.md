# 03: Menu bar 與設定視窗骨架

**What to build:** menu bar icon 提供 Show/Hide Island、Settings…、Quit；設定視窗顯示 Herdr 連線狀態，可手動 Reconnect，啟動時檢查 `hc`／core 版本並在不相容時提示。之後各 ticket 的開關都加在這個設定視窗。UI 文字使用英文。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] menu bar icon 可開關動態島、打開設定、結束程式
- [ ] 設定視窗顯示連線狀態（connected／disconnected）與 core 版本
- [ ] Reconnect 會重新建立 socket 與事件訂閱
- [ ] 版本不相容（以 `rpc.discover`／版本資訊判斷）時顯示明確提示
- [ ] `AgentStore` 的連線狀態有 fake client 測試
