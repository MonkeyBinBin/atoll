# 32: 面板檢視回合變更

**What to build:** 成果摘要（ticket 28）的 `+120 −30 · 6 files` 可以點開：面板列出這個回合變更的檔案與各自的增減行數，點檔案展開該檔的 diff，或用編輯器打開。用途是決定要回「繼續」還是要求修改，不用切到終端機或 IDE。ticket 28 把這件事列為 out of scope，本 ticket 接手。

**Blocked by:** —

**Status:** resolved

- [x] 基準與 ticket 28 相同（`TurnBaseline`）：有基準時列 `git diff --numstat <base>` 加上這個回合新出現的未追蹤檔案；沒有基準時列 `HEAD` 到 working tree，標「uncommitted」；「incl. earlier edits」「shared tree」的標示照搬，不假裝是這個 agent 的變更
- [x] 檔案清單在面板點摘要時才查，不在回合結束時預先查；每個檔案的 diff 在展開時才查（`git diff <base> -- <path>`）
- [x] git 執行沿用 `ProcessGitRunner` 的全部 hardening（`--no-optional-locks`、停用 fsmonitor／hooks／pager／external diff／textconv／filter driver），每個指令 2 秒逾時；逾時或失敗顯示「Couldn't load changes」，不重試
- [x] 顯示：檔案清單依路徑排序，顯示 `+N −M`、新增／刪除／rename 標示；binary 檔只顯示「binary」。diff 用等寬字、增刪著色，單檔超過 500 行截斷並提示「Open in editor」
- [x] 未追蹤的新檔案不讀內容，只顯示「new」與行數（行數拿不到就不顯示），可用編輯器打開
- [x] 「Open in editor」：用 `NSWorkspace` 以預設 app 打開檔案；路徑必須在該 repo 的 toplevel 之內（防 `../` 與 symlink 跳出）
- [x] 隱私：diff 內容是程式碼，比照近期輸出的規則，只在面板開著時留在記憶體，關閉面板即丟棄；不寫入磁碟。spec 隱私段落與 README 一併更新
- [x] `--numstat` 解析（含 rename 的 `old => new` 與 `{a => b}` 格式、binary 的 `-\t-`）與截斷規則放在 AtollCore，透過可替換的 runner 測試；`RealGitTests` 新增一個真 repo 案例（agent commit＋未 commit 修改＋新檔案）

**Out of scope:** 在 Atoll 內編輯、stage、revert 或 commit；side-by-side diff；語法高亮；呼叫外部 diff 工具；跨回合的累積 diff。

## Comments

- 2026-11-12（agent）：`ChangeSummary` 新增 `baseCommit`（算摘要時 diff 的那個 commit：回合開始的 HEAD，或 `.head` 時當下的 HEAD）與 `newFiles`（計入 `untracked` 的檔名），變更檢視用同一個基準，不會跟摘要數字對不上。AtollCore 新增 `TurnChanges.swift`：`ChangedFile`（`Kind`：modified／added／deleted／renamed(from:)／untracked）、`FileDiff`（去掉 git header、超過 500 行截斷並記錄省略行數）、`ChangeInspecting` 協定與 `GitProbe` 的實作。`fileURL(in:)` 解析 symlink 後必須仍在 toplevel 之內，刪除或不存在的檔案回 nil。
- 2026-11-12（agent）：跟 ticket 不同：(1) 檔案清單用 `--numstat -z` 加 `--name-status -z`，不解析 `old => new`／`{a => b}`：`-z` 的 rename 是 `\0old\0new\0`，路徑含 tab、空白、`=>` 或非 ASCII 都不會被 quote 或混淆；`-M` 開啟 rename 偵測，copy（`C`）當 added。(2) 未追蹤新檔不顯示行數：要數行就得讀檔案內容，ticket 允許拿不到就不顯示。(3) 依路徑排序用 `localizedStandardCompare`。
- 2026-11-12（agent）：`PanelState.changes`（`PanelChanges`：summary、files、diffs、expanded），`showChanges()`／`hideChanges()`／`toggleDiff(_:)`；diff 第一次展開才查、之後收合再展開不重查（失敗的會重查）。關閉面板即丟棄；agent 的摘要變了（新回合開始）就關閉檢視；晚回來的結果比對 panel address 與 summary，不符就丟掉。`changeInspector` 跟著「Change summary」設定開關。UI：面板標題列的摘要變成可點的按鈕（附 chevron），檢視取代終端輸出區，底部有「Back to output」；檔案列點擊展開，右側按鈕用 `NSWorkspace` 打開檔案。DebugHook 新增 `changes`、`difffile <path>`。
- 2026-11-12（agent）：測試：parser 6 個、GitProbe 3 個、路徑安全 2 個（`../`、`src/../../`、絕對路徑、指向外面的 symlink、刪除、不存在）、面板 6 個、真 repo 1 個（agent commit 的修改＋未 commit 的 rename、刪除與新檔，檢查清單、kind、diff 內容與 `fileURL`），全套 278 個通過。dev-run 實測：真的 Claude Code（`acceptEdits`）在暫存 repo 修改 a.txt、新增 notes.md，點摘要後列出 `M a.txt +1 −1` 與 `N notes.md new`，展開 a.txt 顯示著色的 hunk。「Open in editor」按鈕與 500 行截斷提示只有單元測試與編譯確認，沒有實際點擊。
