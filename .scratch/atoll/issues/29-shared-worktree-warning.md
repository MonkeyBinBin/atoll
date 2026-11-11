# 29: 多個 agent 共用同一個 working tree 時警示

**What to build:** 兩個以上的 agent 同時在同一個 git working tree 裡活動時，在清單、hover card 與面板標示共用風險，提醒改用各自的 worktree。同時跑多個 agent 時，最大的損失是彼此覆蓋檔案或把對方的變更 commit 進去，事前提醒比事後處理衝突便宜得多。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 分組：對每個 agent 的 `projectPath` 跑 `git rev-parse --show-toplevel`，toplevel 相同才算共用。不同的 `git worktree` 有不同的 toplevel，不會被誤判；非 git 目錄不參與判斷
- [ ] 結果依 `projectPath` 快取，只在 `projectPath` 改變或 agent 新增時重新計算，不輪詢
- [ ] 「活動中」是指 Starting、Working、Needs you、Error。同一組裡有兩個以上的 agent 活動中才警示；Done／Idle／Exited 的 agent 不算，避免開著不用的 session 一直觸發警示
- [ ] 不聲稱是哪個 agent 改了哪些檔案：同一個 working tree 的 `git status` 是共用的，無法歸屬。警示只陳述事實：「與 Codex · project-x 共用 working tree」
- [ ] 顯示：清單列與 hover card 加圖示與文字（不能只靠顏色）；面板標題列列出同組的其他 agent。第二個 agent 開始活動時冒一次泡泡，同一組持續共用期間不再重複
- [ ] Settings 可以關閉
- [ ] 分組與「何時警示、何時再冒泡泡」的規則放在 AtollCore，git 執行透過可替換的 runner（若 ticket 28 先做了，就共用它的 `GitProbe`），並有測試：同 tree 兩個活動中、worktree 不同不警示、一個活動一個 Idle 不警示、非 git 目錄、泡泡只冒一次

**Out of scope:** 自動建立 worktree、阻止 agent 啟動、偵測不同 worktree 之間的檔案衝突、Launch 表單的 worktree 選項（另開 ticket）。

## Comments
