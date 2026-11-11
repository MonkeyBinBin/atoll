# 28: Done 時顯示成果摘要

**What to build:** agent 跑完一個回合（Done／Exited，或從 Working 轉為 Idle，判斷規則同 ticket 24）時，在它的專案目錄算出這個回合的變更量，例如 `+120 −30 · 6 files`，顯示在泡泡、清單列與面板標題列。用途是決定這次要不要細看，以及要細看哪一個 agent。

**Blocked by:** —

**Status:** resolved

- [x] 基準：agent 轉為 Working／Starting 時，記下 `projectPath` 所在 repo 的 `HEAD`。跑完時算基準 commit 到 working tree 的差異（`git diff --shortstat <base>`），所以 agent 自己 commit 的內容也算進去；未追蹤的新檔案另外計數（`git ls-files --others --exclude-standard`），顯示為「+N new」
- [x] Atoll 在回合中途才啟動、沒有基準時，改算 `HEAD` 到 working tree 的差異，並標示為「uncommitted」，不冒充成這個回合的變更
- [x] `projectPath` 不在 git repo 裡、git 不存在或執行失敗：不顯示摘要，也不顯示錯誤
- [x] git 在背景執行，加 timeout（例如 2 秒），不擋住狀態轉換與泡泡；超時就不顯示摘要
- [x] 沒有任何變更時顯示「no changes」，因為這本身就是有用的資訊（例如 agent 只回答了問題）
- [x] 同一個 working tree 同時有多個 agent 時，差異無法歸屬給個別 agent：摘要加註「shared tree」（與 ticket 29 一致），不假裝是這個 agent 的變更
- [x] 摘要只存在記憶體，下一個回合開始時清掉；Settings 可以關閉
- [x] 解析 `--shortstat` 與組出摘要字串的邏輯放在 AtollCore（例如 `GitProbe`／`ChangeSummary`），git 執行透過可替換的 runner，以便測試：一般 diff、只有新增檔案、沒有變更、沒有基準、非 git 目錄、超時

**Out of scope:** 測試結果（目前沒有可靠來源，不從畫面猜）、在 Atoll 內顯示 diff 內容、依檔案列出變更、PR／CI 狀態。

## Comments

- 2026-11-11（agent）：AtollCore 新增 `ChangeSummary.swift`：`ChangeSummary`（數字、基準種類、`label`／`help`、`--shortstat` 解析）、`TurnBaseline`、`ChangeProbing` 協定、`GitProbe`（透過 `GitRunner` 執行 git）與 `ProcessGitRunner`。git 一律加 `--no-optional-locks`（不搶 agent 自己 git 指令要用的 index lock），每個指令 2 秒逾時（不是整體 2 秒），只找 Homebrew／CLT／Xcode 的 git，刻意跳過 `/usr/bin/git`：沒裝開發者工具時那個 shim 會跳安裝視窗。`AgentStore.changeProbe` 為 nil 時完全不跑 git；`trackTurn` 在轉為 Working／Starting 且沒有進行中的回合時記基準，Needs you／Unknown 留在回合內，Done／Exited／結束回合的 Idle 算摘要，Error 關閉回合但不算摘要；每個 agent 有 generation，較晚回來的舊回合結果不會蓋到新回合上。
- 2026-11-11（agent）：跟 ticket 不同的地方：(1) 新增「incl. earlier edits」：回合開始時 working tree 已經有未 commit 的修改，從基準 commit 算 diff 會把它們算進去，所以照實標示。(2) 未追蹤檔案：有基準時只算這個回合新出現的（結束時的清單減掉開始時的），顯示「N new」；沒有基準時顯示全部，標「N untracked」。(3) 「shared tree」的判斷：同一個 toplevel 還有其他沒有 Exited 的 agent。toplevel 是從基準與摘要得知的，所以 Atoll 啟動後還沒開始過回合的 agent 不會被算進去；ticket 29 做好之後可以改用它的分組。(4) 泡泡只顯示數字（`text`），不顯示 caveat；`BubbleRules` 的隱私註解已同步更新。
- 2026-11-11（agent）：測試：`GitProbeTests` 8 個（含 4 種 shortstat）、`TurnTrackingTests` 10 個、`RealGitTests` 1 個（在暫存 repo 跑真的 git：agent commit 加上新檔案得到 `+2 −1 · 1 file · 1 new`），全套 183 個通過。dev-run 實測：用 `hc run --bg` 在暫存 repo 跑假 agent（OSC 7501：idle → working → 修改並 commit、新增檔案 → done），清單列、面板標題列與泡泡都顯示 `+3 −1 · 1 file · 1 new`，回合開始前就存在的未追蹤檔案沒有被算進去。hover card 與 Settings 開關只有編譯確認，沒有截圖驗證。

- 2026-11-11（agent）：安全修正：探測的目錄可能是不受信任的 checkout，repo 的 `.git/config` 能讓 git 執行任意指令（`core.fsmonitor`、外部 diff、textconv、pager）。`ProcessGitRunner` 每次執行都加 `-c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat -c diff.external= -c safe.bareRepository=explicit`，`git diff` 再加 `--no-ext-diff --no-textconv`。`RealGitTests` 新增回歸測試：在 repo config 埋會寫 marker 檔的 fsmonitor／diff.external／pager，確認都沒執行（拿掉 hardening 時這個測試會失敗），全套 184 個通過。
- 2026-11-11（agent）：安全修正（續）：`.gitattributes`（或 `.git/info/attributes`）可以讓檔案走 filter driver，`status`／`diff` 在雜湊修改過的檔案時會執行它的 clean／process 指令。現在每次執行前先用同樣的 hardening 跑 `git config --name-only --get-regexp ^filter\.`，把每個已定義的 driver 的 `clean`／`smudge`／`process` 設成空字串、`required=false`（列不出來就整個不執行）；另加 `core.attributesFile=/dev/null`。沒用 `GIT_ATTR_SOURCE`／`--attr-source`：empty tree 的 hash 只適用 SHA-1 repo。代價：git-lfs 的 filter 也會被停用，LFS 檔案的變更量可能不準。回歸測試加入 filter（含名稱帶點的 driver）＋`.gitattributes`＋`info/attributes`；拿掉 override 時測試會失敗。全套 185 個通過。
