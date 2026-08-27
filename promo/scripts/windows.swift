// Lists the on-screen windows as `id<TAB>owner<TAB>x,y,w,h<TAB>title`, so a
// capture script can find one by name and hand its id to `screencapture -l`.
// Run via: swift promo/scripts/windows.swift [owner]
//
// Window ids are what makes a clean capture possible: `screencapture -l` takes
// the window and nothing else, so the result has the real rounded corners and
// an alpha channel where the desktop would be, and the promo can put it on a
// background of its own instead of whatever wallpaper was up that day.

import CoreGraphics
import Foundation

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

guard
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]]
else {
    FileHandle.standardError.write(Data("cannot read the window list\n".utf8))
    exit(1)
}

for window in windows {
    guard
        let id = window[kCGWindowNumber as String] as? Int,
        let owner = window[kCGWindowOwnerName as String] as? String,
        let bounds = window[kCGWindowBounds as String] as? [String: Any]
    else { continue }

    if let wanted, owner != wanted { continue }

    let title = window[kCGWindowName as String] as? String ?? ""
    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    let w = bounds["Width"] as? Double ?? 0
    let h = bounds["Height"] as? Double ?? 0

    // Menu bar extras and other one-pixel scraps are never what is wanted.
    if w < 40 || h < 40 { continue }

    print("\(id)\t\(owner)\t\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))\t\(title)")
}
