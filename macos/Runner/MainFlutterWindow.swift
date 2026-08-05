import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Set window background color to match splash screen (#1B64D3)
    self.backgroundColor = NSColor(calibratedRed: 0.106, green: 0.392, blue: 0.827, alpha: 1.0)
    self.isOpaque = true

    // Allow fullscreen via green button
    self.collectionBehavior.insert(.fullScreenPrimary)

    // Minimum window size
    self.minSize = NSSize(width: 1024, height: 700)

    super.awakeFromNib()
  }
}