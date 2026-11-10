# 05: 完整狀態模型

**What to build:** 動態島上的每個 agent 依 spec 的狀態對映表顯示正確的使用者可見狀態（Starting / Working / Needs you / Done / Idle / Error / Exited / Unknown），依優先級排序；斷線或資料過期時全部轉為 Unknown，膠囊轉灰並顯示 `Herdr offline · Last updated hh:mm`。預設只顯示有回報 `status.app` 的 terminal，設定中可打開「Show terminals without status」。

**Blocked by:** 01, 03

**Status:** ready-for-agent

- [ ] 狀態對映涵蓋 spec 表格每一列，含 blocked kind（Question / Permission / Sign-in required）
- [ ] 超過 heartbeat 期限未收資料 → 全部 Unknown；收到 `missed` → 以新 snapshot 重建
- [ ] socket 斷線 → 膠囊轉灰、顯示最後更新時間，agent 保留不移除；重連後自動重新同步
- [ ] 排序：Needs you > Error > Unknown > Working > Done > Idle > Exited；Needs you 同級依開始等待時間由早到晚
- [ ] `status.app` 過濾與設定開關，關閉時未回報的 terminal 不出現，打開時以 Unknown 顯示
- [ ] 本機記錄每個 agent 的 Last status change 時間
- [ ] 以上每條規則都有 fake client 測試
