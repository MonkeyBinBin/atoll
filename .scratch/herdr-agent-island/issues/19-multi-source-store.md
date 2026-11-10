# 19: AgentStore 支援多個後端來源

**What to build:** 讓 `AgentStore` 同時接收多個後端（herdr-core、herdr CLI、cmux）的事件，每個 agent 記錄它來自哪個來源，指令依來源路由到對應的 client。連線狀態、snapshot、事件序號、過期判定、相容性警告都按來源分開計算：某個後端沒在跑（例如 cmux 沒開）只影響它自己的 agent，不會讓整個動態島變灰。

**Blocked by:** 05, 09

**Status:** resolved

- [x] `handle(_:from:)` 依來源套用更新；單一來源的既有 79 個測試不需修改即通過
- [x] 一個來源的 snapshot 只取代該來源的 agent；事件序號與 snapshot 序號按來源比較
- [x] 過期計時、斷線、相容性警告按來源；該來源的 agent 才轉 Unknown；所有來源都不 live 時動態島才轉灰
- [x] 讀輸出、傳送、按鍵、中斷、聚焦依 agent 的來源路由；啟動只走 herdr-core（herdr-app）
- [x] 非 herdr-core 的位址加命名空間（`herdr:<terminal_id>`、`cmux:<surface uuid>`），個體色、通知設定、面板都以位址為鍵
- [x] 設定視窗每個後端一列連線狀態
- [x] 以上皆有 fake client 測試

## Comments

- 2026-11-10（agent）：`AgentStore(clients:)` 接受多個來源；snapshot、序號、過期計時、連線與相容性警告都按來源分開，單一來源時行為不變（既有測試不改即通過）。所有來源都不 live 時動態島才轉灰。指令依 agent 來源路由，啟動只走 herdr-core。設定視窗改為每個來源一列。新增 `MultiSourceTests`。
