# 43: 啟動表單預設開在目前的 space

**What to build:** ticket 42 讓動態島可以切到單一 Herdr space，但啟動表單的 Space 仍然只看 Settings 的 Default space（空白 = Herdr 目前選的 space）。切到某個 space 後新開的 agent 常常落在別的 space，馬上又被動態島藏起來。表單打開時的預設 space 改成跟著目前的情境。

**Blocked by:** 42

**Status:** resolved

- [x] 表單打開時的 Space 依序取：從 agent 的「Launch in new worktree」進來時該 agent 的 space → 動態島目前選的 space（`SpaceFilter.space`；All／Other 不算）→ Settings 的 Default space → Selected space
- [x] 取到的 space 不在 Herdr 目前的 spaces 裡時照舊回到 Selected space；Recent／preset 帶回的 space 照舊覆蓋（ticket 37 的規則不變）
- [x] 預設來自動態島或 agent 時，Space 欄位旁標示來源（「from island」／「same as agent」），手動改就不再標示
- [x] 規則放在 AtollCore（`SpaceGrouping.launchSpace`），測試涵蓋三層優先順序與 All／Other 不算

**Out of scope:** Settings 的 Default space 改成下拉選單、Recent 紀錄的 space 規則、記住手動改過的 space。

## Comments

- 2026-11-12（agent）：`SpaceGrouping.launchSpace(agentSpace:island:defaultSpace:)` 回傳起始 space 與來源（agent／island／settings）。`LaunchPrefill` 加 `space`，`openLaunchInWorktree` 帶入該 agent 的 `spaceID`。表單 `load()` 用它決定 `space`，記下 `startingSpace` 與 `spaceOrigin`；Space 選單右邊在值仍等於起始值時標「from island」／「same as agent」，手動改掉就不顯示。Recent／preset 帶回時清掉來源；space 不在 Herdr 清單裡照舊回 Selected space（既有邏輯，標示跟著消失）。動態島的過濾用 `model.spaceFilter`（已處理失效回 All）。
- 2026-11-12（agent）：測試：`SpaceTests.launchSpace`（三層優先、All／Other 不算、空字串 agent space 不算）；全套 405 個通過。實測：動態島切到 atoll 後打開表單，Space 為 atoll 並標「from island」；切回 All 再打開為 Selected space、無標示。「same as agent」路徑只有單元測試（需要共用 working tree 的情境才有按鈕）。
