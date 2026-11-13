# 49: Follow mouse 的 timer 只在選了 Follow mouse 時才跑

**What to build:** `IslandController` 在 init 就建立每秒一次的 `followMouseTimer`，不論 Settings 的螢幕是否設為 Follow mouse 都會一直觸發（`followMouse()` 進去才 guard 掉）。改成只在設定為 Follow mouse 時啟動、改設定時停止；或改用 `NSEvent` 全域 mouse-moved monitor 加節流。

**Status:** needs-triage

- [ ] 非 Follow mouse 時沒有任何週期性 timer 在跑
- [ ] 切換設定（Follow mouse ↔ 指定螢幕）即時生效，行為與現在相同（展開時不跳螢幕）

**Out of scope:** 多螢幕定位規則本身。
