import AppKit

@main
enum TidelineApp {
    // NSApplication holds its delegate unowned, so keep a strong reference here.
    @MainActor static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
