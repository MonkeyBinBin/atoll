# 59: App target 的版面幾何加上測試

**What to build:** 測試 target 目前只有 `AtollCoreTests`，`Atoll` target（約 7000 行）完全沒有測試。其中瀏海、無瀏海、多螢幕的幾何計算是純邏輯，卻最容易悄悄壞掉：`ScreenGeometry.of(_:)`（從 `NSScreen` 推出瀏海位置、兩側空間、上緣高度）、`IslandLayout.compute`（收合列兩翼寬度、提示文字、space 標籤、空島、離線、捲動門檻），以及 `IslandController.updateFrame` 裡的視窗座標（左翼對齊瀏海、無瀏海置中、展開置中、夾在螢幕內）。新增一個 `AtollTests` target，用 `@testable import Atoll` 直接測 App target；只有吃 `NSScreen`、`NSPanel` 的部分需要抽出純函式。

不搬進 `AtollCore`：`IslandLayout.compute` 用 `NSFont` 量文字寬度，搬過去就得為了 core 不依賴 AppKit 的原則，把量測抽成可注入的形式。直接測 App target 量到的是真實字型，之後 App 層其他純邏輯（`SkyPalette`、`SpritePlayer.frame`、`Theme`）也能接著補測。實驗過 SwiftPM 可以 `@testable import` 這個 executable target（有 `main.swift`），跑測試不會啟動 app。

**Blocked by:** —

**Status:** resolved

- [x] `Package.swift` 新增 `AtollTests` test target（依賴 `Atoll`）；`make check` 與 CI 不用改就會一起 build、跑
- [x] `ScreenGeometry` 從 `NSScreen` 讀值的部分與計算分開：新增一個只吃數值（frame、visibleFrame、safe area top、左右 auxiliary area）的純函式，`of(_ screen:)` 改為讀 `NSScreen` 後呼叫它，行為不變
- [x] `updateFrame` 的座標計算抽成純函式（輸入 geometry、layout、展開時的寬高；輸出視窗 frame，含取整），`updateFrame` 改呼叫它，行為不變
- [x] 測試 `ScreenGeometry`：有瀏海時瀏海位置與兩側空間、`barHeight` 用 safe area；無瀏海時 menu bar 高度下限 24、`barHeight` 上限 30、中點與兩側各半；非原點的副螢幕 frame
- [x] 測試 `IslandLayout.compute`：pinned（Needs you／Error）與 others 分組、提示文字（單一、`+N`、離線文字優先）、兩翼上限（有瀏海時依兩側空間、無瀏海 360、右翼最多 8 格）與 `rightScrolls`、space 標籤（含沒有角色可顯示時、寬度上限 110）、空島膠囊、有瀏海時兩翼最小 padding、固定按鈕寬度、無瀏海的 `endInset` 與中間間隔
- [x] 測試視窗 frame：有瀏海時左翼右緣貼齊瀏海左緣、無瀏海時置中、展開時以瀏海或螢幕中線置中、超出螢幕時夾回、無瀏海時上緣留 2pt、副螢幕座標
- [x] 既有測試不改即通過；`make check` 通過，無新 warning

**Out of scope:** 改變任何版面行為或數值；App 層其他邏輯（`SkyPalette`、`SpritePlayer`、`Theme`、`AppSettings` 遷移）的測試；把任何型別搬進 `AtollCore`；SwiftUI view 的快照測試。

## Comments

- 2026-11-18（agent）：完成。`Package.swift` 新增 `AtollTests`（依賴 `Atoll`），`make check`／CI 不用改就會 build 並執行。`ScreenGeometry` 新增 `of(frame:visibleFrame:safeAreaTop:leftArea:rightArea:)`，`of(_ screen:)` 只負責讀 `NSScreen` 再轉呼叫。`updateFrame` 的座標計算移到 `ScreenGeometry.islandFrame(layout:expanded:)`，`expanded` 是 `(width, contentHeight)?`；`updateFrame` 改成組好參數後呼叫它，只在展開時才算 `expandedWidth`，跟原本一樣。邏輯都是原封不動搬移，數值不變。
- 2026-11-18（agent）：測試：`Tests/AtollTests/IslandGeometryTests.swift` 共 14 個。`ScreenGeometry` 3 個：瀏海、無瀏海與 menu bar 高度上下限、只有 safe area 沒有 menu bar 區域時不算瀏海。`IslandLayout` 7 個：空島、pinned 與提示文字、離線文字、右翼 8 格與捲動、兩翼上限、瀏海時的最小 padding、space 標籤。視窗 frame 4 個：瀏海收合、無瀏海收合、展開、夾回螢幕內與取整。文字寬度用跟 `compute` 相同的 `NSFont` 量測，所以斷言對應真實字型。把瀏海收合改成置中時有 2 個測試轉紅。踩到的坑：Swift Testing 的 `#expect(x == 1512 + 1280)` 會把右邊的整數算式當成 `Int` 求值，跟 `CGFloat` 比較時結果是 false，要寫成單一字面值。全套 522 + 14 個通過，debug／release 皆 0 warning。未實機確認：視窗位置在瀏海螢幕與外接螢幕上是否跟改動前一樣（純搬移，風險低）。
