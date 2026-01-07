import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let fullTitle = "Bible Readings for the Home Circle"
  private let shortTitle = "Bible Readings for the Home"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    titleVisibility = .visible
    titlebarAppearsTransparent = false
    updateWindowTitle()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize),
      name: NSWindow.didResizeNotification,
      object: self
    )

    super.awakeFromNib()
  }

  @objc private func windowDidResize(_ notification: Notification) {
    updateWindowTitle()
  }

  private func updateWindowTitle() {
    title = frame.width < 520 ? shortTitle : fullTitle
  }
}
