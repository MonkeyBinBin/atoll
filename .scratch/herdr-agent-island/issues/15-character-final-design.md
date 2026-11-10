# 15: 角色定稿

**What to build:** 依 02 選定的方向，鎖定約 16 色的最終色盤，完成 Claude Code、Codex、通用三種外觀的 idle 定稿（原生 16×16），並定義個體色配件區與個體色集合；個體色必須與狀態色（錯誤紅、等待黃等）明顯區隔。

**Blocked by:** 02

**Status:** resolved

- [x] 最終色盤以明確色值記錄，並標出哪些是狀態色、哪些是個體色
- [x] 三種外觀的 idle 定稿，剪影在黑底上 1 像素 = 1pt 時可清楚區分
- [x] 個體色配件區明確，換色後角色仍可辨識且不與狀態色混淆
- [x] 與任何官方吉祥物或 logo 都沒有可辨識的相似
- [x] 定稿與色盤說明保存在 art 目錄

## Comments

- 2026-11-10（agent）：定稿色盤與 8 組個體色（亮／暗）寫在 `art/final/palette.json` 與 README；script 檢查個體色與錯誤紅、等待黃的色相距離 ≥ 40°。配件區以 key color #FF00FF／#B000B0 繪製，app 載入時換色（`SpriteSheet` 支援 `accessoryKeyDark`）。
