# 42: 依 Herdr space 分組

**What to build:** Herdr GUI 用 space 把 tab／terminal 分組（`herdr-app ls` 的 `spaces[].tabs[].terminals[]`，含 `sub_agents`）。Atoll 目前只在啟動表單用到 space。改成每個 agent 知道自己在哪個 space：清單依 space 分段，動態島可以切換「目前 space」只顯示該 space 的角色。不在任何 space 的 agent（cmux、herdr CLI、在其他終端機用 `hc run` 且沒有 pane 的）歸到「Other」。

**Blocked by:** —

**Status:** resolved

- [x] `HerdrSpace` 帶上該 space 的 terminal 位址（含 sub-agent）；`CoreRPCAdapter.spaces()` 從 `herdr-app ls` 解析，其他 adapter 照舊回空
- [x] `AgentStore` 保存 spaces，`Agent` 帶 `spaceID`／`spaceName`（只對 herdr-core 來源的 agent 對應）。更新時機：Herdr app 開啟時、出現還沒對應到 space 的新 agent 時（每個位址只觸發一次）、Herdr app 執行中每 15 秒一次（space 改名、pane 搬移沒有事件）。Herdr app 沒開時清空，所有 agent 歸 Other。`herdr-app ls` 失敗保留上一次結果
- [x] 清單：至少一個 agent 有 space 時依 space 分段、段落有標題（space 名稱與數量）；段落順序依段內最優先的 agent（等待使用者／錯誤所在的 space 排最前），段內順序同現在。沒有任何 space 時維持現在的平鋪清單。`↑↓`、`⌘1`–`⌘9`、`⌘Y`／`⌘N` 依畫面上的順序
- [x] 動態島切換：清單頂端一列 All／各 space／Other，點選設定目前 space；清單內 `Tab`／`⇧Tab` 輪替。只影響收合的動態島，清單永遠顯示全部。選了 space 時收合列只顯示該 space 的角色，**其他 space 的 Needs you／Error 仍顯示在左翼**；右翼前面顯示 space 名稱與被藏起來的數量（「atoll +3」）。選擇記在 UserDefaults；選的 space 在 Herdr 裡已經不存在時回到 All
- [x] 全螢幕規則（ticket 既有的 FullScreenPresence）套在 space 過濾之後
- [x] Hover card 的路徑列附上 space 名稱
- [x] 測試放在 AtollCore：`herdr-app ls` 解析（含 sub-agent、缺 name）、store 對應與更新時機（新 agent 觸發一次、Herdr app 關掉清空、失敗保留）、分段順序、動態島過濾（含跨 space 的 attention）

**Out of scope:** 在 Atoll 裡建立／改名／刪除 space、把 agent 搬到別的 space、Herdr 的 tab 層級、啟動表單預設 space 跟著目前 space、通知依 space 過濾（泡泡跟著收合列，被藏起來的角色不冒）。

## Comments

- 2026-11-12（agent）：`HerdrSpace` 加 `terminals`，`CoreRPCAdapter.spaces(inHerdrAppLs:)` 解析每個 space 的 terminal（含 sub-agent），`terminalsShown` 改用同一個解析。實測 Herdr 0.1.14 的 `sub_agents` 是位址字串陣列（`["t6f"]`），不是先前測試假設的物件；兩種都接受。這也修掉 `terminalsShown` 漏掉 sub-agent 的問題（「Open in Herdr」對 sub-agent 會多做一次 `terminal.keep`）。
- 2026-11-12（agent）：`AgentStore.spaces` 與 `refreshSpaces()`：`herdrAppRunning` 變 true 時讀一次，之後每 `spaceRefreshInterval`（15 秒）一次；rebuild 發現 herdr-core agent 沒有 space 時觸發一次（`spaceMisses` 記住，每個位址只觸發一次）；讀取中又有要求就讀完再讀一次；失敗保留上一次；Herdr app 關掉時 generation 遞增、清空、停 timer。純邏輯在 `SpaceGrouping`（分段、清單順序、動態島過濾、可選項、失效回到 All）與 `SpaceFilter`（UserDefaults `islandSpace`：空字串 = All、`@other`、space id）。
- 2026-11-12（agent）：UI：`IslandModel.listAgents` 是清單順序，selection／`⌘1`–`⌘9`／`⌘Y`／`⌘N` 都改用它；`collapsedAgents` 先套 space 過濾再套全螢幕規則；泡泡本來就看 `showsInCollapsedIsland`，被藏起來的角色自然不冒。Island 列只在可選項超過一個 space（或過濾還開著）時出現。Debug hook 加 `space <id|all>`、`tab`。
- 2026-11-12（agent）：測試：`SpaceTests` 11 個（對應、新 agent 觸發一次、計時重讀與失敗保留、Herdr app 關掉、分段順序、過濾含跨 space attention、失效、可選項、stored 往返）＋ `WireDecodingTests` 1 個；全套 404 個通過。實測：dev-run 對本機 Herdr（3 個 space）用 `hc run --bg claude` 開一個閒置 agent，它被 Herdr 掛成 t5c 的 sub-agent，清單正確歸在「atoll 2」；切到沒有 agent 的 dotfiles，收合列顯示「dotfiles +2」、角色全藏；`Tab` 依序 dotfiles → All → atoll。跨 space 的 Needs you 只有單元測試，沒有實機觸發。
