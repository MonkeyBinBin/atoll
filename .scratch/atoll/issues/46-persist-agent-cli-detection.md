# 46: 偵測到的 agent CLI 存到磁碟，重開 app 不用等偵測

**What to build:** 啟動表單偵測已安裝的 agent CLI（`AgentCLIDetector`），結果只存在記憶體（`lastKnown`）。每次重開 app 後第一次開表單，tool 清單與 Recent／preset 的套用都要等一次完整的 login shell 偵測（最多 5 秒）。把上次成功的偵測結果存到 UserDefaults，啟動時先用它，背景照常刷新。

**Status:** resolved

- [x] `AgentCLIDetector` 可帶入上次存的結果當 `lastKnown`；每次偵測成功就寫回（只存 command 名稱，對回 `AgentCLI.catalog`，catalog 已移除的忽略）
- [x] 表單第一次開啟時直接走「有快取」路徑：立即顯示、背景刷新、recipe 的 CLI 不在快取時等刷新（沿用現有 `refreshing` 規則）
- [x] 規則放在 AtollCore，有測試（存取用可注入的 storage，不碰真的 UserDefaults）

**Out of scope:** 讓使用者自訂 CLI 清單、定期在背景重新偵測。

## Comments

- 2026-11-13（agent）：TDD 完成。`AgentCLIDetector` 加 `saved`（上次的 command 名稱，對回 catalog、依 catalog 排序，已移除的忽略）、`onDetected`（偵測成功且結果與 `lastKnown` 不同時交出 command 名稱）、可注入的 `detect`；拿掉 `shared`，改由 `IslandModel.agentCLIDetector` 持有，`AppDelegate` 用 `AppSettings.detectedAgentCLIs`（UserDefaults `detectedAgentCLIs`）建立。表單只改了取得 detector 的那一行：有存檔時 `lastKnown` 一開始就有值，直接走快取路徑。測試只在 detector seam（`AgentCLITests` 5 個），全套 451 個通過。AppSettings 讀寫與表單「重開 app 後立即顯示」未手動驗證。
- 2026-11-13（agent）：手動驗證：開表單後 UserDefaults 寫入 `detectedAgentCLIs`，值為 `(opencode)`（Copilot CLI 已不在本機，偵測結果正確），重開 app 再開表單時 OpenCode 立即出現。
