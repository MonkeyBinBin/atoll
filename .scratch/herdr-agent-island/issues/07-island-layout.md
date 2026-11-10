# 07: 動態島完整版面

**What to build:** 動態島依 spec 的版面運作：有瀏海時黑色膠囊與瀏海融合並往兩翼延伸，無瀏海時為頂部置中膠囊；左翼釘住 Needs you 與 Error 的角色，並顯示一行提示（例如 `Codex · project-x needs you`）；右翼依優先級排列其餘角色，可用觸控板橫向捲動、兩端淡出。0 個 agent 時縮成最小膠囊。支援選擇顯示在哪個螢幕。

**Blocked by:** 05, 06

**Status:** resolved

- [x] 偵測瀏海螢幕並計算左右兩翼可用寬度，內容不落在瀏海內
- [x] 無瀏海螢幕顯示頂部置中膠囊，同樣的左右分區邏輯
- [x] 需注意的角色永遠在左翼可見，不會被捲走
- [x] 角色多到超出右翼寬度時可橫向捲動，兩端淡出提示還有更多
- [x] 提示文字只在有 Needs you 或 Error 時出現
- [x] 0 個 agent 時顯示最小膠囊加一個待機角色
- [x] 設定中可選擇顯示的螢幕；螢幕接上或拔除時位置正確更新

## Comments

- 2026-11-10（agent）：瀏海偵測用 `safeAreaInsets`＋`auxiliaryTopLeft/RightArea`，左右翼寬度分開計算；無瀏海為頂部置中膠囊。設定可選螢幕，`didChangeScreenParameters` 時重算。**註**：開發機目前只接外接螢幕，瀏海版面未在實機上目視驗證，第一次在 MacBook 內建螢幕使用時請確認。
