# 49: Follow mouse 的 timer 只在選了 Follow mouse 時才跑

**What to build:** `IslandController` 在 init 就建立每秒一次的 `followMouseTimer`，不論 Settings 的螢幕是否設為 Follow mouse 都會一直觸發（`followMouse()` 進去才 guard 掉）。改成只在設定為 Follow mouse 時啟動、改設定時停止；或改用 `NSEvent` 全域 mouse-moved monitor 加節流。

**Status:** resolved

- [x] 非 Follow mouse 時沒有任何週期性 timer 在跑
- [x] 切換設定（Follow mouse ↔ 指定螢幕）即時生效，行為與現在相同（展開時不跳螢幕）

**Out of scope:** 多螢幕定位規則本身。

## Comments

- 2026-11-13（agent）：`IslandController.updateFollowMouseTimer()` 放在 `trackChanges` 裡，依 `settings.displayID == followMouseDisplay` 建立或 invalidate 每秒一次的 timer；`followMouse()` 本身不變（展開時不跳）。改設定時的螢幕切換照舊由 `AppDelegate.applySettings` 追蹤 `displayID` 後呼叫 `refreshScreen()`。保留 1 秒輪詢而不改用 mouse-moved monitor：行為與現在完全相同，且只在 Follow mouse 時付出成本。全套 468 個通過；Settings 切換 Follow mouse 的實際操作未目視驗證。
