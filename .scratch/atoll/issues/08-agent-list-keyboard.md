# 08: Agent 清單＋鍵盤導航＋全域快捷鍵

**What to build:** 點動態島上角色以外的區域、或按全域快捷鍵 `⌥⌘A`，動態島往下展開 agent 清單。卡片顯示名稱、工具、狀態與持續時間、專案目錄、Last status change、是否 Needs you；Exited 收在底部。清單內可用 `↑↓` 選擇、`Enter` 打開、`⌘1`–`⌘9` 直接跳到第 N 個、`Esc` 逐層返回。第二組全域快捷鍵直接選到最早開始等待的 agent。兩組快捷鍵可在設定修改。

**Blocked by:** 03, 05

**Status:** resolved

- [x] 清單排序與 05 的優先級一致，Exited 在底部
- [x] 卡片欄位齊全，狀態同時有文字標籤
- [x] 鍵盤操作全部可用，`Esc` 逐層收回到收合態
- [x] `⌥⌘A` 在任何 app 前景時都能展開清單
- [x] 「最早等待」快捷鍵選到正確的 agent（有 fake client 測試），沒有等待中的 agent 時不動作
- [x] 兩組快捷鍵可在設定修改並立即生效

## Comments

- 2026-11-10（agent）：清單卡片、↑↓／Enter／⌘1–9／Esc（面板→清單→收合），全域快捷鍵 `⌥⌘A`（清單）與 `⌃⌥⌘A`（最早等待；避開 ⌥⌘W 的 Close All Windows），設定中可錄製修改並立即重新註冊（Carbon `RegisterEventHotKey`，不需輔助使用權限）。
