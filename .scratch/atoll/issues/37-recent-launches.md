# 37: 最近啟動與啟動範本

**What to build:** 啟動表單記住最近幾次的「工具＋目錄＋任務（＋名稱、space、是否 New worktree）」組合，一鍵帶回或直接重新啟動；也能把常用組合存成範本（例如「在 X 專案跑 review」）。目前表單只記最近目錄（`recentFolders`），每次都要重選工具、重打任務。這裡的「範本」是 Atoll 自己的表單預設，與 herdr-core 的 template（`templates.list`，會出現在工具選單）是兩回事，UI 用詞要分開（例如叫「Presets」）。

**Blocked by:** —

**Status:** resolved

- [x] 最近啟動：每次成功送出（狀態到 Launched 或 unconfirmed，不含 failed）記一筆：工具 option id、使用者選的目錄（不是 worktree 路徑）、任務全文、名稱、space、New worktree 開關；最多 10 筆，相同組合（工具＋目錄＋任務）只留最新一筆
- [x] 表單頂端多一個「Recent」選單：每筆顯示「工具 · 目錄名 · 任務前 40 字」；選了只填入表單，不直接啟動。另提供「Launch again」（`⌘R`，針對最近一筆）直接用同樣的組合送出，送出前一樣顯示確認摘要（表單填好、聚焦在 Launch 按鈕，不跳過確認）
- [x] 帶回時的檢查：目錄不存在就不填目錄並提示；工具是已不存在的 herdr template 就改回預設工具並提示；New worktree 只在目錄仍是 repo 時開啟，branch 一律重新產生（不沿用舊 branch，避免撞名）
- [x] Presets：表單上「Save as preset…」把目前的組合存成具名 preset（名稱必填，最多 20 個）；表單頂端的選單列出 presets，選了填入表單。Settings 新增 Presets 區塊可改名、刪除、調整順序
- [x] 儲存：最近啟動與 presets 都存在 `UserDefaults`（同 `recentFolders`），任務文字會被寫入磁碟，所以 Settings 提供「Clear recent launches」，並在 README 隱私段落註明「啟動表單的最近紀錄與 presets 會存在本機 UserDefaults」
- [x] 選單內容只來自本機紀錄，不讀 agent 的畫面或輸出
- [x] 紀錄的增刪、去重、上限與帶回時的檢查放在 AtollCore（或 App 層可測試的 model），單元測試：去重、上限、failed 不記、目錄消失、template 消失、worktree 開關的處理

**Out of scope:** 跨機器同步、匯入／匯出 presets、一次啟動多個 agent、排程啟動。

## Comments

- 2026-11-12（agent）：AtollCore 新增 `LaunchHistory.swift`：`LaunchRecipe`（option id、使用者選的目錄、任務、名稱、space、worktree，Codable，branch 不存）、`LaunchPreset`（id、名稱、recipe）、`LaunchHistory`（`recording`：最新在前、工具＋目錄＋任務相同只留最新、最多 10 筆；`adding`／`renaming`／`deleting`／`moving`：名稱必填、最多 20 個、空白名稱不改名、兩端移動無效；`restore`：目錄不存在留空、工具不存在改回預設工具（template 與內建工具、template 清單載入失敗各有不同提示）、space 不存在改回 Selected space，各附一句提示；worktree 意願保留給表單判斷；`templateName(of:)`）。`AgentStore.onLaunchFinished(succeeded:)`：`launchState` 從 starting 轉 launched 或 unconfirmed 時回報成功一次，轉 failed（含 worktree 建立失敗、Herdr 沒開）時回報失敗。
- 2026-11-12（agent）：App：`AppSettings.recentLaunches`／`launchPresets` 以 JSON 存在 UserDefaults；表單送出時把目前組合放在 `IslandModel.pendingLaunchRecipe`，AppDelegate 在 `onLaunchFinished` 時清掉它、成功才記錄（失敗留著的話，之後別的成功啟動會把它記下來）。worktree 只記實際生效的（有 worktree plan 才算），否則預填過的 `worktree: true` 會被記下來。表單右上角「Recent」（選了只填入；清除只放在 Settings）、「Presets」（列出 presets，底部「Save as preset…」開一列輸入名稱）、「Launch again」（`⌘R`，填入最近一筆並把焦點移到 Launch，不跳過確認）。帶回時：template 清單還在載入就先暫存，載入後才套用，避免把有效的 template 當成不存在；New worktree 等目錄的 repo 檢查回來才決定（目錄不變且已檢查過時直接用結果；使用者自己改目錄或勾選時取消待套用的值），branch 清掉重新產生；使用者改工具或目錄時清掉提示。Settings 的 preset 名稱按 Return 或點離開都會存，空白名稱恢復原名。`AppSettings` 的 JSON 存取改成共用的泛型 `save`／`load`（hotkey 也用）。Settings 新增「Launch presets」區塊（改名、上下移、刪除、Clear recent launches 與 UserDefaults 說明）。
- 2026-11-12（agent）：測試：紀錄規則 11 個（去重、上限、選單標題、presets 的新增上限與改名／刪除／排序、目錄消失、template 消失、template 清單載入失敗與未知內建工具、space 消失、template 名稱、全部存在時原樣帶回、JSON round-trip），store 1 個（Launched 與 unconfirmed 回報成功、啟動失敗與 worktree 失敗回報失敗），全套 357 個通過。「只在 repo 時開啟 New worktree、branch 重新產生」在表單 view 裡，沒有單元測試。dev-run 實測：從表單啟動 Claude Code 後 UserDefaults 出現一筆紀錄；重開表單按 `⌘R` 填回工具、目錄與任務、沒有自動啟動；寫入一筆指向不存在目錄與 template 的紀錄，`⌘R` 後目錄留空、工具改回 Claude Code，摘要下方顯示兩句提示。code review 後重測：開表單同時按 `⌘R`，提示仍是 template 不存在（等清單載入後才判斷）。Settings 的 Presets 區塊只有編譯確認，沒有實際點過改名與排序；`⌘R` 後把焦點移到 Launch 按鈕在沒開「完整鍵盤操作」時不會生效，確認仍靠 `⌘↩`。
