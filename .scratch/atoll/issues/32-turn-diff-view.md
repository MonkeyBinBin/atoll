# 32: 面板檢視回合變更

**What to build:** 成果摘要（ticket 28）的 `+120 −30 · 6 files` 可以點開：面板列出這個回合變更的檔案與各自的增減行數，點檔案展開該檔的 diff，或用編輯器打開。用途是決定要回「繼續」還是要求修改，不用切到終端機或 IDE。ticket 28 把這件事列為 out of scope，本 ticket 接手。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 基準與 ticket 28 相同（`TurnBaseline`）：有基準時列 `git diff --numstat <base>` 加上這個回合新出現的未追蹤檔案；沒有基準時列 `HEAD` 到 working tree，標「uncommitted」；「incl. earlier edits」「shared tree」的標示照搬，不假裝是這個 agent 的變更
- [ ] 檔案清單在面板點摘要時才查，不在回合結束時預先查；每個檔案的 diff 在展開時才查（`git diff <base> -- <path>`）
- [ ] git 執行沿用 `ProcessGitRunner` 的全部 hardening（`--no-optional-locks`、停用 fsmonitor／hooks／pager／external diff／textconv／filter driver），每個指令 2 秒逾時；逾時或失敗顯示「Couldn't load changes」，不重試
- [ ] 顯示：檔案清單依路徑排序，顯示 `+N −M`、新增／刪除／rename 標示；binary 檔只顯示「binary」。diff 用等寬字、增刪著色，單檔超過 500 行截斷並提示「Open in editor」
- [ ] 未追蹤的新檔案不讀內容，只顯示「new」與行數（行數拿不到就不顯示），可用編輯器打開
- [ ] 「Open in editor」：用 `NSWorkspace` 以預設 app 打開檔案；路徑必須在該 repo 的 toplevel 之內（防 `../` 與 symlink 跳出）
- [ ] 隱私：diff 內容是程式碼，比照近期輸出的規則，只在面板開著時留在記憶體，關閉面板即丟棄；不寫入磁碟。spec 隱私段落與 README 一併更新
- [ ] `--numstat` 解析（含 rename 的 `old => new` 與 `{a => b}` 格式、binary 的 `-\t-`）與截斷規則放在 AtollCore，透過可替換的 runner 測試；`RealGitTests` 新增一個真 repo 案例（agent commit＋未 commit 修改＋新檔案）

**Out of scope:** 在 Atoll 內編輯、stage、revert 或 commit；side-by-side diff；語法高亮；呼叫外部 diff 工具；跨回合的累積 diff。

## Comments
