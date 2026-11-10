# 14: 通知

**What to build:** agent 轉為 Needs you 或 Error 時發 macOS 通知；Done 通知預設關閉，可在設定依 agent 或專案打開；Working 永不通知。通知內容只有「工具 · 專案名」，不含輸出。點通知直接打開該 agent 的互動面板。設定中有通知總開關。

**Blocked by:** 03, 09

**Status:** ready-for-agent

- [ ] 通知觸發規則（哪些狀態轉換會通知）有 fake client 測試
- [ ] 通知內容不含終端機輸出或任務內容
- [ ] 點通知打開對應 agent 的面板，而不是總清單
- [ ] 設定中可開關全部通知，以及依 agent／專案開啟 Done 通知
- [ ] 同一次狀態轉換不重複通知
