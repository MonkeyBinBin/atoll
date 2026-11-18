# 58: issue 的完成狀態寫進 triage label 文件

**What to build:** `docs/agents/triage-labels.md` 只定義了五個 triage role（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`），沒有「做完了」的狀態。但 `.scratch/atoll/issues/` 的 56 張 ticket 做完後都標成 `resolved`。這個字只出現在 `docs/agents/issue-tracker.md` 的 Wayfinding 段落，而且那裡寫的是 wayfinding child ticket 用的（`claimed`／`resolved`），不是一般的實作 ticket。結果 agent 照文件找狀態時，會看不懂 `resolved`，也不確定做完要標什麼。另外，文件寫的格式是 `Status:` 行，實際所有 issue 都寫成 `**Status:**`（粗體），用 `grep '^Status:'` 會一張都找不到。

**Blocked by:** —

**Status:** resolved

- [x] `triage-labels.md` 補上實作 ticket 的完成狀態 `resolved`（沿用現有 56 張的寫法），並說明它是終態、跟 wayfinding 的 `resolved` 同一個字
- [x] `issue-tracker.md` 的 Conventions 寫明實際格式 `**Status:** <label>`（或改成「`Status:` 行，可加粗」），讓照著 grep 的 agent 找得到
- [x] 現有 issue 檔不改

**Out of scope:** 建立 `GLOSSARY.md`、`docs/adr/`（`domain.md` 規定由 `/domain-modeling` 在需要時才建立）；改動任何既有 issue 的內容。

## Comments

- 2026-11-18（agent）：`triage-labels.md` 新增「After triage」段落，列出 `claimed`、`resolved`（與 Wayfinding 同字），註明 `resolved` 是終態、要重開就退回某個 triage role 並在 `## Comments` 說明原因。`issue-tracker.md` 的 Conventions 改成實際格式 `**Status:** <label>`，並附上可用的 grep 寫法。既有 issue 未改動。
