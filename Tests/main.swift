import Foundation

try checkCodexParsing()
try checkClaudeParsing()
try checkMenuBarHUD()
try checkPanelFonts()

let full = UsageWindow(id: "full", label: "5시간", usedPercent: 0, resetsAt: nil)
let empty = UsageWindow(id: "empty", label: "5시간", usedPercent: 100, resetsAt: nil)
assert(full.remainingPercent == 100)
assert(empty.remainingPercent == 0)
assert(ProviderState().menuText == "—")
let disconnected = ProviderState(error: "키체인 접근 권한 없음")
assert(disconnected.menuText == "—" && !disconnected.isStale)
var state = ProviderState(windows: [full], updatedAt: Date())
assert(state.menuText == "100%")
state.error = "오프라인"
assert(state.menuText == "100%*")
state.error = nil
state.updatedAt = Date().addingTimeInterval(-601)
assert(state.isStale)
state = ProviderState(windows: [UsageWindow(id: "past", label: "5시간", usedPercent: 50,
    resetsAt: Date().addingTimeInterval(-1))], updatedAt: Date())
assert(state.menuText == "50%*")
print("All usage parsing and display-state checks passed.")
