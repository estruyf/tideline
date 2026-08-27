// Captures one window, by id, to a PNG. Run via:
//   swift promo/scripts/grab.swift <window-id> <out.png>
//
// `screencapture -l` will not do this for a sheet: asked for a sheet's id it
// hands back the parent window with the sheet drawn into it. The review sheets
// in the README are sheets and read better on their own, so this goes through
// ScreenCaptureKit instead — one window, its own rounded corners, and alpha
// where the window behind it would be.
//
// `CGWindowListCreateImage` did the same in three lines and was obsoleted in
// macOS 15. Both ScreenCaptureKit calls below are the completion-handler forms
// rather than the `async` ones: the handlers are declared nullable, so Swift
// does not synthesise an async overload and `try await` on them quietly
// resolves to the Void-returning version instead.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 2, let wanted = UInt32(args[1]) else {
    FileHandle.standardError.write(Data("usage: grab.swift <window-id> <out.png>\n".utf8))
    exit(1)
}

// A command-line tool has no connection to the window server until something
// asks for one, and ScreenCaptureKit asserts rather than reporting that. This
// is the one line that makes a non-bundled binary able to see windows at all.
_ = NSApplication.shared

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

/// Both calls below are waited on with a semaphore. Fifteen seconds, so a
/// permission prompt nobody is there to answer cannot hang the script forever.
let timeout = DispatchTime.now() + 15

var content: SCShareableContent?
var contentError: Error?
let gotContent = DispatchSemaphore(value: 0)
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, e in
    content = c
    contentError = e
    gotContent.signal()
}
if gotContent.wait(timeout: timeout) == .timedOut { fail("timed out listing windows") }
if let contentError { fail("\(contentError)") }
guard let content else { fail("no window list came back") }

guard let window = content.windows.first(where: { $0.windowID == wanted }) else {
    fail("window \(wanted) is not on screen")
}

let configuration = SCStreamConfiguration()
// Twice the window's own size, so the PNG carries the Retina pixels the app
// actually drew rather than a resample of them.
configuration.width = Int(window.frame.width * 2)
configuration.height = Int(window.frame.height * 2)
configuration.showsCursor = false
configuration.ignoreGlobalClipSingleWindow = true

var shot: CGImage?
var shotError: Error?
let gotShot = DispatchSemaphore(value: 0)
SCScreenshotManager.captureImage(
    contentFilter: SCContentFilter(desktopIndependentWindow: window),
    configuration: configuration
) { i, e in
    shot = i
    shotError = e
    gotShot.signal()
}
if gotShot.wait(timeout: .now() + 15) == .timedOut { fail("timed out capturing") }
if let shotError { fail("\(shotError)") }
guard let image = shot else { fail("no image came back") }

let url = URL(fileURLWithPath: args[2])
guard
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )
else { fail("cannot write \(url.path)") }

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(url.path)") }

print("\(image.width)x\(image.height)")
