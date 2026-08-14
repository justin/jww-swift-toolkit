#if canImport(AppKit)
import AppKit

/// A view that displays an image with aspect fill content mode.
open class ImageAspectFillView: NSImageView {
    open override var image: NSImage? {
        get {
            return super.image
        }

        set {
            self.layer = CALayer()
            self.layer?.contentsGravity = .resizeAspectFill
            self.layer?.contents = newValue
            self.wantsLayer = true

            super.image = newValue
        }
    }

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    public init(image: NSImage?) {
        super.init(frame: .zero)
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
#endif
