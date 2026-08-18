import AppKit

@MainActor
enum GhostPinAssets {
    static let logo = loadImage(named: "GhostPinLogo")
    static let statusBar = loadImage(named: "GhostPinStatusBar", isTemplate: true)

    private static func loadImage(named name: String, isTemplate: Bool = false) -> NSImage? {
        for bundle in resourceBundles {
            guard let url = bundle.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "Logo"
            ) else {
                continue
            }
            guard let image = NSImage(contentsOf: url) else {
                continue
            }
            return isTemplate ? makeMenuBarImage(from: image) : image
        }

        return nil
    }

    private static func makeMenuBarImage(from source: NSImage) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: source.size),
            operation: .destinationIn,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    private static var resourceBundles: [Bundle] {
        var bundles = [Bundle.main]
        let adjacentBundleURL = Bundle.main.bundleURL.appendingPathComponent("GhostPin_GhostPin.bundle")
        if let adjacentBundle = Bundle(url: adjacentBundleURL) {
            bundles.append(adjacentBundle)
        }
        return bundles
    }
}
