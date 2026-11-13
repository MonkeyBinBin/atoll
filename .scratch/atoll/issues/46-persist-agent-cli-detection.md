# 46: 偵測到的 agent CLI 存到磁碟，重開 app 不用等偵測

**What to build:** 啟動表單偵測已安裝的 agent CLI（`AgentCLIDetector`），結果只存在記憶體（`lastKnown`）。每次重開 app 後第一次開表單，tool 清單與 Recent／preset 的套用都要等一次完整的 login shell 偵測（最多 5 秒）。把上次成功的偵測結果存到 UserDefaults，啟動時先用它，背景照常刷新。

**Status:** ready-for-agent

- [ ] `AgentCLIDetector` 可帶入上次存的結果當 `lastKnown`；每次偵測成功就寫回（只存 command 名稱，對回 `AgentCLI.catalog`，catalog 已移除的忽略）
- [ ] 表單第一次開啟時直接走「有快取」路徑：立即顯示、背景刷新、recipe 的 CLI 不在快取時等刷新（沿用現有 `refreshing` 規則）
- [ ] 規則放在 AtollCore，有測試（存取用可注入的 storage，不碰真的 UserDefaults）

**Out of scope:** 讓使用者自訂 CLI 清單、定期在背景重新偵測。

## Comments
