import AppKit

// Agent app (LSUIElement): no Dock icon, no menu bar icon. Open it again from Finder or Spotlight
// to bring up its settings window.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
