import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 设置最小窗口尺寸
    self.minSize = NSSize(width: 1280, height: 900)
    
    // 确保初始窗口尺寸不小于最小尺寸
    var frame = self.frame
    if frame.size.width < 1280 || frame.size.height < 900 {
      frame.size = NSSize(width: max(frame.size.width, 1280), height: max(frame.size.height, 900))
      self.setFrame(frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
