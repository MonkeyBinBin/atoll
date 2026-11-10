# 12: 中斷目前任務

**What to build:** 互動面板提供 `Interrupt current task` 按鈕；第一次按下變成 `Press again to confirm`，1.5 秒內再按才真正中斷，否則恢復原狀。中斷後顯示一次性回饋 `Interrupted · stopped／exited／still working／unknown`，之後回到 Herdr 回報的實際狀態。UI 上不出現結束 session、kill 或移除。

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] 只有在 1.5 秒內第二次按下才發出 interrupt 指令（有 fake client 測試）
- [ ] 四種中斷結果都有對應的一次性回饋
- [ ] 回饋結束後狀態由 Herdr 事件決定，不殘留「已中斷」狀態
- [ ] 介面上沒有任何結束或刪除 session 的操作
