import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Configure native macOS window appearance
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible
    self.styleMask.insert(.fullSizeContentView)
    
    // Set minimum window size
    self.minSize = NSSize(width: 800, height: 600)
    
    // Set window title
    self.title = "NavTool"

    super.awakeFromNib()
  }
}
