# 55: 從清單回答的型別改名與收斂

**What to build:** 54 讓提問選項沿用 permission 的回答路徑後，型別名稱與資料流都對不上實際內容（code review 的 Standards 結果）。純重構，行為不變：把「從清單／面板直接回答」整理成一致的名稱與單一入口。

**Blocked by:** —

**Status:** needs-triage

- [ ] 改名：`PermissionChoice` → 涵蓋 Allow／Deny 與提問選項的名稱（例如 `ListAnswer`），連帶 `PermissionResponseState`、`AgentStore.permissionResponses`、`PermissionResponseLabel`；`WaitingPreviewTracker.Result.choices` 改成 `permissionChoices`
- [ ] 「答案 → 按鍵」的 switch 只留一處：`AgentStore.key(for:of:)` 搬到 `Agent`（它只讀 agent 的資料），`PermissionChoices.key(for:)` 回到不接受提問選項的形狀
- [ ] 本 episode 讀到的對話框資料（preview、permission 選項、提問選項）以一個型別在 tracker → store → `Agent` 之間傳遞，不再逐欄複製
- [ ] `QuestionButtons` 與 `PermissionButtons` 共用外框（回覆狀態、送出中停用、尾端狀態標籤）；`chipTitle` 移到兩者都能用的中立位置
- [ ] header 判斷用的 `"☐☒✔"` 抽成具名常數，與 `freeText` 一致

**Out of scope:** 任何行為變更。

## Comments

- 2026-11-13（agent）：由 `8771e1d...e1ef34a` 的 code review（Standards）整理出，全是 judgement call，沒有違反文件規範。
