import AppKit

/// Renders a view offscreen at 2× so docs screenshots stay sharp on Retina screens.
func writeRetinaPNG(of view: NSView, to url: URL) throws {
    let size = view.bounds.size
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])?.write(to: url)
}
