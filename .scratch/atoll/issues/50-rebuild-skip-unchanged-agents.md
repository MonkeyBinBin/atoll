# 50: rebuild 沒有變化時不重新賦值 agents

**What to build:** `AgentStore.rebuild()` 幾乎每個事件都會跑，結尾無條件 `agents = built`；`agents` 是 `@Observable` 狀態，每次寫入都讓動態島、清單、面板重新 render。比照 `timeline` 的作法，只有內容不同才寫入。

**Status:** resolved

- [x] `built == agents` 時不寫入（`Agent` 已是 `Equatable`）
- [x] 行為不變，既有測試通過

## Comments

- 2026-11-13（agent）：`if built != agents { agents = built }`。全套 468 個通過。效益與 48 一起量測，沒有單獨拆開。
