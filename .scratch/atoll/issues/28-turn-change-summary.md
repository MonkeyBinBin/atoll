# 28: Done 時顯示成果摘要

**What to build:** agent 跑完一個回合（Done／Exited，或從 Working 轉為 Idle，判斷規則同 ticket 24）時，在它的專案目錄算出這個回合的變更量，例如 `+120 −30 · 6 files`，顯示在泡泡、清單列與面板標題列。用途是決定這次要不要細看，以及要細看哪一個 agent。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 基準：agent 轉為 Working／Starting 時，記下 `projectPath` 所在 repo 的 `HEAD`。跑完時算基準 commit 到 working tree 的差異（`git diff --shortstat <base>`），所以 agent 自己 commit 的內容也算進去；未追蹤的新檔案另外計數（`git ls-files --others --exclude-standard`），顯示為「+N new」
- [ ] Atoll 在回合中途才啟動、沒有基準時，改算 `HEAD` 到 working tree 的差異，並標示為「uncommitted」，不冒充成這個回合的變更
- [ ] `projectPath` 不在 git repo 裡、git 不存在或執行失敗：不顯示摘要，也不顯示錯誤
- [ ] git 在背景執行，加 timeout（例如 2 秒），不擋住狀態轉換與泡泡；超時就不顯示摘要
- [ ] 沒有任何變更時顯示「no changes」，因為這本身就是有用的資訊（例如 agent 只回答了問題）
- [ ] 同一個 working tree 同時有多個 agent 時，差異無法歸屬給個別 agent：摘要加註「shared tree」（與 ticket 29 一致），不假裝是這個 agent 的變更
- [ ] 摘要只存在記憶體，下一個回合開始時清掉；Settings 可以關閉
- [ ] 解析 `--shortstat` 與組出摘要字串的邏輯放在 AtollCore（例如 `GitProbe`／`ChangeSummary`），git 執行透過可替換的 runner，以便測試：一般 diff、只有新增檔案、沒有變更、沒有基準、非 git 目錄、超時

**Out of scope:** 測試結果（目前沒有可靠來源，不從畫面猜）、在 Atoll 內顯示 diff 內容、依檔案列出變更、PR／CI 狀態。

## Comments
